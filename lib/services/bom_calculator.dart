/// lib/services/bom_calculator.dart
///
/// Pure calculation engine for the ProTPO Bill of Materials.
///
/// Design rules:
///   - No Flutter imports. Pure Dart.
///   - All inputs are passed explicitly — no global state.
///   - Every BOM line carries its full calculation trace for "hover math" display.
///   - Order quantities are always whole units (ceiling division).
///   - Waste factors come from ProjectInfo (user-configurable per project).
///
/// Formula convention:
///   orderQty = ceil( baseQty × (1 + waste) / packageSize ) × packageSize
///
/// For items with no package size (e.g. "each"), packageSize = 1.

import 'dart:math';
import '../models/project_info.dart';
import '../models/roof_geometry.dart';
import '../models/insulation_system.dart';
import '../models/section_models.dart';
import '../models/system_specs.dart';
import 'board_schedule_calculator.dart';
import '../data/qxo_pack_sizes.dart';
import '../data/versico_ma_fastening.dart';

// ─── BOM LINE ITEM ────────────────────────────────────────────────────────────

/// A single line in the BOM, including the full calculation trace.
class BomLineItem {
  final String category;      // e.g. "Primary System"
  final String name;          // e.g. "60 mil TPO Membrane (10' rolls)"
  final double orderQty;      // final order quantity (whole units)
  final String unit;          // "rolls", "bundles", "boxes", "each", "LF", "gal", "tubes"
  final String notes;         // e.g. "10'×100', 1,000 sf/roll"
  final BomTrace trace;       // full calculation breakdown for hover math

  /// When set, items sharing this key are merged into a single line by the
  /// post-process consolidator. Use a stable identifier (not the display name)
  /// for any SKU emitted from multiple sites — e.g. '3in_insulation_plates'.
  final String? consolidationKey;

  /// Display name used by the consolidator when collapsing duplicates.
  /// If null, falls back to [name] (with any "— Layer X" suffix stripped).
  final String? consolidatedName;

  /// Stable identifier for QXO catalog mapping. Independent of display name —
  /// e.g. 'tpo_membrane_field', 'fastener_insulation', 'plate_3in_insulation'.
  /// The QXO mapping service looks up (skuKey, attributes) → qxoSkuId.
  final String? skuKey;

  /// Variant attributes that discriminate between SKUs sharing the same skuKey.
  /// E.g. for `tpo_membrane_field`: {thickness: '60 mil', color: 'White',
  /// rollWidth: "10'"}. For `fastener_insulation`: {deckType: 'Steel',
  /// lengthIn: 4}. Keep keys camelCase, values JSON-serializable.
  final Map<String, dynamic>? attributes;

  const BomLineItem({
    required this.category,
    required this.name,
    required this.orderQty,
    required this.unit,
    required this.notes,
    required this.trace,
    this.consolidationKey,
    this.consolidatedName,
    this.skuKey,
    this.attributes,
  });

  /// True if this line has a non-zero quantity.
  bool get hasQuantity => orderQty > 0;
}

/// The step-by-step calculation behind a BOM line item.
/// Used to render "hover math" transparency in the UI.
class BomTrace {
  final String baseDescription;   // e.g. "8,000 sq ft ÷ 1,000 sf/roll"
  final double baseQty;           // pre-waste quantity
  final double wastePercent;      // as a fraction, e.g. 0.10 = 10%
  final double withWaste;         // baseQty × (1 + wastePercent)
  final double packageSize;       // 1 for "each", 10 for LF pieces, etc.
  final double orderQty;          // ceil(withWaste / packageSize) × packageSize
  final List<String> breakdown;   // human-readable lines shown in hover tooltip

  const BomTrace({
    required this.baseDescription,
    required this.baseQty,
    required this.wastePercent,
    required this.withWaste,
    required this.packageSize,
    required this.orderQty,
    required this.breakdown,
  });
}

// ─── BOM RESULT ───────────────────────────────────────────────────────────────

class BomResult {
  final List<BomLineItem> items;
  final List<String> warnings;    // missing inputs, incompatible assemblies
  final bool isComplete;          // false if critical inputs are missing

  const BomResult({
    required this.items,
    required this.warnings,
    required this.isComplete,
  });

  /// Items grouped by category, preserving order.
  Map<String, List<BomLineItem>> get byCategory {
    final map = <String, List<BomLineItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map;
  }

  /// All items with qty > 0.
  List<BomLineItem> get activeItems => items.where((i) => i.hasQuantity).toList();
}

// ─── CALCULATOR ───────────────────────────────────────────────────────────────

class BomCalculator {
  /// Calculates the full BOM from all project inputs.
  ///
  /// Returns a [BomResult] containing every line item, their calculation
  /// traces, and any validation warnings.
  static BomResult calculate({
    required ProjectInfo projectInfo,
    required RoofGeometry geometry,
    required SystemSpecs systemSpecs,
    required InsulationSystem insulation,
    required MembraneSystem membrane,
    required ParapetWalls parapet,
    required Penetrations penetrations,
    required MetalScope metalScope,
    BoardScheduleResult? boardSchedule,
    /// Total assembly R-value from RValueCalculator (the app's single R-value
    /// engine). When null the BOM does not judge code compliance — it used to
    /// run its own inconsistent estimate that ignored tapered insulation (eval F3).
    double? assemblyRValue,
  }) {
    final warnings = <String>[];
    final items    = <BomLineItem>[];

    final wMat  = projectInfo.wasteMaterial;   // e.g. 0.10
    final wMet  = projectInfo.wasteMetal;      // e.g. 0.05
    final wAcc  = projectInfo.wasteAccessory;  // e.g. 0.05
    final vocSuffix = projectInfo.vocRegion != 'Standard' ? ' (Low-VOC)' : '';
    final taperMaxIn = boardSchedule?.maxThicknessAtRidge ?? 0.0;

    final totalArea      = geometry.totalArea;
    // Zone areas are re-derived from the current geometry. The stored areas
    // are a snapshot taken when the zone width was last pushed; if that
    // happened before the roof dimensions were entered (or a shape was
    // removed / re-typed afterwards) they are stale — e.g. field area 0,
    // which dropped the field membrane rolls entirely.
    final zoneWidth      = geometry.windZones.perimeterZoneWidth;
    final zones          = zoneWidth > 0
        ? WindZones.fromDimensions(
            totalArea: totalArea,
            totalPerimeter: geometry.totalPerimeter,
            outsideCorners: geometry.outsideCorners > 0 ? geometry.outsideCorners : 4,
            zoneWidth: zoneWidth)
        : geometry.windZones;
    final fieldArea      = zones.fieldZoneArea;
    final perimArea      = zones.perimeterZoneArea;
    final cornerArea     = zones.cornerZoneArea;
    // TPO area for parapet walls — the VERTICAL WALL FACE only.
    // The deck-side overlap is already covered by the perimeter zone membrane.
    // The top is covered by coping metal. The flashing strip only needs to go
    // up the inside wall face from the deck transition to the termination bar.
    //
    // Per Versico spec the flashing strip extends:
    //   - From the roof deck surface up the wall to the termination point
    //   - A 4" minimum lap onto the field membrane at the base (welded)
    //
    // parapetHeight is in inches — the user-entered wall height.
    // We add 4" (0.33') for the base lap onto the field membrane.
    final parapetHeightFt = parapet.hasParapetWalls ? parapet.parapetHeight / 12.0 : 0.0;
    final parapetStripWidthFt = parapetHeightFt + 0.33; // wall height + 4" base lap
    final parapetTpoArea = parapet.hasParapetWalls
        ? parapetStripWidthFt * parapet.parapetTotalLF : 0.0;
    final termBarLF      = parapet.hasParapetWalls ? parapet.terminationBarLF : 0.0;
    final totalPerimeter = geometry.totalPerimeter;
    final drainCount     = geometry.numberOfDrains;

    // Check for minimum inputs
    final bool hasArea     = totalArea > 0;
    final bool hasZones    = geometry.windZones.perimeterZoneWidth > 0;
    final bool hasDeckType = systemSpecs.deckType.isNotEmpty;

    if (!hasArea)     warnings.add('BLOCKER: Enter roof dimensions to calculate BOM.');
    if (!hasZones && membrane.fieldAttachment == 'Rhinobond (Induction Welded)') {
      warnings.add('WARNING: Wind zone widths missing — Rhinobond plate quantities estimated from total area.');
    }
    if (!hasDeckType) warnings.add('BLOCKER: Deck type required to select fasteners.');
    if (projectInfo.warrantyYears == 0) {
      warnings.add('WARNING: Warranty years not set — fastening density defaulting to 20-year pattern.');
    }

    // Parse design wind speed for fastening density adjustment
    final windSpeedMph = _parseWindSpeed(projectInfo.designWindSpeed);
    final bool isHighWind = windSpeedMph >= 130;
    final bool isElevatedWind = windSpeedMph >= 90;
    final isRbSystem = membrane.fieldAttachment == 'Rhinobond (Induction Welded)';
    if (isRbSystem && isHighWind) {
      warnings.add('NOTE: Design wind speed ${windSpeedMph.toInt()} mph — hurricane-zone Rhinobond plate densities applied.');
    } else if (isRbSystem && isElevatedWind) {
      warnings.add('NOTE: Design wind speed ${windSpeedMph.toInt()} mph — elevated wind Rhinobond plate densities applied.');
    }

    // R-value validation
    if (assemblyRValue != null && projectInfo.requiredRValue != null &&
        projectInfo.requiredRValue! > 0 && totalArea > 0) {
      final actualR = assemblyRValue;
      if (actualR < projectInfo.requiredRValue!) {
        warnings.add('WARNING: Insulation R-value ~${actualR.toStringAsFixed(1)} may not meet code requirement of R-${projectInfo.requiredRValue!.toStringAsFixed(0)} for ${projectInfo.climateZone ?? "this zone"}.');
      }
    }

    // ── EFFECTIVE AREAS ──────────────────────────────────────────────────────
    // MA systems: Versico's fastening tables set the perimeter sheets (count ×
    // width) around the building edge — that band, not the ASCE zone width,
    // decides which area gets perimeter rolls and perimeter fastening.
    // Other systems: ASCE zones; when zone widths aren't set, all field.
    final isMASystem = membrane.fieldAttachment == 'Mechanically Attached';
    final maSched = isMASystem && totalArea > 0
        ? maFastenerSchedule(
            totalArea: totalArea,
            totalPerimeter: geometry.totalPerimeter,
            outsideCorners: geometry.outsideCorners,
            membrane: membrane,
            systemSpecs: systemSpecs,
            projectInfo: projectInfo,
            buildingHeightFt: geometry.buildingHeight,
          )
        : null;
    final effectiveFieldArea  = maSched?.field.area ?? (hasZones ? fieldArea : totalArea);
    final effectivePerimArea  = maSched?.perimeter.area ?? (hasZones ? perimArea : 0.0);
    final effectiveCornerArea = maSched != null ? 0.0 : (hasZones ? cornerArea : 0.0);
    // Perimeter/corner zones go on the narrower perimeter rolls. With the
    // perimeter roll set to "None" those zones (and parapet flashing) are
    // covered by field rolls —
    // previously that area was dropped from the membrane count altogether.
    final hasPerimRoll = membrane.perimeterRollWidth != 'None';
    final fieldRollArea = hasPerimRoll
        ? effectiveFieldArea
        : effectiveFieldArea + effectivePerimArea + effectiveCornerArea + parapetTpoArea;
    // Flashing area = parapet + perimeter zone + corner zone (all use 6'×100' rolls)
    final flashingArea = parapetTpoArea + effectivePerimArea + effectiveCornerArea;

    // ══════════════════════════════════════════════════════════════════════════
    // 1. MEMBRANE
    // ══════════════════════════════════════════════════════════════════════════

    final fieldRollCoverage = membrane.rollCoverage;         // e.g. 1000 sf
    final flashRollCoverage = membrane.perimeterRollCoverage; // always 600 sf

    // 1a. Field rolls
    if (fieldRollArea > 0) {
      final base     = fieldRollArea / fieldRollCoverage;
      final withW    = base * (1 + wMat);
      final orderQty = withW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Membrane',
        name: '${membrane.thickness} ${membrane.membraneType} — Field (${membrane.rollWidth}×100\')',
        orderQty: orderQty,
        unit: 'rolls',
        notes: '${membrane.rollWidth}×100\', ${fieldRollCoverage.toInt()} sf/roll',
        skuKey: 'tpo_membrane_field',
        attributes: {
          'membraneType': membrane.membraneType,
          'thickness':    membrane.thickness,
          'color':        membrane.color,
          'rollWidth':    membrane.rollWidth,
        },
        trace: BomTrace(
          baseDescription: '${_sf(fieldRollArea)} ÷ ${fieldRollCoverage.toInt()} sf/roll',
          baseQty: base,
          wastePercent: wMat,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            'Field area:    ${_sf(fieldRollArea)}',
            'Roll coverage: ${fieldRollCoverage.toInt()} sf/roll (${membrane.rollWidth}×100\')',
            'Base qty:      ${base.toStringAsFixed(2)} rolls',
            'Waste:         ${_pct(wMat)}%',
            'With waste:    ${withW.toStringAsFixed(2)} rolls',
            'ORDER QTY:     ${orderQty.toInt()} rolls',
          ],
        ),
      ));
    }

    // 1b. Flashing / perimeter rolls (6'×100') — skip when set to "None"
    if (flashingArea > 0 && membrane.perimeterRollWidth != 'None') {
      final base     = flashingArea / flashRollCoverage;
      final withW    = base * (1 + wMat);
      final orderQty = withW.ceil().toDouble();
      final parts = <String>[];
      if (parapetTpoArea > 0) parts.add('parapet ${_sf(parapetTpoArea)} (${parapetHeightFt.toStringAsFixed(1)}\' wall + 4" base lap)');
      if (effectivePerimArea > 0)    parts.add('perimeter zone ${_sf(effectivePerimArea)}');
      if (effectiveCornerArea > 0)   parts.add('corner zone ${_sf(effectiveCornerArea)}');
      final pRW = membrane.perimeterRollWidth;
      final pRC = membrane.perimeterRollCoverage.toInt();
      items.add(BomLineItem(
        category: 'Membrane',
        name: '${membrane.thickness} ${membrane.membraneType} — Flashing ($pRW×100\' roll, $pRC sf)',
        orderQty: orderQty,
        unit: 'rolls',
        notes: "$pRW×100', $pRC sf/roll — parapet, perimeter & corner zones",
        skuKey: 'tpo_membrane_flashing',
        attributes: {
          'membraneType': membrane.membraneType,
          'thickness':    membrane.thickness,
          'color':        membrane.color,
          'rollWidth':    pRW,
        },
        trace: BomTrace(
          baseDescription: '${_sf(flashingArea)} ÷ $pRC sf/roll',
          baseQty: base,
          wastePercent: wMat,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            'Flashing area breakdown:',
            ...parts.map((p) => '  $p'),
            'Total flashing: ${_sf(flashingArea)}',
            'Roll coverage:  $pRC sf/roll ($pRW×100\')',
            'Base qty:       ${base.toStringAsFixed(2)} rolls',
            'Waste:          ${_pct(wMat)}%',
            'With waste:     ${withW.toStringAsFixed(2)} rolls',
            'ORDER QTY:      ${orderQty.toInt()} rolls',
          ],
        ),
      ));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2. INSULATION
    // ══════════════════════════════════════════════════════════════════════════
    // Board size: 4'×8' = 32 sf. Bundle = 1 board (standard; adjust if needed).

    const double boardSf      = 32.0;  // 4'×8' board
    const double bundleBoards = 1.0;   // boards per bundle (adjustable)

    if (totalArea > 0) {
      // Layer 1 (skipped when numberOfLayers == 0, e.g. tapered/cover board only)
      final l1 = insulation.layer1;
      if (insulation.numberOfLayers >= 1 && l1.thickness > 0) {
        final base     = totalArea / boardSf;
        final withW    = base * (1 + wMat);
        final orderQty = withW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Insulation',
          name: '${l1.type} ${_ins(l1.thickness)} — Layer 1',
          orderQty: orderQty,
          unit: 'boards',
          notes: "4'×8' boards (${boardSf.toInt()} sf each), ${l1.attachmentMethod}",
          skuKey: 'iso_polyiso_flat',
          attributes: {
            'type':       l1.type,
            'thicknessIn': l1.thickness,
            'boardSize':  "4x8",
          },
          trace: _insTrace(totalArea, base, withW, orderQty, wMat, boardSf,
              'Layer 1 — ${l1.type} ${_ins(l1.thickness)}'),
        ));
      }

      // Layer 2 (if present)
      if (insulation.numberOfLayers == 2 && insulation.layer2 != null) {
        final l2 = insulation.layer2!;
        if (l2.thickness > 0) {
          final base     = totalArea / boardSf;
          final withW    = base * (1 + wMat);
          final orderQty = withW.ceil().toDouble();
          items.add(BomLineItem(
            category: 'Insulation',
            name: '${l2.type} ${_ins(l2.thickness)} — Layer 2',
            orderQty: orderQty,
            unit: 'boards',
            notes: "4'×8' boards (${boardSf.toInt()} sf each), ${l2.attachmentMethod}",
            skuKey: 'iso_polyiso_flat',
            attributes: {
              'type':       l2.type,
              'thicknessIn': l2.thickness,
              'boardSize':  "4x8",
            },
            trace: _insTrace(totalArea, base, withW, orderQty, wMat, boardSf,
                'Layer 2 — ${l2.type} ${_ins(l2.thickness)}'),
          ));
        }
      }

      // Tapered insulation
      if (insulation.hasTaper && insulation.taperDefaults != null) {
        final taper = insulation.taperDefaults!;

        if (boardSchedule != null && boardSchedule.totalTaperedPanels > 0) {
          // Per-panel-type lines from board schedule
          for (final entry in boardSchedule.taperedPanelCounts.entries) {
            final letter = entry.key;
            final count = entry.value;
            final withW = count * (1 + wMat);
            final orderQty = withW.ceil().toDouble();
            items.add(BomLineItem(
              category: 'Insulation',
              name: 'Tapered Polyiso — Panel $letter (${taper.manufacturer} ${taper.taperRate})',
              orderQty: orderQty,
              unit: 'boards',
              notes: "4'×4' tapered boards, ${taper.attachmentMethod}",
              skuKey: 'iso_polyiso_tapered_panel',
              attributes: {
                'manufacturer': taper.manufacturer,
                'taperRate':    taper.taperRate,
                'profileType':  taper.profileType,
                'panelLetter':  letter,
              },
              trace: BomTrace(
                baseDescription: '$count panels (Panel $letter) from board schedule',
                baseQty: count.toDouble(),
                wastePercent: wMat,
                withWaste: withW,
                packageSize: 1,
                orderQty: orderQty,
                breakdown: [
                  'Panel $letter count:  $count panels',
                  'Waste:               ${_pct(wMat)}%',
                  'With waste:          ${withW.toStringAsFixed(1)}',
                  'ORDER QTY:           ${orderQty.toInt()} panels',
                ],
              ),
            ));
          }

          // Flat fill lines
          final sortedFill = boardSchedule.flatFillCounts.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          for (final entry in sortedFill) {
            final thickness = entry.key;
            final count = entry.value;
            final withW = count * (1 + wMat);
            final orderQty = withW.ceil().toDouble();
            items.add(BomLineItem(
              category: 'Insulation',
              name: 'Flat Fill Polyiso ${_ins(thickness)} (${taper.manufacturer})',
              orderQty: orderQty,
              unit: 'boards',
              notes: "4'×4' flat stock under tapered panels, ${taper.attachmentMethod}",
              skuKey: 'iso_polyiso_flat_fill',
              attributes: {
                'manufacturer': taper.manufacturer,
                'thicknessIn': thickness,
                'boardSize':  "4x4",
              },
              trace: BomTrace(
                baseDescription: '$count boards (${_ins(thickness)} flat fill) from board schedule',
                baseQty: count.toDouble(),
                wastePercent: wMat,
                withWaste: withW,
                packageSize: 1,
                orderQty: orderQty,
                breakdown: [
                  'Flat fill ${_ins(thickness)} count: $count boards',
                  'Waste:                    ${_pct(wMat)}%',
                  'With waste:               ${withW.toStringAsFixed(1)}',
                  'ORDER QTY:                ${orderQty.toInt()} boards',
                ],
              ),
            ));
          }
        } else {
          // Fallback: placeholder when no board schedule (no drains placed).
          // Tapered panels are 4'×4' (16 sf), not 4'×8'.
          const taperPanelSf = 16.0;
          final taperArea = totalArea;
          final base = taperArea / taperPanelSf;
          final withW = base * (1 + wMat);
          final orderQty = withW.ceil().toDouble();
          items.add(BomLineItem(
            category: 'Insulation',
            name: 'Tapered Polyiso — ${taper.taperRate} slope',
            orderQty: orderQty,
            unit: 'boards',
            notes: 'Min ${_ins(taper.minThickness)} at drain — place drains for detailed schedule',
            skuKey: 'iso_polyiso_tapered_panel',
            attributes: {
              'manufacturer': taper.manufacturer,
              'taperRate':    taper.taperRate,
              'profileType':  taper.profileType,
              'panelLetter':  'estimated',
            },
            trace: _insTrace(taperArea, base, withW, orderQty, wMat, taperPanelSf,
                'Tapered — Polyiso (estimated, no drains placed)'),
          ));
        }
      }

      // Cover board
      if (insulation.hasCoverBoard && insulation.coverBoard != null) {
        final cb = insulation.coverBoard!;
        if (cb.thickness > 0) {
          final base     = totalArea / boardSf;
          final withW    = base * (1 + wMat);
          final orderQty = withW.ceil().toDouble();
          items.add(BomLineItem(
            category: 'Insulation',
            name: '${cb.type} ${_ins(cb.thickness)} — Cover Board',
            skuKey: 'iso_coverboard',
            attributes: {
              'type':        cb.type,
              'thicknessIn': cb.thickness,
              'boardSize':   "4x8",
            },
            orderQty: orderQty,
            unit: 'boards',
            notes: "4'×8' boards (${boardSf.toInt()} sf each), ${cb.attachmentMethod}",
            trace: _insTrace(totalArea, base, withW, orderQty, wMat, boardSf,
                'Cover Board — ${cb.type} ${_ins(cb.thickness)}'),
          ));
        }
      }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3. FASTENERS & PLATES
    // ══════════════════════════════════════════════════════════════════════════

    final isMA        = membrane.fieldAttachment == 'Mechanically Attached';
    final isRhinobond = membrane.fieldAttachment == 'Rhinobond (Induction Welded)';
    final isFA        = membrane.fieldAttachment == 'Fully Adhered';

    // Temperature/adhesive warnings per Versico spec
    if (isFA) {
      warnings.add('Bonding adhesive: apply at min 60°F. Store below 90°F. Verify tacky-not-stringy state before membrane placement.');
    }

    // ── MECHANICALLY ATTACHED (MA) ───────────────────────────────────────────
    // Through-membrane fasteners + seam plates, one row per seam:
    //   fasteners = area ÷ (net sheet width × table spacing)
    // Perimeter sheet count and spacing come from the Versico MA fastening
    // tables (maFastenerSchedule). The old flat per-sf densities (0.5–1.0/sf)
    // implied a 1–2" seam spacing and over-ordered fasteners and plates ~6×.
    if (isMA && maSched != null) {
      final sched = maSched;
      final lk = sched.lookup;
      if (!lk.isListed) {
        warnings.add('WARNING: MA fastening — ${lk.basis}.'
            '${lk.listedSheets.isEmpty ? '' : ' Versico lists: ${lk.listedSheets.join(', ')} sheets.'}'
            '${lk.status == VersicoMaStatus.contactVersico ? ' Contact Versico for approval.' : ''}');
      }
      if (projectInfo.warrantyYears > 20) {
        warnings.add('WARNING: Versico MA fastening tables cover warranties up to 20 years — '
            '${projectInfo.warrantyYears}-yr requires Versico approval; quantities use the 20-yr table.');
      }
      if (systemSpecs.deckType == 'Wood' && systemSpecs.woodDeckGrade.contains('OSB') &&
          projectInfo.warrantyYears > 20) {
        warnings.add('WARNING: Versico limits OSB decks to 20-year warranties.');
      }
      if (geometry.buildingHeight <= 0) {
        warnings.add('NOTE: Building height not set — MA fastening assumes ≤60\' building.');
      }
      final fieldFast  = sched.field.fasteners;
      final perimFast  = sched.perimeter.fasteners;
      final cornerFast = sched.corner.fasteners;
      final totalFast  = fieldFast + perimFast + cornerFast;
      String zoneLine(String label, MaZoneFastening z) =>
          '$label${_sf(z.area)} ÷ (${z.netSheetWidthFt.toStringAsFixed(1)}\' net sheet × ${z.spacingIn.toInt()}" o.c.) = ${z.fasteners.toStringAsFixed(0)}';

      final fastenerName = _fastenerName(systemSpecs.deckType);
      final memStackIn   = _stackThicknessIn(insulation, 3, taperMaxThickness: taperMaxIn);
      final memFastLen   = _selectFastenerLen(systemSpecs.deckType, memStackIn);
      final boxSize  = _fastenerPack(systemSpecs.deckType, memStackIn).toDouble();
      final withW    = totalFast * (1 + wAcc);
      final orderQty = (withW / boxSize).ceil().toDouble();

      items.add(BomLineItem(
        category: 'Fasteners & Plates',
        name: '$fastenerName $memFastLen — ${systemSpecs.deckType} Deck (MA Membrane)',
        skuKey: 'fastener_membrane',
        attributes: {
          'fastenerName': fastenerName,
          'length':       memFastLen,
          'deckType':     systemSpecs.deckType,
        },
        orderQty: orderQty,
        unit: 'cartons',
        notes: '${boxSize.toInt()}/carton (QXO) — field & perimeter sheets',
        trace: BomTrace(
          baseDescription: '${totalFast.toStringAsFixed(0)} fasteners ÷ ${boxSize.toInt()}/carton',
          baseQty: totalFast,
          wastePercent: wAcc,
          withWaste: withW,
          packageSize: boxSize,
          orderQty: orderQty,
          breakdown: [
            _fastenerBreakdown(systemSpecs.deckType, memStackIn, 'MA membrane fastener'),
            lk.basis,
            'Perimeter band: ${lk.perimeterSheets} × ${sched.perimeter.netSheetWidthFt.toStringAsFixed(2)}\' = ${sched.perimeterBandFt.toStringAsFixed(1)}\' around ${_lf(geometry.totalPerimeter)}',
            zoneLine('Field sheets:     ', sched.field),
            zoneLine('Perimeter sheets: ', sched.perimeter),
            'Total fasteners: ${totalFast.toStringAsFixed(0)}',
            'Waste: ${_pct(wAcc)}%  →  With waste: ${withW.toStringAsFixed(0)}',
            'ORDER QTY: ${orderQty.toInt()} cartons (${boxSize.toInt()}/carton)',
          ],
        ),
      ));

      // Seam fastening plates — one per MA fastener. Versico pairs HPVX with
      // 2.38" HPVX Steel Fastening Plates; HPV / MP 14-10 / CD-10 use 2" Seam
      // Fastening Plates. (3" plates are insulation plates, not seam plates.)
      final isHpvx       = fastenerName.contains('HPVX');
      final plateLabel   = isHpvx ? '2.38" HPVX Fastening Plates' : '2" Seam Fastening Plates';
      final plateBoxSize = (isHpvx ? kQxoHpvxPlatePack : kQxoSeamPlate2inPack).toDouble();
      final plateWithW   = totalFast * (1 + wAcc);
      final plateOrder   = (plateWithW / plateBoxSize).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Fasteners & Plates',
        name: plateLabel,
        skuKey: 'plate_seam_stress_3in', // stable key; plate size is an attribute
        attributes: {'plateSize': isHpvx ? '2.38"' : '2"', 'fastener': isHpvx ? 'HPVX' : 'HPV'},
        orderQty: plateOrder,
        unit: 'cartons',
        notes: '${plateBoxSize.toInt()}/carton (QXO) — one plate per MA fastener',
        trace: BomTrace(
          baseDescription: '${totalFast.toStringAsFixed(0)} plates ÷ ${plateBoxSize.toInt()}/carton',
          baseQty: totalFast,
          wastePercent: wAcc,
          withWaste: plateWithW,
          packageSize: plateBoxSize,
          orderQty: plateOrder,
          breakdown: [
            'One seam plate per fastener: ${totalFast.toStringAsFixed(0)}',
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${plateOrder.toInt()} cartons (${plateBoxSize.toInt()}/carton)',
          ],
        ),
      ));
    }

    // ── RHINOBOND (INDUCTION WELDED) ──────────────────────────────────────────
    // Versico Rhinobond: steel plates fastened through insulation to deck,
    // then membrane inductively welded to plate tops — no through-membrane fasteners.
    //
    // BOM has THREE separate line items:
    //   1. Rhinobond induction weld plates (500/carton per QXO)
    //   2. Fasteners for plates — same sizing logic as MA, one per plate
    //   3. Insulation fasteners (handled below in insulation section, same as MA)
    //
    // Plate density is ~33–50% of MA fastener density (larger bond area per plate).
    // Source: Versico Rhinobond TPO Installation Guide & FM approval tables.
    if (isRhinobond && totalArea > 0) {
      final rbEffWarranty   = _windAdjustedWarranty(projectInfo.warrantyYears, windSpeedMph);
      final rbDensities     = _rhinobondDensities(rbEffWarranty);
      final rbFieldDensity  = rbDensities.$1;
      final rbPerimDensity  = rbDensities.$2;
      final rbCornerDensity = rbDensities.$3;

      final rbFieldPlates  = (hasZones ? effectiveFieldArea  : totalArea) * rbFieldDensity;
      final rbPerimPlates  = hasZones ? effectivePerimArea  * rbPerimDensity  : 0.0;
      final rbCornerPlates = hasZones ? effectiveCornerArea * rbCornerDensity : 0.0;
      final rbTotalPlates  = rbFieldPlates + rbPerimPlates + rbCornerPlates;

      // ── Rhinobond induction weld plates ──────────────────────────────────
      final rbCartonSize = kQxoRhinobondPlatePack.toDouble(); // QXO: 3" RhinoBond TPO Plates
      final rbPlateWithW = rbTotalPlates * (1 + wAcc);
      final rbPlateOrder = (rbPlateWithW / rbCartonSize).ceil().toDouble();

      items.add(BomLineItem(
        category: 'Fasteners & Plates',
        name: 'Rhinobond Induction Weld Plates',
        skuKey: 'plate_rhinobond',
        attributes: const {},
        orderQty: rbPlateOrder,
        unit: 'cartons',
        notes: '${rbCartonSize.toInt()}/carton (QXO) — Versico Rhinobond TPO system',
        trace: BomTrace(
          baseDescription: '${rbTotalPlates.toStringAsFixed(0)} plates ÷ ${rbCartonSize.toInt()}/carton',
          baseQty: rbTotalPlates,
          wastePercent: wAcc,
          withWaste: rbPlateWithW,
          packageSize: rbCartonSize,
          orderQty: rbPlateOrder,
          breakdown: [
            'Rhinobond plate grid (${projectInfo.warrantyYears}-yr warranty):',
            '  Field density:   ${rbFieldDensity.toStringAsFixed(3)}/sf',
            '  Perim density:   ${rbPerimDensity.toStringAsFixed(3)}/sf',
            '  Corner density:  ${rbCornerDensity.toStringAsFixed(3)}/sf',
            if (hasZones) ...[
              'Field zone:     ${_sf(rbFieldPlates)} plates',
              'Perimeter zone: ${_sf(rbPerimPlates)} plates',
              'Corner zone:    ${_sf(rbCornerPlates)} plates',
            ] else
              'Total area (no zones): ${_sf(rbTotalPlates)} plates',
            'Total plates: ${rbTotalPlates.toStringAsFixed(0)}',
            'Waste: ${_pct(wAcc)}%  →  With waste: ${rbPlateWithW.toStringAsFixed(0)}',
            'ORDER QTY: ${rbPlateOrder.toInt()} cartons (${rbCartonSize.toInt()}/carton)',
          ],
        ),
      ));

      // ── Fasteners for Rhinobond plates (one per plate, through insulation to deck) ─
      final memStackIn   = _stackThicknessIn(insulation, 3, taperMaxThickness: taperMaxIn);
      final rbFastName   = _fastenerName(systemSpecs.deckType);
      final rbFastLen    = _selectFastenerLen(systemSpecs.deckType, memStackIn);
      final rbFastBox    = _fastenerPack(systemSpecs.deckType, memStackIn).toDouble();
      final rbFastWithW  = rbTotalPlates * (1 + wAcc);
      final rbFastOrder  = (rbFastWithW / rbFastBox).ceil().toDouble();

      items.add(BomLineItem(
        category: 'Fasteners & Plates',
        name: '$rbFastName $rbFastLen — ${systemSpecs.deckType} Deck (Rhinobond)',
        skuKey: 'fastener_rhinobond',
        attributes: {
          'fastenerName': rbFastName,
          'length':       rbFastLen,
          'deckType':     systemSpecs.deckType,
        },
        orderQty: rbFastOrder,
        unit: 'cartons',
        notes: '${rbFastBox.toInt()}/carton (QXO) — one fastener per Rhinobond plate',
        trace: BomTrace(
          baseDescription: '${rbTotalPlates.toStringAsFixed(0)} fasteners ÷ ${rbFastBox.toInt()}/carton',
          baseQty: rbTotalPlates,
          wastePercent: wAcc,
          withWaste: rbFastWithW,
          packageSize: rbFastBox,
          orderQty: rbFastOrder,
          breakdown: [
            _fastenerBreakdown(systemSpecs.deckType, memStackIn, 'Rhinobond plate fastener'),
            'One fastener per plate: ${rbTotalPlates.toStringAsFixed(0)}',
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${rbFastOrder.toInt()} cartons (${rbFastBox.toInt()}/carton)',
          ],
        ),
      ));
    }

    // Insulation fasteners — only the TOPMOST mechanically-attached layer emits
    // fasteners. The fastener length is sized to penetrate the full stack from
    // that layer down to the deck, capturing all layers below in the same pass.
    // Emitting fasteners for every MA layer independently double-attaches and
    // over-orders. When redundant MA flags are detected, a warning is added.
    // Rhinobond: the Rhinobond plates + their fasteners are the only
    // attachment — no separate insulation fasteners or 3" plates.
    if (totalArea > 0 && !isRhinobond) {
      final l1MA = insulation.numberOfLayers >= 1 &&
          insulation.layer1.attachmentMethod == 'Mechanically Attached';
      final l2MA = insulation.numberOfLayers == 2 &&
          (insulation.layer2?.attachmentMethod == 'Mechanically Attached' ?? false);
      final taperMAFlag = insulation.hasTaper &&
          insulation.taperDefaults != null &&
          insulation.taperDefaults!.attachmentMethod == 'Mechanically Attached';
      final cbMA = insulation.hasCoverBoard &&
          (insulation.coverBoard?.attachmentMethod == 'Mechanically Attached' ?? false);

      // Topmost MA wins: cover board > tapered > L2 > L1.
      final effectiveCbMA    = cbMA;
      final effectiveTaperMA = taperMAFlag && !cbMA;
      final effectiveL2MA    = l2MA && !taperMAFlag && !cbMA;
      final effectiveL1MA    = l1MA && !l2MA && !taperMAFlag && !cbMA;

      final maCount = (l1MA ? 1 : 0) + (l2MA ? 1 : 0) + (taperMAFlag ? 1 : 0) + (cbMA ? 1 : 0);
      if (maCount > 1) {
        final topName = cbMA ? 'cover board' : (taperMAFlag ? 'tapered insulation' : (l2MA ? 'Layer 2' : 'Layer 1'));
        warnings.add(
          'NOTE: $maCount insulation layers marked Mechanically Attached — '
          'fasteners emitted only for topmost ($topName), which captures lower '
          'layers in a single pass. Set lower layers to "Adhered" if redundant '
          'attachment was unintended.',
        );
      }

      final insDensity = _insulationDensity(projectInfo.warrantyYears, systemSpecs.deckType);
      final perBoard = (insDensity * 32).round(); // fasteners per 4'×8' board

      // Layer 1 MA: fastener only passes through layer 1 stack
      if (effectiveL1MA) {
        final l1StackIn = _stackThicknessIn(insulation, 1);
        final l1Len     = _selectFastenerLen(systemSpecs.deckType, l1StackIn);
        final insBoxSize = _fastenerPack(systemSpecs.deckType, l1StackIn).toDouble();
        final base      = totalArea * insDensity;
        final withW     = base * (1 + wAcc);
        final orderQty  = (withW / insBoxSize).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '${_fastenerName(systemSpecs.deckType)} $l1Len — Layer 1 Insulation',
          skuKey: 'fastener_insulation',
          attributes: {
            'fastenerName': _fastenerName(systemSpecs.deckType),
            'length':       l1Len,
            'deckType':     systemSpecs.deckType,
          },
          orderQty: orderQty,
          unit: 'cartons',
          notes: '${insBoxSize.toInt()}/carton (QXO) — $perBoard per 4\'×8\' board (${insulation.layer1.type})',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} fasteners ÷ ${insBoxSize.toInt()}/carton',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: insBoxSize,
            orderQty: orderQty,
            breakdown: [
              _fastenerBreakdown(systemSpecs.deckType, l1StackIn, 'Layer 1 fastener'),
              '${_sf(totalArea)} × $insDensity/sf = ${base.toStringAsFixed(0)} fasteners',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${orderQty.toInt()} cartons (${insBoxSize.toInt()}/carton)',
            ],
          ),
        ));

        // Insulation plates for Layer 1 — one plate per fastener
        const l1PlateBoxSize = 1000.0;
        final l1PlateOrder = (withW / l1PlateBoxSize).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '3" Insulation Plates — Layer 1',
          consolidationKey: 'plates_3in_insulation',
          skuKey: 'plate_3in_insulation',
          attributes: const {},
          consolidatedName: '3" Insulation Plates',
          orderQty: l1PlateOrder,
          unit: 'cartons',
          notes: '1,000/carton (QXO) — one plate per insulation fastener',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} plates ÷ 1,000/carton',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: l1PlateBoxSize,
            orderQty: l1PlateOrder,
            breakdown: [
              'One 3" galv plate per insulation fastener',
              '${_sf(totalArea)} × $insDensity/sf = ${base.toStringAsFixed(0)} plates',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${l1PlateOrder.toInt()} cartons (1,000/carton)',
            ],
          ),
        ));
      }

      // Layer 2 MA: fastener passes through BOTH layer 2 AND layer 1 to reach deck
      if (effectiveL2MA) {
        final l2StackIn = _stackThicknessIn(insulation, 2); // L1 + L2 thickness
        final l2Len     = _selectFastenerLen(systemSpecs.deckType, l2StackIn);
        final insBoxSize = _fastenerPack(systemSpecs.deckType, l2StackIn).toDouble();
        final base      = totalArea * insDensity;
        final withW     = base * (1 + wAcc);
        final orderQty  = (withW / insBoxSize).ceil().toDouble();
        final l2type    = insulation.layer2?.type ?? '';
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '${_fastenerName(systemSpecs.deckType)} $l2Len — Layer 2 Insulation',
          skuKey: 'fastener_insulation',
          attributes: {
            'fastenerName': _fastenerName(systemSpecs.deckType),
            'length':       l2Len,
            'deckType':     systemSpecs.deckType,
          },
          orderQty: orderQty,
          unit: 'cartons',
          notes: '${insBoxSize.toInt()}/carton (QXO) — $perBoard per 4\'×8\' board, through L1+L2 ($l2type)',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} fasteners ÷ ${insBoxSize.toInt()}/carton',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: insBoxSize,
            orderQty: orderQty,
            breakdown: [
              _fastenerBreakdown(systemSpecs.deckType, l2StackIn, 'Layer 2 fastener (thru L1+L2)'),
              'Note: L2 fastener must pass through L1 to reach deck',
              '${_sf(totalArea)} × $insDensity/sf = ${base.toStringAsFixed(0)} fasteners',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${orderQty.toInt()} cartons (${insBoxSize.toInt()}/carton)',
            ],
          ),
        ));

        // Insulation plates for Layer 2 — one plate per fastener
        const l2PlateBoxSize = 1000.0;
        final l2PlateOrder = (withW / l2PlateBoxSize).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '3" Insulation Plates — Layer 2',
          consolidationKey: 'plates_3in_insulation',
          skuKey: 'plate_3in_insulation',
          attributes: const {},
          consolidatedName: '3" Insulation Plates',
          orderQty: l2PlateOrder,
          unit: 'cartons',
          notes: '1,000/carton (QXO) — one plate per insulation fastener',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} plates ÷ 1,000/carton',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: l2PlateBoxSize,
            orderQty: l2PlateOrder,
            breakdown: [
              'One 3" galv plate per insulation fastener',
              '${_sf(totalArea)} × $insDensity/sf = ${base.toStringAsFixed(0)} plates',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${l2PlateOrder.toInt()} cartons (1,000/carton)',
            ],
          ),
        ));
      }

      // Tapered insulation MA: fastener passes through flat layers + tapered max.
      // When no board schedule exists yet (no drains placed) the ridge thickness
      // is unknown — still emit the fasteners over the full roof area, size the
      // length from the min thickness, and warn that the length is an estimate.
      // Skipping the line entirely silently under-orders (eval F1).
      if (effectiveTaperMA) {
        final taperEstimated = taperMaxIn <= 0;
        final taperThickForLen = taperEstimated
            ? (insulation.taperDefaults?.minThickness ?? 0.0)
            : taperMaxIn;
        if (taperEstimated) {
          warnings.add('WARNING: Tapered insulation fastener length estimated from '
              'min thickness — place drains to size fasteners for the ridge thickness.');
        }
        // Stack = flat layers + tapered max thickness (no cover board)
        double taperStackIn = 0;
        if (insulation.numberOfLayers >= 1) taperStackIn += insulation.layer1.thickness;
        if (insulation.numberOfLayers == 2 && insulation.layer2 != null) taperStackIn += insulation.layer2!.thickness;
        taperStackIn += taperThickForLen;
        final taperLen  = _selectFastenerLen(systemSpecs.deckType, taperStackIn) +
            (taperEstimated ? ' (est.)' : '');
        final insBoxSize = _fastenerPack(systemSpecs.deckType, taperStackIn).toDouble();
        // An empty schedule (rate 0, no drain distance) reports 0 tapered SF;
        // treat it like "no schedule" or the roof gets no insulation fasteners.
        final schedSF   = boardSchedule?.totalTaperedSF ?? 0.0;
        final taperSF   = schedSF > 0 ? schedSF : totalArea;
        final base      = taperSF * insDensity;
        final withW     = base * (1 + wAcc);
        final orderQty  = (withW / insBoxSize).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '${_fastenerName(systemSpecs.deckType)} $taperLen — Tapered Insulation (max)',
          skuKey: 'fastener_insulation',
          attributes: {
            'fastenerName': _fastenerName(systemSpecs.deckType),
            'length':       taperLen,
            'deckType':     systemSpecs.deckType,
          },
          orderQty: orderQty,
          unit: 'cartons',
          notes: taperEstimated
              ? '${insBoxSize.toInt()}/carton (QXO) — length estimated (no drains placed)'
              : '${insBoxSize.toInt()}/carton (QXO) — sized for max thickness ${_ins(taperMaxIn)} at ridge',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} fasteners ÷ ${insBoxSize.toInt()}/carton',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: insBoxSize,
            orderQty: orderQty,
            breakdown: [
              _fastenerBreakdown(systemSpecs.deckType, taperStackIn, 'Tapered ISO fastener (at max thickness)'),
              taperEstimated
                  ? 'Note: No board schedule — length based on min thickness ${_ins(taperThickForLen)}; place drains to size for ridge'
                  : 'Note: Fastener length based on max taper thickness ${_ins(taperMaxIn)} at ridge',
              '${_sf(taperSF)} tapered area × $insDensity/sf = ${base.toStringAsFixed(0)} fasteners',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${orderQty.toInt()} cartons (${insBoxSize.toInt()}/carton)',
            ],
          ),
        ));

        // Insulation plates for tapered — one plate per fastener
        const taperPlateBoxSize = 1000.0;
        final taperPlateOrder = (withW / taperPlateBoxSize).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '3" Insulation Plates — Tapered Insulation',
          consolidationKey: 'plates_3in_insulation',
          skuKey: 'plate_3in_insulation',
          attributes: const {},
          consolidatedName: '3" Insulation Plates',
          orderQty: taperPlateOrder,
          unit: 'cartons',
          notes: '1,000/carton (QXO) — one plate per insulation fastener',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} plates ÷ 1,000/carton',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: taperPlateBoxSize,
            orderQty: taperPlateOrder,
            breakdown: [
              'One 3" galv plate per tapered insulation fastener',
              '${_sf(taperSF)} tapered area × $insDensity/sf = ${base.toStringAsFixed(0)} plates',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${taperPlateOrder.toInt()} cartons (1,000/carton)',
            ],
          ),
        ));
      }

      // Cover board MA: passes through cover board + insulation stack
      if (effectiveCbMA) {
        final cbStackIn = _stackThicknessIn(insulation, 3, taperMaxThickness: taperMaxIn); // full stack
        final cbLen     = _selectFastenerLen(systemSpecs.deckType, cbStackIn);
        final insBoxSize = _fastenerPack(systemSpecs.deckType, cbStackIn).toDouble();
        final base      = totalArea * insDensity;
        final withW     = base * (1 + wAcc);
        final orderQty  = (withW / insBoxSize).ceil().toDouble();
        final cbtype    = insulation.coverBoard?.type ?? 'Cover Board';
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '${_fastenerName(systemSpecs.deckType)} $cbLen — Cover Board',
          skuKey: 'fastener_insulation',
          attributes: {
            'fastenerName': _fastenerName(systemSpecs.deckType),
            'length':       cbLen,
            'deckType':     systemSpecs.deckType,
          },
          orderQty: orderQty,
          unit: 'cartons',
          notes: '${insBoxSize.toInt()}/carton (QXO) — $perBoard per 4\'×8\' board ($cbtype)',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} fasteners ÷ ${insBoxSize.toInt()}/carton',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: insBoxSize,
            orderQty: orderQty,
            breakdown: [
              _fastenerBreakdown(systemSpecs.deckType, cbStackIn, 'Cover board fastener (full stack)'),
              'Note: Cover board fastener penetrates full insulation stack',
              '${_sf(totalArea)} × $insDensity/sf = ${base.toStringAsFixed(0)} fasteners',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${orderQty.toInt()} cartons (${insBoxSize.toInt()}/carton)',
            ],
          ),
        ));

        // Insulation plates for Cover Board — one plate per fastener
        const cbPlateBoxSize = 1000.0;
        final cbPlateOrder = (withW / cbPlateBoxSize).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '3" Insulation Plates — Cover Board',
          consolidationKey: 'plates_3in_insulation',
          skuKey: 'plate_3in_insulation',
          attributes: const {},
          consolidatedName: '3" Insulation Plates',
          orderQty: cbPlateOrder,
          unit: 'cartons',
          notes: '1,000/carton (QXO) — one plate per insulation fastener',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} plates ÷ 1,000/carton',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: cbPlateBoxSize,
            orderQty: cbPlateOrder,
            breakdown: [
              'One 3" galv plate per cover board fastener',
              '${_sf(totalArea)} × $insDensity/sf = ${base.toStringAsFixed(0)} plates',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${cbPlateOrder.toInt()} cartons (1,000/carton)',
            ],
          ),
        ));
      }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4. ADHESIVES & SEALANTS
    // ══════════════════════════════════════════════════════════════════════════

    // Bonding adhesive — split into membrane-bond (VersiWeld) and insulation-bond (OlyBond).
    // VersiWeld TPO Bonding Adhesive is for membrane-to-substrate only.
    // Insulation adhered to deck or to itself uses OlyBond500 / FAST 100LV (separate SKU).
    final adheredMembraneArea = isFA ? totalArea : 0.0;

    final adheredInsulationLayers = [
      if (insulation.numberOfLayers >= 1 && insulation.layer1.attachmentMethod == 'Adhered') 1,
      if (insulation.numberOfLayers == 2 &&
          (insulation.layer2?.attachmentMethod == 'Adhered' ?? false)) 1,
      if (insulation.hasTaper && insulation.taperDefaults != null &&
          insulation.taperDefaults!.attachmentMethod == 'Adhered')
        1,
      if (insulation.hasCoverBoard &&
          (insulation.coverBoard?.attachmentMethod == 'Adhered' ?? false)) 1,
    ].length;
    final adheredInsArea = adheredInsulationLayers * totalArea;

    // ── Membrane bonding adhesive (membrane-to-substrate only) ────────────────
    if (adheredMembraneArea > 0) {
      final isSprayAdhesive = membrane.adhesiveType == kAdhesiveCavGrip;

      if (isSprayAdhesive) {
        // CAV-GRIP 3V spray: ~2,000 sf per #40 cylinder. [Unverified] Midpoint
        // of the ~1,500–2,500 sf published range; 400 sf over-ordered ~5×.
        const coveragePerCyl = 2000.0;
        final cylBase = adheredMembraneArea / coveragePerCyl;
        final cylWithW = cylBase * (1 + wAcc);
        final cylOrder = cylWithW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Adhesives & Sealants',
          name: 'Versico CAV-GRIP 3V Low-VOC Adhesive/Primer$vocSuffix — #40 Cylinder (Field)',
          skuKey: 'adhesive_cavgrip_3v_40lb',
          attributes: {'voc': projectInfo.vocRegion, 'application': 'field'},
          orderQty: cylOrder,
          unit: 'cylinders',
          notes: '#40 cylinder, ~${coveragePerCyl.toInt()} sf/cyl — spray application, field membrane only',
          trace: BomTrace(
            baseDescription: '${_sf(adheredMembraneArea)} ÷ ${coveragePerCyl.toInt()} sf/cyl',
            baseQty: cylBase,
            wastePercent: wAcc,
            withWaste: cylWithW,
            packageSize: 1,
            orderQty: cylOrder,
            breakdown: [
              'FA membrane area: ${_sf(adheredMembraneArea)}',
              'Coverage rate: ~${coveragePerCyl.toInt()} sf per #40 cylinder',
              'Base: ${cylBase.toStringAsFixed(2)} cylinders',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${cylOrder.toInt()} cylinders',
            ],
          ),
        ));
        // Also add UN-TACK for field CAV-GRIP 3V
        items.add(BomLineItem(
          category: 'Adhesives & Sealants',
          name: 'Versico UN-TACK Adhesive Remover & Cleaner — #8 Aerosol (Field)',
          skuKey: 'cleaner_untack_8oz_aerosol',
          attributes: {'application': 'field'},
          orderQty: cylOrder,
          unit: 'aerosols',
          notes: '#8 aerosol — one per CAV-GRIP 3V cylinder',
          trace: BomTrace(
            baseDescription: '1:1 ratio with CAV-GRIP 3V cylinders',
            baseQty: cylBase,
            wastePercent: wAcc,
            withWaste: cylWithW,
            packageSize: 1,
            orderQty: cylOrder,
            breakdown: ['One UN-TACK per CAV-GRIP 3V cylinder', 'ORDER QTY: ${cylOrder.toInt()} aerosols'],
          ),
        ));
      } else {
        // VersiWeld bonding adhesive: 60 sf/gal, ordered in 5-gal pails.
        const coveragePerGal = 60.0;
        const packageGal = 5.0;
        final base  = adheredMembraneArea / coveragePerGal;
        final withW = base * (1 + wAcc);
        final orderQty = (withW / packageGal).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Adhesives & Sealants',
          name: 'VersiWeld TPO Bonding Adhesive$vocSuffix — 5 Gal Pail',
          skuKey: 'adhesive_versiweld_bonding',
          attributes: {'voc': projectInfo.vocRegion, 'packageGal': 5, 'application': 'field'},
          orderQty: orderQty,
          unit: 'pails',
          notes: '5-gal pail, ~60 sf/gal — field membrane only',
          trace: BomTrace(
            baseDescription: '${_sf(adheredMembraneArea)} ÷ 60 sf/gal',
            baseQty: base, wastePercent: wAcc, withWaste: withW,
            packageSize: packageGal, orderQty: orderQty,
            breakdown: [
              'FA membrane area: ${_sf(adheredMembraneArea)}',
              'Coverage rate: 60 sf/gal',
              'Base gallons:  ${base.toStringAsFixed(1)}',
              'Waste:         ${_pct(wAcc)}%',
              'With waste:    ${withW.toStringAsFixed(1)} gal',
              'ORDER QTY:     ${orderQty.toInt()} pails (5-gal each)',
            ],
          ),
        ));
      }
    }

    // ── Insulation adhesive (separate SKU from membrane bond) ─────────────────
    // Per Versico spec, insulation adhered to deck or underlying insulation uses a
    // dual-cartridge urethane adhesive (OlyBond500 / FAST 100LV).
    // Coverage @ 12" o.c. ribbon application: ~1,500 sf per dual-cartridge set.
    if (adheredInsulationLayers > 0) {
      const sfPerSet = 1500.0;
      final base = adheredInsArea / sfPerSet;
      final withW = base * (1 + wAcc);
      final orderQty = withW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Adhesives & Sealants',
        name: 'OlyBond500 Insulation Adhesive (or FAST 100LV) — Dual Cartridge Set',
        skuKey: 'adhesive_olybond_500_set',
        attributes: const {},
        orderQty: orderQty,
        unit: 'sets',
        notes: '~1,500 sf/set @ 12" o.c. ribbons — adhered insulation layers',
        trace: BomTrace(
          baseDescription: '${_sf(adheredInsArea)} ÷ 1,500 sf/set',
          baseQty: base,
          wastePercent: wAcc,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            'Adhered insulation layers: $adheredInsulationLayers',
            '  ($adheredInsulationLayers × ${_sf(totalArea)} = ${_sf(adheredInsArea)} adhered area)',
            'Coverage: ~1,500 sf per dual-cartridge set @ 12" o.c. ribbons',
            'Base sets:  ${base.toStringAsFixed(2)}',
            'Waste:      ${_pct(wAcc)}%',
            'With waste: ${withW.toStringAsFixed(2)} sets',
            'ORDER QTY:  ${orderQty.toInt()} sets',
          ],
        ),
      ));
    }

    // ── Parapet wall adhesive & cleaner (always adhered, separate products) ──
    if (parapetTpoArea > 0) {
      // Versico spec: bonding adhesive is NOT required on short parapet walls when:
      //   - Wall height ≤ 12" and membrane is terminated under metal counterflashing/drip edge
      //   - Wall height ≤ 18" and a termination bar is used
      final parapetHeightIn = parapet.parapetHeight; // already in inches
      final skipParapetAdhesive =
          (parapetHeightIn <= 12) || // ≤12" with any termination (drip edge / counterflashing)
          (parapetHeightIn <= 18 && parapet.terminationType == 'Termination Bar');

      if (skipParapetAdhesive) {
        warnings.add('Parapet adhesive omitted — wall height ${parapetHeightIn.toInt()}" per Versico spec (no adhesive required for short walls with ${parapet.terminationType.toLowerCase()}).');
      } else if (parapet.parapetAdhesiveType == kAdhesiveCavGrip) {
        // CAV-GRIP 3V Low-VOC: ~2,000 sf per #40 cylinder [Unverified] — same
        // coverage basis as the field spray line.
        const cavGripCoverage = 2000.0;
        final cavBase      = parapetTpoArea / cavGripCoverage;
        final cavWithW     = cavBase * (1 + wAcc);
        final cavOrder     = cavWithW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Adhesives & Sealants',
          name: 'Versico CAV-GRIP 3V Low-VOC Adhesive/Primer$vocSuffix — #40 Cylinder',
          skuKey: 'adhesive_cavgrip_3v_40lb',
          attributes: {'voc': projectInfo.vocRegion, 'application': 'parapet'},
          orderQty: cavOrder,
          unit: 'cylinders',
          notes: '#40 cylinder, ~${cavGripCoverage.toInt()} sf/cyl — parapet walls',
          trace: BomTrace(
            baseDescription: '${_sf(parapetTpoArea)} ÷ ${cavGripCoverage.toInt()} sf/cylinder',
            baseQty: cavBase,
            wastePercent: wAcc,
            withWaste: cavWithW,
            packageSize: 1,
            orderQty: cavOrder,
            breakdown: [
              'Parapet TPO area: ${_sf(parapetTpoArea)}',
              '  Wall: ${parapetHeightFt.toStringAsFixed(1)}\' + 4" base lap = ${parapetStripWidthFt.toStringAsFixed(2)}\' x ${_lf(parapet.parapetTotalLF)}',
              'Coverage rate: ${cavGripCoverage.toInt()} sf per #40 cylinder (double-sided spray)',
              'Base: ${cavBase.toStringAsFixed(2)} cylinders',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${cavOrder.toInt()} cylinders',
            ],
          ),
        ));

        // UN-TACK Adhesive Remover & Cleaner — 1 aerosol per CAV-Grip cylinder
        items.add(BomLineItem(
          category: 'Adhesives & Sealants',
          name: 'Versico UN-TACK Adhesive Remover & Cleaner — #8 Aerosol',
          skuKey: 'cleaner_untack_8oz_aerosol',
          attributes: {'application': 'parapet'},
          orderQty: cavOrder,
          unit: 'aerosols',
          notes: '#8 aerosol — one per CAV-GRIP 3V cylinder',
          trace: BomTrace(
            baseDescription: '1:1 ratio with CAV-Grip 3v cylinders',
            baseQty: cavBase,
            wastePercent: wAcc,
            withWaste: cavWithW,
            packageSize: 1,
            orderQty: cavOrder,
            breakdown: [
              'One UN-TACK per CAV-GRIP 3V cylinder',
              'ORDER QTY: ${cavOrder.toInt()} aerosols',
            ],
          ),
        ));
      } else {
        // VersiWeld TPO Bonding Adhesive (default) — 5-gal pail, ~60 sf/gal applied
        // to both surfaces (~30 sf/gal each). Parapet wall flashing is always adhered.
        const coveragePerGal = 60.0;
        const packageGal = 5.0;
        final base    = parapetTpoArea / coveragePerGal;
        final withW   = base * (1 + wAcc);
        final pails   = (withW / packageGal).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Adhesives & Sealants',
          name: 'VersiWeld TPO Bonding Adhesive$vocSuffix — 5 Gal Pail (Parapet)',
          skuKey: 'adhesive_versiweld_bonding',
          attributes: {'voc': projectInfo.vocRegion, 'packageGal': 5, 'application': 'parapet'},
          orderQty: pails,
          unit: 'pails',
          notes: '5-gal pail, ~60 sf/gal — parapet wall flashing',
          trace: BomTrace(
            baseDescription: '${_sf(parapetTpoArea)} ÷ 60 sf/gal',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: packageGal,
            orderQty: pails,
            breakdown: [
              'Parapet TPO area: ${_sf(parapetTpoArea)}',
              '  Wall: ${parapetHeightFt.toStringAsFixed(1)}\' + 4" base lap = ${parapetStripWidthFt.toStringAsFixed(2)}\' x ${_lf(parapet.parapetTotalLF)}',
              'Coverage rate: 60 sf/gal',
              'Base gallons:  ${base.toStringAsFixed(1)}',
              'Waste:         ${_pct(wAcc)}%',
              'With waste:    ${withW.toStringAsFixed(1)} gal',
              'ORDER QTY:     ${pails.toInt()} pails (5-gal each)',
            ],
          ),
        ));
      }
    }

    // Seam length — ONE estimate shared by cut-edge sealant, seam tape and
    // membrane cleaner (eval F16):
    //   field sheets:     (fieldRolls − 1) shared seams × 100'
    //   perimeter sheets: one lap seam per sheet run = zone area ÷ sheet width
    // Perimeter/corner half-sheets used to be left out, halving seam LF on
    // jobs with wide perimeter zones.
    final fieldRollsForSeam = (fieldRollArea / fieldRollCoverage).ceil();
    final fieldOnlySeamLF = _fieldSeamLF(fieldRollArea, fieldRollCoverage);
    final perimSheetArea = hasPerimRoll ? effectivePerimArea + effectiveCornerArea : 0.0;
    final perimSheetWidthFt = _rollWidthFt(membrane.perimeterRollWidth);
    final perimSeamLF = perimSheetArea > 0 ? perimSheetArea / perimSheetWidthFt : 0.0;
    final fieldSeamLF = fieldOnlySeamLF + perimSeamLF;
    final seamBreakdown = <String>[
      'Field seams: max(0, $fieldRollsForSeam − 1) × 100\' = ${fieldOnlySeamLF.toStringAsFixed(0)} LF',
      if (perimSeamLF > 0)
        'Perimeter sheet seams: ${_sf(perimSheetArea)} ÷ ${perimSheetWidthFt.toStringAsFixed(0)}\' = ${perimSeamLF.toStringAsFixed(0)} LF',
      if (perimSeamLF > 0) 'Total seams: ${fieldSeamLF.toStringAsFixed(0)} LF',
    ];

    // Cut-edge sealant — applied to membrane reinforcement at cut edges along field seams.
    // Plus a small detail allowance for penetration cuts.
    if (totalArea > 0) {
      final detailCutLF = drainCount * 4.0; // ~4 LF per drain (boot perimeter)
      final seamLF = fieldSeamLF + detailCutLF;
      // 1 bottle (16 oz) covers ~250 LF of cut edge (Versico spec: 225–275 LF/bottle)
      const lfPerBottle  = 250.0;
      final base         = seamLF / lfPerBottle;
      final withW        = base * (1 + wAcc);
      final orderQty     = withW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Adhesives & Sealants',
        name: 'Versico TPO Cut Edge Sealant$vocSuffix',
        skuKey: 'sealant_cut_edge',
        attributes: {'voc': projectInfo.vocRegion},
        orderQty: orderQty,
        unit: 'bottles',
        notes: '16 oz bottles, ~250 LF/bottle — 1/8" bead on cut edges',
        trace: BomTrace(
          baseDescription: '${seamLF.toStringAsFixed(0)} LF cut edge ÷ 250 LF/bottle',
          baseQty: base,
          wastePercent: wAcc,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            ...seamBreakdown,
            'Detail cuts: $drainCount drains × 4 LF = ${detailCutLF.toStringAsFixed(0)} LF',
            'Total cut edge LF: ${seamLF.toStringAsFixed(0)}',
            'Coverage: 250 LF/bottle',
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${orderQty.toInt()} bottles',
          ],
        ),
      ));
    }

    // Versico Water Cut-Off Mastic — moisture barrier at compression details.
    // Per Versico spec, used at: drains (gasket under drain ring), pipe flashing
    // tops (against the pipe), and beneath conventional metal edging at compression
    // terminations. NOT used along field seams (those are welded or taped) and
    // NOT at T-joints (T-joints get lap sealant under the T-joint cover).
    if (totalArea > 0) {
      final pipeCount = penetrations.smallPipeCount + penetrations.largePipeCount;
      // ~1 LF per drain, ~1 LF per pipe flashing top, ~5% of edge metal LF for
      // compression terminations under conventional metal edging.
      final masticLF = drainCount * 1.0
          + pipeCount * 1.0
          + metalScope.edgeMetalLF * 0.05;
      if (masticLF > 0) {
        const lfPerTube = 10.0;
        final base     = masticLF / lfPerTube;
        final withW    = base * (1 + wAcc);
        final orderQty = withW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Adhesives & Sealants',
          name: 'Versico Water Cut-Off Mastic',
          skuKey: 'mastic_water_cutoff',
          attributes: const {},
          orderQty: orderQty,
          unit: 'tubes',
          notes: '11 oz tubes, ~10 LF/tube — drains, pipe tops, under metal edging',
          trace: BomTrace(
            baseDescription: '${masticLF.toStringAsFixed(0)} LF detail seal ÷ 10 LF/tube',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: 1,
            orderQty: orderQty,
            breakdown: [
              'Drains: $drainCount × 1.0 LF',
              'Pipe flashing tops: $pipeCount × 1.0 LF',
              'Under metal edging (5% × ${metalScope.edgeMetalLF.toStringAsFixed(0)} LF): ${(metalScope.edgeMetalLF * 0.05).toStringAsFixed(1)} LF',
              'Total detail LF: ${masticLF.toStringAsFixed(1)}',
              'Coverage: 10 LF/tube',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${orderQty.toInt()} tubes',
            ],
          ),
        ));
      }
    }

    // ── Seam tape (when seamType == 'Tape' instead of hot-air welded) ───────
    // Versico seam tape: 3" wide pressure-sensitive, 100' rolls.
    // Corrected seam LF: (fieldRolls − 1) shared seams × 100' roll length.
    if (membrane.seamType == 'Tape' && totalArea > 0) {
      final seamLFTape = fieldSeamLF;
      const tapeRollLF = 100.0;
      final tapeBase = seamLFTape / tapeRollLF;
      final tapeWithW = tapeBase * (1 + wAcc);
      final tapeOrder = tapeWithW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Adhesives & Sealants',
        name: 'Versico TPO Seam Tape (3" wide)',
        skuKey: 'tape_tpo_seam_3in',
        attributes: const {},
        orderQty: tapeOrder,
        unit: 'rolls',
        notes: "3\"×100' rolls — pressure-sensitive seam tape (requires TPO primer)",
        trace: BomTrace(
          baseDescription: '${seamLFTape.toStringAsFixed(0)} LF seams ÷ 100\'/roll',
          baseQty: tapeBase,
          wastePercent: wAcc,
          withWaste: tapeWithW,
          packageSize: 1,
          orderQty: tapeOrder,
          breakdown: [
            ...seamBreakdown,
            'Roll length: 100\' per roll',
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${tapeOrder.toInt()} rolls',
          ],
        ),
      ));
    }

    // ── Substrate prep for tear-off projects ─────────────────────────────────
    // BUR and Modified Bitumen tear-offs leave bituminous residue on the deck.
    // Deck primer is ONLY needed when insulation is ADHERED directly to deck.
    // If insulation is mechanically attached, fasteners penetrate through residue — no primer needed.
    final deckNeedsPrimer = systemSpecs.projectType == 'Tear-off & Replace' &&
        (systemSpecs.existingRoofType == 'BUR' || systemSpecs.existingRoofType == 'Modified Bitumen') &&
        insulation.layer1.attachmentMethod == 'Adhered';
    if (deckNeedsPrimer && totalArea > 0) {
      // Substrate primer: ~200 sf/gallon, 5-gallon pails
      const subPrimerCoverage = 200.0;
      const subPailGal = 5.0;
      final subBase = totalArea / subPrimerCoverage;
      final subWithW = subBase * (1 + wAcc);
      final subOrder = (subWithW / subPailGal).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Adhesives & Sealants',
        name: 'Deck Primer (Post Tear-Off Prep)',
        skuKey: 'primer_deck_substrate',
        attributes: const {},
        orderQty: subOrder,
        unit: 'pails',
        notes: '5-gal pails, ~200 sf/gal — preps deck after ${systemSpecs.existingRoofType} removal for new TPO system adhesion',
        trace: BomTrace(
          baseDescription: '${_sf(totalArea)} ÷ 200 sf/gal',
          baseQty: subBase,
          wastePercent: wAcc,
          withWaste: subWithW,
          packageSize: subPailGal,
          orderQty: subOrder,
          breakdown: [
            'Project type: ${systemSpecs.projectType}',
            'Existing roof: ${systemSpecs.existingRoofType}',
            'Deck area: ${_sf(totalArea)}',
            'Coverage: 200 sf/gal',
            'Base gallons: ${subBase.toStringAsFixed(1)}',
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${subOrder.toInt()} pails (5 gal)',
          ],
        ),
      ));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5. PARAPET & TERMINATION
    // ══════════════════════════════════════════════════════════════════════════

    if (parapet.hasParapetWalls) {
      // Termination bar — 10' pieces
      if (termBarLF > 0) {
        const pieceLen = 10.0;
        final base     = termBarLF / pieceLen;
        final withW    = base * (1 + wMet);
        final orderQty = withW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Parapet & Termination',
          name: parapet.terminationType,
          orderQty: orderQty,
          unit: 'pieces',
          notes: "10' pieces",
          skuKey: parapet.terminationType == 'TPO Coated Drip Edge'
              ? 'term_tpo_coated_drip_edge_10ft'
              : 'term_bar_aluminum_10ft',
          attributes: const {},
          trace: BomTrace(
            baseDescription: '${_lf(termBarLF)} ÷ 10\' pieces',
            baseQty: base,
            wastePercent: wMet,
            withWaste: withW,
            packageSize: 1,
            orderQty: orderQty,
            breakdown: [
              'Total LF: ${_lf(termBarLF)}',
              'Piece length: 10\'',
              'Base: ${base.toStringAsFixed(1)} pieces',
              'Waste: ${_pct(wMet)}%',
              'ORDER QTY: ${orderQty.toInt()} pieces',
            ],
          ),
        ));
      }

      // Water cut-off mastic — gasket under termination bar, ~10 LF/tube (Versico spec: 10 LF/tube, 7/16" bead)
      if (termBarLF > 0) {
        const lfPerTube = 10.0;
        final base     = termBarLF / lfPerTube;
        final withW    = base * (1 + wAcc);
        final orderQty = withW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Parapet & Termination',
          name: 'Low-VOC Water Cut-Off Mastic',
          skuKey: 'mastic_water_cutoff_lowvoc',
          attributes: const {},
          orderQty: orderQty,
          unit: 'tubes',
          notes: '~10 LF/tube — 7/16" bead under termination bar',
          trace: BomTrace(
            baseDescription: '${_lf(termBarLF)} ÷ 10 LF/tube',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: 1,
            orderQty: orderQty,
            breakdown: [
              'Termination bar LF: ${_lf(termBarLF)}',
              'Coverage: ~10 LF/tube (7/16" bead)',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${orderQty.toInt()} tubes',
            ],
          ),
        ));
      }

      // Single-ply sealant — top edge of termination bar, ~25 LF/tube (Versico spec: 25 LF/tube, 1/4" bead)
      if (termBarLF > 0) {
        const lfPerTube = 25.0;
        final base     = termBarLF / lfPerTube;
        final withW    = base * (1 + wAcc);
        final orderQty = withW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Parapet & Termination',
          name: 'Universal Single-Ply Sealant',
          skuKey: 'sealant_universal_singleply',
          attributes: const {},
          orderQty: orderQty,
          unit: 'tubes',
          notes: '~25 LF/tube — 1/4" bead along top edge',
          trace: BomTrace(
            baseDescription: '${_lf(termBarLF)} ÷ 25 LF/tube',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: 1,
            orderQty: orderQty,
            breakdown: [
              'Termination bar LF: ${_lf(termBarLF)}',
              'Coverage: ~25 LF/tube (1/4" bead)',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${orderQty.toInt()} tubes',
            ],
          ),
        ));
      }

      // ── Termination bar fasteners — type driven by wall type ──────────────
      if (termBarLF > 0) {
        const spacingIn = 8.0; // 8" o.c. per Versico spec for all wall types

        // Determine fastener type, length, and unit name from wall type
        final String tbFastener;
        final String tbLength;
        final String tbNotes;
        switch (parapet.wallType) {
          case 'Wood':
            tbFastener = 'Wood Screws';
            tbLength   = '1-5/8"';  // standard wood nailer screw
            tbNotes    = '8" o.c. into wood nailer';
            break;
          case 'Metal Stud':
            tbFastener = 'TEK Screws (Self-Drilling)';
            tbLength   = '1"';
            tbNotes    = '8" o.c. into metal stud/framing';
            break;
          default: // Concrete Block, Poured Concrete
            tbFastener = 'Masonry Anchors';
            tbLength   = '1-1/4"';
            tbNotes    = '8" o.c. into masonry/concrete per Versico spec';
        }

        final base     = termBarLF * 12.0 / spacingIn;
        final withW    = base * (1 + wAcc);
        const tbBucketSize = 500.0;
        final orderQty = (withW / tbBucketSize).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Parapet & Termination',
          name: '$tbFastener $tbLength — Termination Bar (${parapet.wallType})',
          skuKey: parapet.wallType == 'Wood'
              ? 'fastener_termbar_wood'
              : (parapet.wallType == 'Metal Stud'
                  ? 'fastener_termbar_tek'
                  : 'fastener_termbar_masonry'),
          attributes: {'wallType': parapet.wallType, 'length': tbLength},
          orderQty: orderQty,
          unit: 'buckets',
          notes: '${tbBucketSize.toInt()}/bucket — $tbNotes',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} fasteners ÷ ${tbBucketSize.toInt()}/bucket',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: tbBucketSize,
            orderQty: orderQty,
            breakdown: [
              'Wall type:  ${parapet.wallType} → $tbFastener $tbLength',
              'Spacing:    ${spacingIn.toInt()}" o.c.',
              '${_lf(termBarLF)} × 12"/ft ÷ ${spacingIn.toInt()}" = ${base.toStringAsFixed(0)} fasteners',
              'Waste: ${_pct(wAcc)}%',
              'With waste: ${withW.toStringAsFixed(0)} fasteners',
              'Bucket size: ${tbBucketSize.toInt()}/bucket',
              'ORDER QTY: ${orderQty.toInt()} buckets',
            ],
          ),
        ));
      }
    }

    // ── Edge metal fasteners (eave / rake termination into deck) ─────────────
    // Edge metal (gravel stop, drip edge, ES-1) is fastened to the deck nailer
    // or directly into the deck at the roof edge — no insulation in the flange.
    // Spacing: 4" o.c. (roof-edge flanges are fastened 3–4" o.c.; 12" was
    // far too sparse). Roof edges only — wall flashing/counterflashing is
    // fastened into the wall, not the roof-edge nailer.
    final edgeMetalLF = metalScope.dripEdgeLF + metalScope.otherEdgeMetalLF;
    if (edgeMetalLF > 0 && hasDeckType) {
      const edgeSpacingIn = 4.0;
      // Edge metal fastener goes through metal flange only (~0" insulation at edge)
      final edgeFastLen   = _selectFastenerLen(systemSpecs.deckType, 0);
      final edgeFastName  = _fastenerName(systemSpecs.deckType);
      final base          = edgeMetalLF * 12.0 / edgeSpacingIn;
      final withW         = base * (1 + wAcc);
      final edgeBucketSize = _fastenerPack(systemSpecs.deckType, 0).toDouble();
      final orderQty      = (withW / edgeBucketSize).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Parapet & Termination',
        name: '$edgeFastName $edgeFastLen — Edge Metal (${metalScope.edgeMetalType})',
        skuKey: 'fastener_edge_metal',
        attributes: {
          'fastenerName': edgeFastName,
          'length':       edgeFastLen,
          'deckType':     systemSpecs.deckType,
        },
        orderQty: orderQty,
        unit: 'cartons',
        notes: '${edgeBucketSize.toInt()}/carton — ${edgeSpacingIn.toInt()}" o.c. eave/rake edge attachment',
        trace: BomTrace(
          baseDescription: '${base.toStringAsFixed(0)} fasteners ÷ ${edgeBucketSize.toInt()}/carton',
          baseQty: base,
          wastePercent: wAcc,
          withWaste: withW,
          packageSize: edgeBucketSize,
          orderQty: orderQty,
          breakdown: [
            'Deck type:  ${systemSpecs.deckType} → $edgeFastName $edgeFastLen',
            'Location:   eave/rake (no insulation in flange)',
            'Roof-edge LF: drip edge ${_lf(metalScope.dripEdgeLF)} + other ${_lf(metalScope.otherEdgeMetalLF)}',
            'Spacing:    ${edgeSpacingIn.toInt()}" o.c.',
            '${_lf(edgeMetalLF)} × 12"/ft ÷ ${edgeSpacingIn.toInt()}" = ${base.toStringAsFixed(0)} fasteners',
            'Waste: ${_pct(wAcc)}%',
            'Bucket size: ${edgeBucketSize.toInt()}/carton',
            'ORDER QTY: ${orderQty.toInt()} cartons',
          ],
        ),
      ));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 6. DETAILS & ACCESSORIES
    // ══════════════════════════════════════════════════════════════════════════

    // Inside corners
    final insideCorners = geometry.insideCorners;
    if (insideCorners > 0) {
      items.add(_eachItem('Details & Accessories', 'TPO Inside Corners (Prefab)',
          insideCorners.toDouble(), 'each', '',
          skuKey: 'accessory_corner_inside_prefab'));
    }

    // Outside corners — from geometry OR default 4
    final outsideCorners = geometry.outsideCorners > 0 ? geometry.outsideCorners : 4;
    if (outsideCorners > 0) {
      items.add(_eachItem('Details & Accessories', 'TPO Outside Corners (Prefab)',
          outsideCorners.toDouble(), 'each', '',
          skuKey: 'accessory_corner_outside_prefab'));
    }

    // T-joint covers — estimated: 1 per roll minus perimeter
    if (totalArea > 0) {
      final fieldRolls = (effectiveFieldArea / membrane.rollCoverage).ceil();
      final tJoints    = (fieldRolls * 0.75).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Details & Accessories',
        name: 'T-Joint Covers',
        skuKey: 'accessory_tjoint_covers',
        attributes: const {},
        orderQty: tJoints,
        unit: 'each',
        notes: 'Estimated ~0.75 per field roll',
        trace: BomTrace(
          baseDescription: '$fieldRolls field rolls × 0.75',
          baseQty: tJoints,
          wastePercent: 0,
          withWaste: tJoints,
          packageSize: 1,
          orderQty: tJoints,
          breakdown: [
            'Field rolls: $fieldRolls',
            'Est. T-joints: ${fieldRolls} × 0.75 = $tJoints',
            'ORDER QTY: ${tJoints.toInt()} each',
          ],
        ),
      ));
    }

    // Drains
    if (drainCount > 0) {
      items.add(_eachItem('Details & Accessories', 'Roof Drain Assembly (${penetrations.drainType})',
          drainCount.toDouble(), 'each', penetrations.drainType,
          skuKey: 'accessory_drain_assembly',
          attributes: {'drainType': penetrations.drainType}));
    }

    // Pipe boots — small
    if (penetrations.smallPipeCount > 0) {
      items.add(_eachItem('Details & Accessories', 'Pipe Boot — Small (1–4")',
          penetrations.smallPipeCount.toDouble(), 'each', '',
          skuKey: 'accessory_pipeboot_small'));
    }

    // Pipe boots — large
    if (penetrations.largePipeCount > 0) {
      items.add(_eachItem('Details & Accessories', 'Pipe Boot — Large (4–12")',
          penetrations.largePipeCount.toDouble(), 'each', '',
          skuKey: 'accessory_pipeboot_large'));
    }

    // Skylights
    if (penetrations.skylightCount > 0) {
      items.add(_eachItem('Details & Accessories', 'Skylight Flashing Kit',
          penetrations.skylightCount.toDouble(), 'each', '',
          skuKey: 'accessory_skylight_kit'));
    }

    // Scuppers
    if (penetrations.scupperCount > 0) {
      items.add(_eachItem('Details & Accessories', 'Scupper Assembly',
          penetrations.scupperCount.toDouble(), 'each', '',
          skuKey: 'accessory_scupper'));
    }

    // Expansion joint covers
    if (penetrations.expansionJointLF > 0) {
      const pieceLen = 10.0;
      final base     = penetrations.expansionJointLF / pieceLen;
      final withW    = base * (1 + wMet);
      final orderQty = withW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Details & Accessories',
        name: 'Expansion Joint Cover',
        skuKey: 'accessory_expansion_joint_cover',
        attributes: const {},
        orderQty: orderQty,
        unit: 'pieces',
        notes: "10' pieces",
        trace: BomTrace(
          baseDescription: '${_lf(penetrations.expansionJointLF)} ÷ 10\'',
          baseQty: base,
          wastePercent: wMet,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            '${_lf(penetrations.expansionJointLF)} ÷ 10\' = ${base.toStringAsFixed(1)} pieces',
            'Waste: ${_pct(wMet)}%',
            'ORDER QTY: ${orderQty.toInt()} pieces',
          ],
        ),
      ));
    }

    // Pitch pans
    if (penetrations.pitchPanCount > 0) {
      items.add(_eachItem('Details & Accessories', 'TPO Molded Sealant Pocket',
          penetrations.pitchPanCount.toDouble(), 'each', '',
          skuKey: 'accessory_pitch_pan'));
    }

    // RTU flashing (perimeter rolls)
    // Use actual curb dimensions from rtuDetails if available, else default 12" curb height.
    if (penetrations.rtuTotalLF > 0) {
      // Strip width = curb height + 12" field overlap + 6" top overlap
      // Versico spec: min 12" up curb wall + lap onto field membrane
      double avgCurbHeightIn = 12.0; // default
      if (penetrations.rtuDetails.isNotEmpty) {
        final totalHeight = penetrations.rtuDetails.fold(0.0, (sum, r) => sum + r.height);
        avgCurbHeightIn = totalHeight / penetrations.rtuDetails.length;
        if (avgCurbHeightIn < 8.0) avgCurbHeightIn = 12.0; // sanity floor
      }
      final stripWidthFt = (avgCurbHeightIn + 18.0) / 12.0; // curb + 12" field lap + 6" top
      final rtuFlashSF = penetrations.rtuTotalLF * stripWidthFt;
      final base       = rtuFlashSF / flashRollCoverage;
      final withW      = base * (1 + wMat);
      final orderQty   = withW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Details & Accessories',
        name: 'TPO Curb Flashing — RTU (6\'×100\')',
        skuKey: 'tpo_rtu_curb_flashing',
        attributes: {
          'membraneType': membrane.membraneType,
          'thickness':    membrane.thickness,
          'color':        membrane.color,
        },
        orderQty: orderQty,
        unit: 'rolls',
        notes: "RTU curbs — ${_lf(penetrations.rtuTotalLF)} perimeter, ${avgCurbHeightIn.toStringAsFixed(0)}\" curb height",
        trace: BomTrace(
          baseDescription: '${_lf(penetrations.rtuTotalLF)} × ${stripWidthFt.toStringAsFixed(1)}\' strip ÷ 600 sf/roll',
          baseQty: base,
          wastePercent: wMat,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            'RTU curb LF: ${_lf(penetrations.rtuTotalLF)}',
            'Avg curb height: ${avgCurbHeightIn.toStringAsFixed(0)}"${penetrations.rtuDetails.isNotEmpty ? " (from ${penetrations.rtuDetails.length} RTU details)" : " (default)"}',
            'Strip width: ${avgCurbHeightIn.toStringAsFixed(0)}" curb + 12" field + 6" top = ${(avgCurbHeightIn + 18).toStringAsFixed(0)}" (${stripWidthFt.toStringAsFixed(1)}\')',
            'Flash SF: ${rtuFlashSF.toStringAsFixed(0)}',
            'Roll: 600 sf/roll',
            'ORDER QTY: ${orderQty.toInt()} rolls',
          ],
        ),
      ));

      // RTU curb wrap corners — 4 corners per RTU per Versico spec
      final rtuCornerCount = penetrations.rtuDetails.length * 4;
      if (rtuCornerCount > 0) {
        final cwBase = rtuCornerCount.toDouble();
        final cwWithW = cwBase * (1 + wAcc);
        final cwOrder = cwWithW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Details & Accessories',
          name: 'TPO Curb Wrap Corners — RTU',
          skuKey: 'accessory_rtu_corner_wrap',
          attributes: const {},
          orderQty: cwOrder,
          unit: 'each',
          notes: '4 corners per RTU — 60-mil reinforced VersiWeld',
          trace: BomTrace(
            baseDescription: '${penetrations.rtuDetails.length} RTUs × 4 corners',
            baseQty: cwBase,
            wastePercent: wAcc,
            withWaste: cwWithW,
            packageSize: 1,
            orderQty: cwOrder,
            breakdown: [
              '${penetrations.rtuDetails.length} RTUs × 4 corners = $rtuCornerCount',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${cwOrder.toInt()} each',
            ],
          ),
        ));
      }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 7. METAL SCOPE
    // ══════════════════════════════════════════════════════════════════════════

    if (metalScope.copingLF > 0) {
      items.add(_linearItem('Metal Scope', 'Coping Cap — ${metalScope.copingWidth}',
          metalScope.copingLF, wMet, "10' sections",
          skuKey: 'metal_coping_cap',
          attributes: {'width': metalScope.copingWidth}));
    }

    if (metalScope.wallFlashingLF > 0) {
      items.add(_linearItem('Metal Scope', 'Wall Flashing',
          metalScope.wallFlashingLF, wMet, "10' sections",
          skuKey: 'metal_wall_flashing'));
    }
    if (metalScope.dripEdgeLF > 0) {
      items.add(_linearItem('Metal Scope', 'Drip Edge — ${metalScope.edgeMetalType}',
          metalScope.dripEdgeLF, wMet, "10' sections",
          skuKey: 'metal_drip_edge',
          attributes: {'edgeMetalType': metalScope.edgeMetalType}));
    }
    if (metalScope.otherEdgeMetalLF > 0) {
      items.add(_linearItem('Metal Scope', 'Other Edge Metal',
          metalScope.otherEdgeMetalLF, wMet, "10' sections",
          skuKey: 'metal_other_edge'));
    }

    if (metalScope.gutterLF > 0) {
      items.add(_linearItem('Metal Scope', 'Gutter — ${metalScope.gutterSize}',
          metalScope.gutterLF, wMet, "10' sections",
          skuKey: 'metal_gutter',
          attributes: {'size': metalScope.gutterSize}));
    }

    if (metalScope.downspoutCount > 0) {
      items.add(_eachItem('Metal Scope', 'Downspout',
          metalScope.downspoutCount.toDouble(), 'each', '',
          skuKey: 'metal_downspout'));
    }

    // TPO Reinforced Overlayment Strip — needed at all metal-to-membrane transitions
    // Per Versico: 6" wide strip welded over non-coated metal flanges
    final totalEdgeMetalLF = metalScope.dripEdgeLF + metalScope.copingLF +
        metalScope.wallFlashingLF + metalScope.otherEdgeMetalLF;
    if (totalEdgeMetalLF > 0) {
      // Overlayment strip: 6" wide, 100' rolls
      const stripRollLF = 100.0;
      final stripBase = totalEdgeMetalLF / stripRollLF;
      final stripWithW = stripBase * (1 + wAcc);
      final stripOrder = stripWithW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Metal Scope',
        name: 'TPO Reinforced Overlayment Strip (6" wide)',
        skuKey: 'tpo_overlayment_strip_6in',
        attributes: const {},
        orderQty: stripOrder,
        unit: 'rolls',
        notes: "6\"x100' — seals metal flanges to membrane per Versico spec",
        trace: BomTrace(
          baseDescription: '${totalEdgeMetalLF.toStringAsFixed(0)} LF edge metal / 100\'/roll',
          baseQty: stripBase,
          wastePercent: wAcc,
          withWaste: stripWithW,
          packageSize: 1,
          orderQty: stripOrder,
          breakdown: [
            'Drip edge: ${_lf(metalScope.dripEdgeLF)}',
            'Coping: ${_lf(metalScope.copingLF)}',
            'Wall flashing: ${_lf(metalScope.wallFlashingLF)}',
            'Other: ${_lf(metalScope.otherEdgeMetalLF)}',
            'Total: ${_lf(totalEdgeMetalLF)}',
            'Roll: 100\' per roll',
            'ORDER QTY: ${stripOrder.toInt()} rolls',
          ],
        ),
      ));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 8. CONSUMABLES
    // ══════════════════════════════════════════════════════════════════════════

    if (totalArea > 0) {
      // Hook blades — 1 pack (100 blades) per ~3,000 sf
      final bladeBase  = totalArea / 3000;
      final bladePacks = bladeBase.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Consumables',
        name: 'Hook Blades',
        skuKey: 'accessory_hook_blades',
        attributes: const {},
        orderQty: bladePacks,
        unit: 'packs',
        notes: '100 blades/pack',
        trace: BomTrace(
          baseDescription: '${_sf(totalArea)} ÷ 3,000 sf/pack',
          baseQty: bladeBase,
          wastePercent: 0,
          withWaste: bladeBase,
          packageSize: 1,
          orderQty: bladePacks,
          breakdown: [
            '${_sf(totalArea)} ÷ 3,000 sf/pack = ${bladePacks.toInt()} packs',
          ],
        ),
      ));

      // Rags / solvent — 1 box per 2,000 sf
      final ragBoxes = (totalArea / 2000).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Consumables',
        name: 'Rags & TPO Cleaner',
        skuKey: 'cleaner_rags_tpo',
        attributes: const {},
        orderQty: ragBoxes,
        unit: 'boxes',
        notes: '~1 box per 2,000 sf',
        trace: BomTrace(
          baseDescription: '${_sf(totalArea)} ÷ 2,000 sf/box',
          baseQty: ragBoxes,
          wastePercent: 0,
          withWaste: ragBoxes,
          packageSize: 1,
          orderQty: ragBoxes,
          breakdown: ['${_sf(totalArea)} ÷ 2,000 sf/box = ${ragBoxes.toInt()} boxes'],
        ),
      ));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 9. VAPOR RETARDER
    // ══════════════════════════════════════════════════════════════════════════
    // Only when systemSpecs.vaporRetarder != 'None' — full roof area coverage.

    if (systemSpecs.vaporRetarder != 'None' && totalArea > 0) {
      // Standard vapor retarder rolls: 10'×100' = 1,000 sf
      const vrRollSf = 1000.0;
      final vrBase     = totalArea / vrRollSf;
      final vrWithW    = vrBase * (1 + wMat);
      final vrOrder    = vrWithW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Vapor Retarder',
        name: 'Vapor Retarder — ${systemSpecs.vaporRetarder}',
        skuKey: 'vapor_retarder',
        attributes: {'type': systemSpecs.vaporRetarder},
        orderQty: vrOrder,
        unit: 'rolls',
        notes: "10'×100' rolls (1,000 sf/roll)",
        trace: BomTrace(
          baseDescription: '${_sf(totalArea)} ÷ 1,000 sf/roll',
          baseQty: vrBase,
          wastePercent: wMat,
          withWaste: vrWithW,
          packageSize: 1,
          orderQty: vrOrder,
          breakdown: [
            'Roof area: ${_sf(totalArea)}',
            'Roll coverage: 1,000 sf/roll (10\'×100\')',
            'Waste: ${_pct(wMat)}%',
            'ORDER QTY: ${vrOrder.toInt()} rolls',
          ],
        ),
      ));

      // Self-Adhered vapor retarder needs primer
      if (systemSpecs.vaporRetarder == 'Self-Adhered') {
        const vrPrimerCoverage = 250.0; // sf per gallon
        const vrPrimerGalPerPail = 5.0;
        final vrPBase   = totalArea / vrPrimerCoverage;
        final vrPWithW  = vrPBase * (1 + wAcc);
        final vrPOrder  = (vrPWithW / vrPrimerGalPerPail).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Vapor Retarder',
          name: 'Vapor Retarder Primer',
          skuKey: 'primer_vapor_retarder',
          attributes: const {},
          orderQty: vrPOrder,
          unit: 'pails',
          notes: '5-gal pails, ~250 sf/gal',
          trace: BomTrace(
            baseDescription: '${_sf(totalArea)} ÷ 250 sf/gal',
            baseQty: vrPBase,
            wastePercent: wAcc,
            withWaste: vrPWithW,
            packageSize: vrPrimerGalPerPail,
            orderQty: vrPOrder,
            breakdown: [
              'Roof area: ${_sf(totalArea)}',
              'Coverage: 250 sf/gal',
              'Base gallons: ${vrPBase.toStringAsFixed(1)}',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${vrPOrder.toInt()} pails (5 gal)',
            ],
          ),
        ));
      }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 10. TPO PRIMER
    // ══════════════════════════════════════════════════════════════════════════
    // Required before ALL pressure-sensitive products per Versico spec:
    //   corners, T-joints, seam tape, RUSS strips, peel & stick products.
    // Coverage: ~400 sf per gallon (single coat).
    // Estimate primed area from: corners, T-joints, seam tape laps, parapet RUSS.

    if (totalArea > 0) {
      // Primed area estimate:
      //   - Inside/outside corners: ~2 sf each (6"×6" area × 2 sides)
      //   - T-joint covers: ~0.25 sf each (4.5" diameter disc)
      //   - Seam tape laps at roll ends: ~0.5 sf per roll
      //   - Parapet RUSS base strip: parapetLF × 0.5' wide = parapetLF × 0.5 sf
      final cornerCount = (geometry.insideCorners + geometry.outsideCorners).toDouble();
      final fieldRolls = (totalArea / membrane.rollCoverage).ceil();
      final tJointCount = (fieldRolls * 0.75).ceil();
      final primedArea = (cornerCount * 2.0) +
          (tJointCount * 0.25) +
          (fieldRolls * 0.5) +
          (parapet.hasParapetWalls ? parapet.parapetTotalLF * 0.5 : 0.0);

      if (primedArea > 0) {
        final String primerName;
        final double primerCov;
        final String primerUnit;
        final double primerPkgSize;
        final String primerSkuKey;
        switch (membrane.primerType) {
          case 'TPO Primer (225 sf/gal)':
            primerName = 'Versico TPO Primer$vocSuffix';
            primerCov = 225.0;
            primerUnit = 'gallons';
            primerPkgSize = 1.0;
            primerSkuKey = 'primer_tpo_225';
            break;
          case 'CAV-PRIME Spray (1,760 sf/cyl)':
            primerName = 'Versico CAV-PRIME Low-VOC Primer$vocSuffix — #32 Cylinder';
            primerCov = 1760.0;
            primerUnit = 'cylinders';
            primerPkgSize = 1.0;
            primerSkuKey = 'primer_cavprime_cylinder';
            break;
          default: // Low-VOC EPDM/TPO Primer
            primerName = 'Versico Low-VOC EPDM & TPO Primer$vocSuffix';
            primerCov = 700.0;
            primerUnit = 'gallons';
            primerPkgSize = 1.0;
            primerSkuKey = 'primer_lowvoc_epdm_tpo_700';
        }
        final primerBase   = primedArea / primerCov;
        final primerWithW  = primerBase * (1 + wAcc);
        // Minimum 1 unit
        final primerOrder  = max(1.0, (primerWithW / primerPkgSize).ceil().toDouble());
        items.add(BomLineItem(
          category: 'Adhesives & Sealants',
          name: primerName,
          skuKey: primerSkuKey,
          attributes: {'voc': projectInfo.vocRegion},
          orderQty: primerOrder,
          unit: primerUnit,
          notes: '~${primerCov.toInt()} sf/${primerUnit == 'cylinders' ? 'cyl' : 'gal'} — required before all pressure-sensitive products',
          trace: BomTrace(
            baseDescription: '${primedArea.toStringAsFixed(0)} sf primed area ÷ ${primerCov.toInt()} sf/${primerUnit == 'cylinders' ? 'cyl' : 'gal'}',
            baseQty: primerBase,
            wastePercent: wAcc,
            withWaste: primerWithW,
            packageSize: primerPkgSize,
            orderQty: primerOrder,
            breakdown: [
              'Primed areas:',
              '  Corners (${cornerCount.toInt()}): ${(cornerCount * 2.0).toStringAsFixed(0)} sf',
              '  T-joints ($tJointCount): ${(tJointCount * 0.25).toStringAsFixed(1)} sf',
              '  Seam tape laps ($fieldRolls rolls): ${(fieldRolls * 0.5).toStringAsFixed(1)} sf',
              if (parapet.hasParapetWalls)
                '  Parapet RUSS base (${_lf(parapet.parapetTotalLF)}): ${(parapet.parapetTotalLF * 0.5).toStringAsFixed(0)} sf',
              'Total primed area: ${primedArea.toStringAsFixed(0)} sf',
              'Coverage: ${primerCov.toInt()} sf/${primerUnit == 'cylinders' ? 'cyl' : 'gal'}',
              'ORDER QTY: ${primerOrder.toInt()} $primerUnit',
            ],
          ),
        ));
      }
    }

    // Membrane Cleaner — required accessory per Versico spec
    if (totalArea > 0) {
      const cleanerCoverage = 400.0; // sf per gallon
      final seamLFClean = fieldSeamLF;
      // Cleaner needed for all seam areas before welding
      final cleanArea = seamLFClean * 0.5; // ~6" strip on each side of seam
      final cleanBase = cleanArea / cleanerCoverage;
      final cleanWithW = cleanBase * (1 + wAcc);
      final cleanOrder = max(1.0, cleanWithW.ceil().toDouble());
      items.add(BomLineItem(
        category: 'Adhesives & Sealants',
        name: 'Versico Weathered Membrane Cleaner',
        skuKey: 'cleaner_weathered_membrane',
        attributes: {'voc': projectInfo.vocRegion},
        orderQty: cleanOrder,
        unit: 'gallons',
        notes: '~400 sf/gal — clean membrane before welding',
        trace: BomTrace(
          baseDescription: '${cleanArea.toStringAsFixed(0)} sf seam area ÷ 400 sf/gal',
          baseQty: cleanBase,
          wastePercent: wAcc,
          withWaste: cleanWithW,
          packageSize: 1,
          orderQty: cleanOrder,
          breakdown: [
            ...seamBreakdown,
            'Clean area (~6" each side): ${cleanArea.toStringAsFixed(0)} sf',
            'Coverage: 400 sf/gal',
            'ORDER QTY: ${cleanOrder.toInt()} gallons (min 1)',
          ],
        ),
      ));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 11. LAP SEALANT
    // ══════════════════════════════════════════════════════════════════════════
    // Separate from cut-edge sealant — needed at T-joint edges, tape overlaps,
    // flashing edges, and penetration details per Versico spec.
    // ~50 LF/tube (10 oz cartridge).

    if (totalArea > 0) {
      final fieldRollsForLap = (totalArea / membrane.rollCoverage).ceil();
      final tJointsForLap = (fieldRollsForLap * 0.75).ceil();
      final cornerCountForLap = geometry.insideCorners + geometry.outsideCorners;
      // Each T-joint: ~12" perimeter, each corner: ~12" perimeter, each penetration: ~12" avg
      final penetrationCount = penetrations.smallPipeCount +
          penetrations.largePipeCount +
          penetrations.skylightCount +
          penetrations.scupperCount +
          penetrations.pitchPanCount;
      final lapLF = (tJointsForLap + cornerCountForLap + penetrationCount) * 1.0; // ~1 LF each
      if (lapLF > 0) {
        const lfPerTube = 22.0;
        final lapBase = lapLF / lfPerTube;
        final lapWithW = lapBase * (1 + wAcc);
        final lapOrder = max(1.0, lapWithW.ceil().toDouble());
        items.add(BomLineItem(
          category: 'Adhesives & Sealants',
          name: 'Versico Lap Sealant',
          skuKey: 'sealant_lap',
          attributes: {'voc': projectInfo.vocRegion},
          orderQty: lapOrder,
          unit: 'tubes',
          notes: '11 oz tubes, ~22 LF/tube — 5/16" bead',
          trace: BomTrace(
            baseDescription: '${lapLF.toStringAsFixed(0)} LF ÷ 22 LF/tube',
            baseQty: lapBase,
            wastePercent: wAcc,
            withWaste: lapWithW,
            packageSize: 1,
            orderQty: lapOrder,
            breakdown: [
              'T-joints: $tJointsForLap × 1 LF',
              'Corners: $cornerCountForLap × 1 LF',
              'Penetrations: $penetrationCount × 1 LF',
              'Total: ${lapLF.toStringAsFixed(0)} LF',
              'ORDER QTY: ${lapOrder.toInt()} tubes',
            ],
          ),
        ));
      }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 12. RUSS STRIPS (MA PARAPET BASE TRANSITION)
    // ══════════════════════════════════════════════════════════════════════════
    // For MA systems: 6" wide VersiWeld Pressure-Sensitive Reinforced Universal
    // Securement Strip at wall/deck transition. Vertical leg extends 1"–6" up wall.
    // Fasteners at 12" O.C. max through RUSS into deck.
    // Per Versico spec: required at all wall-to-deck transitions for MA membrane.

    if (isMA && parapet.hasParapetWalls && parapet.parapetTotalLF > 0) {
      // RUSS comes in 100' rolls, 6" wide
      const russRollLF = 100.0;
      final russBase    = parapet.parapetTotalLF / russRollLF;
      final russWithW   = russBase * (1 + wAcc);
      final russOrder   = russWithW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Parapet & Termination',
        name: 'VersiWeld RUSS Strip (6" wide) — Parapet Base',
        skuKey: 'russ_strip_6in',
        attributes: const {},
        orderQty: russOrder,
        unit: 'rolls',
        notes: "100' rolls — MA wall/deck transition per Versico spec",
        trace: BomTrace(
          baseDescription: '${_lf(parapet.parapetTotalLF)} ÷ 100\'/roll',
          baseQty: russBase,
          wastePercent: wAcc,
          withWaste: russWithW,
          packageSize: 1,
          orderQty: russOrder,
          breakdown: [
            'Parapet LF: ${_lf(parapet.parapetTotalLF)}',
            'Roll length: 100\'',
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${russOrder.toInt()} rolls',
          ],
        ),
      ));

      // RUSS fasteners — 12" O.C. through RUSS into deck; 6" O.C. for >20-yr
      // warranty or ≥90 mph design wind (Versico spec, eval F12).
      final russSpacing = russSpacingIn(projectInfo.warrantyYears, windSpeedMph);
      final russFastName = _fastenerName(systemSpecs.deckType);
      // RUSS sits on top of the insulation at the wall line — the fastener
      // passes through the full stack into the deck, same as the membrane fastener.
      final russStackIn  = _stackThicknessIn(insulation, 3, taperMaxThickness: taperMaxIn);
      final russFastLen  = _selectFastenerLen(systemSpecs.deckType, russStackIn);
      final russBucketSize = _fastenerPack(systemSpecs.deckType, russStackIn).toDouble();
      final russFastBase = parapet.parapetTotalLF * 12.0 / russSpacing;
      final russFastWithW = russFastBase * (1 + wAcc);
      final russFastOrder = (russFastWithW / russBucketSize).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Parapet & Termination',
        name: '$russFastName $russFastLen — RUSS Strip (${russSpacing.toInt()}" o.c.)',
        skuKey: 'fastener_russ_strip',
        attributes: {
          'fastenerName': russFastName,
          'length':       russFastLen,
          'deckType':     systemSpecs.deckType,
        },
        orderQty: russFastOrder,
        unit: 'cartons',
        notes: '${russBucketSize.toInt()}/carton — ${russSpacing.toInt()}" o.c. through RUSS into deck',
        trace: BomTrace(
          baseDescription: '${russFastBase.toStringAsFixed(0)} fasteners ÷ ${russBucketSize.toInt()}/carton',
          baseQty: russFastBase,
          wastePercent: wAcc,
          withWaste: russFastWithW,
          packageSize: russBucketSize,
          orderQty: russFastOrder,
          breakdown: [
            _fastenerBreakdown(systemSpecs.deckType, russStackIn, 'RUSS fastener'),
            'Parapet LF: ${_lf(parapet.parapetTotalLF)}',
            'Spacing: ${russSpacing.toInt()}" o.c.${russSpacing < 12 ? " (>20-yr warranty or ≥90 mph)" : ""}',
            '${parapet.parapetTotalLF.toStringAsFixed(0)} LF × ${(12 / russSpacing).toStringAsFixed(0)}/ft = ${russFastBase.toStringAsFixed(0)} fasteners',
            'Waste: ${_pct(wAcc)}%',
            'Bucket size: ${russBucketSize.toInt()}/carton',
            'ORDER QTY: ${russFastOrder.toInt()} cartons',
          ],
        ),
      ));

      // RUSS seam fastening plates — one per RUSS fastener, 1,000/carton
      const russPlateBoxSize = 1000.0;
      final russPlateOrder = (russFastWithW / russPlateBoxSize).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Parapet & Termination',
        name: 'Seam Fastening Plates — RUSS Strip',
        skuKey: 'plate_russ_seam_fastening',
        attributes: const {},
        orderQty: russPlateOrder,
        unit: 'cartons',
        notes: '${russPlateBoxSize.toInt()}/carton — one plate per RUSS fastener',
        trace: BomTrace(
          baseDescription: '${russFastBase.toStringAsFixed(0)} plates ÷ ${russPlateBoxSize.toInt()}/carton',
          baseQty: russFastBase,
          wastePercent: wAcc,
          withWaste: russFastWithW,
          packageSize: russPlateBoxSize,
          orderQty: russPlateOrder,
          breakdown: [
            'One plate per fastener: ${russFastBase.toStringAsFixed(0)} plates',
            'Carton size: ${russPlateBoxSize.toInt()}/carton',
            'ORDER QTY: ${russPlateOrder.toInt()} cartons',
          ],
        ),
      ));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 13. WALKWAY PADS
    // ══════════════════════════════════════════════════════════════════════════
    // Heat-weldable TPO walkway pads for HVAC access paths.
    // Estimated from RTU count: ~20 LF walkway per RTU access path.
    // Walkway rolls: 3'×50' = 150 sf per roll.

    final rtuCount = penetrations.rtuDetails.length;
    if (rtuCount > 0 && totalArea > 0) {
      // Estimate 20 LF of walkway per RTU for maintenance access
      const walkwayWidthFt = 3.0;
      const walkwayPerRtu = 20.0; // LF per RTU
      const rollSf = 150.0; // 3'×50' roll
      final walkwayLF = rtuCount * walkwayPerRtu;
      final walkwaySf = walkwayLF * walkwayWidthFt;
      final walkBase = walkwaySf / rollSf;
      final walkWithW = walkBase * (1 + wAcc);
      final walkOrder = max(1.0, walkWithW.ceil().toDouble());
      items.add(BomLineItem(
        category: 'Details & Accessories',
        name: 'TPO Walkway Pads (Heat Weldable)',
        skuKey: 'tpo_walkway_pads',
        attributes: const {},
        orderQty: walkOrder,
        unit: 'rolls',
        notes: "3'×50' rolls — HVAC access paths (~${walkwayPerRtu.toInt()} LF per RTU)",
        trace: BomTrace(
          baseDescription: '$rtuCount RTUs × ${walkwayPerRtu.toInt()} LF × 3\' wide ÷ 150 sf/roll',
          baseQty: walkBase,
          wastePercent: wAcc,
          withWaste: walkWithW,
          packageSize: 1,
          orderQty: walkOrder,
          breakdown: [
            'RTU count: $rtuCount',
            'Estimated walkway: ${walkwayPerRtu.toInt()} LF per RTU × 3\' wide',
            'Total walkway area: ${walkwaySf.toStringAsFixed(0)} sf',
            'Roll coverage: 150 sf/roll (3\'×50\')',
            'ORDER QTY: ${walkOrder.toInt()} rolls',
          ],
        ),
      ));
    }

    final consolidated = _consolidate(items);

    return BomResult(
      items: consolidated,
      warnings: warnings,
      isComplete: hasArea && hasDeckType,
    );
  }

  // ─── PRIVATE HELPERS ─────────────────────────────────────────────────────────

  /// Combines items that share the same [BomLineItem.consolidationKey] into a
  /// single line. Sums their pre-package base/withWaste quantities, then ceils
  /// once at the package level. Prevents ordering two boxes of the same SKU
  /// across e.g. Layer 1 and Layer 2 fastener plates when one box would cover
  /// the combined total.
  static List<BomLineItem> _consolidate(List<BomLineItem> items) {
    final groups = <String, List<BomLineItem>>{};
    final order = <String>[];
    for (final it in items) {
      final key = it.consolidationKey;
      if (key == null) continue;
      groups.putIfAbsent(key, () {
        order.add(key);
        return [];
      }).add(it);
    }

    if (groups.isEmpty) return items;

    final mergedKeys = <String, BomLineItem>{};
    for (final entry in groups.entries) {
      final list = entry.value;
      if (list.length == 1) {
        mergedKeys[entry.key] = list.first;
        continue;
      }

      final first = list.first;
      // Trace.baseQty / trace.withWaste are already in RAW UNITS (fasteners,
      // plates, gallons, etc.) — packageSize describes how many fit per
      // ordered package. Sum the raw counts and ceil once at the package level.
      final pkg = first.trace.packageSize;
      double combinedBase = 0;
      double combinedWithW = 0;
      final breakdown = <String>['Combined from ${list.length} sources:'];
      for (final sub in list) {
        combinedBase  += sub.trace.baseQty;
        combinedWithW += sub.trace.withWaste;
        breakdown.add(
          '  • ${sub.name}: ${sub.trace.baseQty.toStringAsFixed(0)} units '
          '(would order ${sub.orderQty.toInt()} ${sub.unit} alone)',
        );
      }

      final orderQty = (combinedWithW / pkg).ceil().toDouble();

      breakdown.addAll([
        'Combined units: ${combinedBase.toStringAsFixed(0)}',
        'Package size:   ${pkg.toInt()} per ${first.unit.replaceAll(RegExp(r"es$|s$"), "")}',
        'With waste:     ${combinedWithW.toStringAsFixed(0)} units = ${(combinedWithW / pkg).toStringAsFixed(2)} ${first.unit}',
        'ORDER QTY:      ${orderQty.toInt()} ${first.unit} (was ${list.fold<double>(0, (a, b) => a + b.orderQty).toInt()} as separate lines)',
      ]);

      final displayName = first.consolidatedName ??
          first.name.replaceFirst(RegExp(r'\s*[—-]\s*(Layer \d+|Tapered Insulation|Cover Board).*$'), '');

      mergedKeys[entry.key] = BomLineItem(
        category: first.category,
        name: displayName,
        orderQty: orderQty,
        unit: first.unit,
        notes: first.notes,
        consolidationKey: first.consolidationKey,
        consolidatedName: first.consolidatedName,
        skuKey: first.skuKey,
        attributes: first.attributes,
        trace: BomTrace(
          baseDescription: '${combinedBase.toStringAsFixed(0)} units ÷ ${pkg.toInt()} per ${first.unit}',
          baseQty: combinedBase,
          wastePercent: first.trace.wastePercent,
          withWaste: combinedWithW,
          packageSize: pkg,
          orderQty: orderQty,
          breakdown: breakdown,
        ),
      );
    }

    // Rebuild the items list, replacing the FIRST occurrence of each merged
    // key with the merged item and dropping subsequent occurrences. Items with
    // no consolidationKey pass through unchanged.
    final emittedKeys = <String>{};
    final result = <BomLineItem>[];
    for (final it in items) {
      final key = it.consolidationKey;
      if (key == null) {
        result.add(it);
        continue;
      }
      if (emittedKeys.contains(key)) continue;
      emittedKeys.add(key);
      result.add(mergedKeys[key]!);
    }
    return result;
  }

  // ─── MA SEAM FASTENING ───────────────────────────────────────────────────────

  /// Seam lap for mechanically attached sheets (5-1/2", Versico MA spec).
  static const double maSeamLapFt = kVersicoMaSeamLapFt;

  static double _rollWidthFt(String rollWidth) =>
      double.tryParse(rollWidth.replaceAll("'", '').trim()) ?? 10.0;

  /// MA membrane fastening from the Versico fastening tables
  /// (lib/data/versico_ma_fastening.dart). Shared by the BOM, the Fastening
  /// Schedule tab and the sub instructions so they never disagree.
  ///
  /// Perimeter sheets run around the whole building edge: the perimeter band
  /// is (number of perimeter sheets × net perimeter sheet width), its area
  /// P × band − corners × band². Everything inside is field sheets. Fasteners
  /// sit in each seam at the table spacing:
  ///   fasteners = area ÷ (net sheet width × spacing).
  static MaFastenerSchedule maFastenerSchedule({
    required double totalArea,
    required double totalPerimeter,
    required int outsideCorners,
    required MembraneSystem membrane,
    required SystemSpecs systemSpecs,
    required ProjectInfo projectInfo,
    required double buildingHeightFt,
  }) {
    final lookup = versicoMaLookup(
      deckType: systemSpecs.deckType,
      woodDeckGrade: systemSpecs.woodDeckGrade,
      windWarrantyMph: projectInfo.windWarrantyMph,
      buildingHeightFt: buildingHeightFt,
      coastlineDistance: projectInfo.coastlineDistance,
      fieldRollWidth: membrane.rollWidth,
      perimeterRollWidth: membrane.perimeterRollWidth,
    );
    final fieldNet = _rollWidthFt(membrane.rollWidth) - maSeamLapFt;
    final perimNet = membrane.perimeterRollWidth == 'None'
        ? fieldNet
        : _rollWidthFt(membrane.perimeterRollWidth) - maSeamLapFt;
    final corners = outsideCorners > 0 ? outsideCorners : 4;
    final band = lookup.perimeterSheets * perimNet;
    final perimArea = totalArea <= 0
        ? 0.0
        : (totalPerimeter * band - corners * band * band).clamp(0.0, totalArea);
    final fieldArea = (totalArea - perimArea).clamp(0.0, totalArea);
    MaZoneFastening zone(double area, double netFt) => MaZoneFastening(
          area: area,
          netSheetWidthFt: netFt,
          spacingIn: lookup.spacingIn,
          fasteners: area <= 0 ? 0 : area / (netFt * lookup.spacingIn / 12.0),
        );
    return MaFastenerSchedule(
      field: zone(fieldArea, fieldNet),
      perimeter: zone(perimArea, perimNet),
      corner: MaZoneFastening(area: 0, netSheetWidthFt: perimNet,
          spacingIn: lookup.spacingIn, fasteners: 0),
      lookup: lookup,
      perimeterBandFt: band,
    );
  }

    // ─── RHINOBOND PLATE DENSITIES ───────────────────────────────────────────────

  /// Returns (fieldDensity, perimDensity, cornerDensity) in plates/sf
  /// for Versico Rhinobond induction-welded system by warranty tier.
  ///
  /// Rhinobond plate density is ~33–50% of MA fastener density because each
  /// induction-welded plate creates a larger bond zone than a single seam fastener.
  /// Source: Versico Rhinobond TPO Installation Guide + FM approval tables.
  ///
  ///  Warranty │ Field    │ Perim    │ Corner   │ vs MA field
  /// ──────────┼──────────┼──────────┼──────────┼────────────
  ///  10-year  │ 0.100/sf │ 0.200/sf │ 0.300/sf │  50% of MA
  ///  15-year  │ 0.125/sf │ 0.250/sf │ 0.375/sf │  50% of MA
  ///  20-year  │ 0.167/sf │ 0.333/sf │ 0.500/sf │  33% of MA
  ///  25-year  │ 0.250/sf │ 0.500/sf │ 0.750/sf │  33% of MA
  ///  30-year  │ 0.333/sf │ 0.667/sf │ 1.000/sf │  33% of MA
  static (double, double, double) _rhinobondDensities(int warrantyYears) {
    switch (warrantyYears) {
      case 10: return (0.100, 0.200, 0.300);
      case 15: return (0.125, 0.250, 0.375);
      case 20: return (0.167, 0.333, 0.500);
      case 25: return (0.250, 0.500, 0.750);
      case 30: return (0.333, 0.667, 1.000);
      default: return (0.167, 0.333, 0.500); // default to 20-year
    }
  }

  /// Insulation fastener density (fasteners per sq ft) by warranty and deck type.
  /// Source: Versico CSI Design Guide — insulation attachment tables.
  /// Standard decks (Metal, Wood): density increases with warranty tier.
  /// Weak decks (Gypsum, Tectum, LW Concrete): always 16/board (0.500/sf), max 20-yr/72 mph.
  static double _insulationDensity(int warrantyYears, String deckType) {
    // Weak deck types — always maximum density, limited warranty
    if (['Gypsum', 'Tectum', 'LW Concrete'].contains(deckType)) {
      return 0.500; // 16 per 4x8 board
    }
    // Standard decks: density by warranty tier
    switch (warrantyYears) {
      case 10: return 0.125;  // 4 per 4x8 board
      case 15: return 0.156;  // 5 per 4x8 board
      case 20: return 0.188;  // 6 per 4x8 board
      case 25: return 0.250;  // 8 per 4x8 board
      case 30: return 0.313;  // 10 per 4x8 board
      default: return 0.188;  // default to 20-year
    }
  }

    static String _fastenerName(String deckType) {
    switch (deckType) {
      case 'Metal':       return 'Versico HPVX';
      case 'Concrete':    return 'Versico MP 14-10';
      case 'Wood':        return 'Versico HPV';
      case 'Gypsum':      return 'Versico HPVX';
      case 'Tectum':      return 'Versico HPVX';
      case 'LW Concrete': return 'Versico CD-10';
      default:            return 'Versico Fastener';
    }
  }

  /// Thickness of the structural deck material itself (inches).
  /// The fastener must pass THROUGH this before the penetration/embedment begins.
  static double _deckThicknessIn(String deckType) {
    switch (deckType) {
      case 'Wood': return 0.75; // standard 3/4" OSB / plywood structural deck
      default:     return 0.0;  // Metal/Concrete: embedment starts at deck surface
    }
  }

  /// Minimum penetration into (or past) the structural deck (inches).
  /// Wood / metal: into the deck material. Concrete: expansion zone below surface.
  static double _deckPenetrationIn(String deckType) {
    switch (deckType) {
      case 'Metal':       return 1.00; // 1" into rib flute (Versico spec)
      case 'Wood':        return 1.00; // 1" minimum into structural deck (Versico/NRCA)
      case 'Concrete':    return 1.25; // 1-1/4" expansion zone (Versico spec)
      case 'LW Concrete': return 1.50; // 1.5" into LW deck
      case 'Gypsum':      return 1.50;
      case 'Tectum':      return 1.50;
      default:            return 1.00;
    }
  }

  /// Available fastener lengths (real inches) for a given deck type.
  static List<double> _fastenerLengthsIn(String deckType) {
    // Lengths QXO stocks for the deck's fastener family (lib/data/qxo_pack_sizes.dart),
    // so every selected length maps to a real SKU. CD-10 (LW concrete) isn't
    // carried by QXO — its catalog lengths are kept.
    final fam = qxoFastenerFamily(_fastenerName(deckType));
    final stocked = kQxoFastenerPacks[fam]?.keys.toList();
    if (stocked != null) return stocked..sort();
    return [3.25, 4.25, 5.25];
  }

  /// Units per carton (QXO) for the fastener selected for [stackThicknessIn].
  static int _fastenerPack(String deckType, double stackThicknessIn) =>
      qxoFastenerPack(_fastenerName(deckType),
          _selectFastener(deckType, stackThicknessIn).lengthIn);

  /// Selects the shortest available fastener length that satisfies:
  ///   insulation stack + deck thickness + deck penetration
  /// Returns a formatted length string like '8"' and the full breakdown string.
  static ({String label, double lengthIn, double minNeeded}) _selectFastener(
      String deckType, double stackThicknessIn) {
    final deckT    = _deckThicknessIn(deckType);
    final penetIn  = _deckPenetrationIn(deckType);
    final minNeeded = stackThicknessIn + deckT + penetIn;
    final available = _fastenerLengthsIn(deckType);

    for (final len in available) {
      if (len >= minNeeded) {
        return (
          label: _fmtIn(len),
          lengthIn: len,
          minNeeded: minNeeded,
        );
      }
    }
    // Stack deeper than standard catalog — flag for manual verification
    final longest = available.last;
    return (
      label: '${_fmtIn(longest)} (verify)',
      lengthIn: longest,
      minNeeded: minNeeded,
    );
  }

  /// Formats an inch value as a clean string: 8.0 → '8"', 4.5 → '4.5"'
  static String _fmtIn(double inches) {
    return inches == inches.truncateToDouble()
        ? '${inches.toInt()}"'
        : '${inches.toStringAsFixed(inches * 2 == (inches * 2).truncateToDouble() ? 1 : 2)}"';
  }

  /// Backward-compatible wrapper — returns just the label string.
  static String _selectFastenerLen(String deckType, double stackThicknessIn) =>
      _selectFastener(deckType, stackThicknessIn).label;

  /// Full breakdown string for hover math: shows each component of the length.
  static String _fastenerBreakdown(String deckType, double stackIn, String purpose) {
    final r       = _selectFastener(deckType, stackIn);
    final deckT   = _deckThicknessIn(deckType);
    final penetIn = _deckPenetrationIn(deckType);
    final parts   = <String>[];
    if (stackIn > 0)  parts.add('${_fmtIn(stackIn)} insulation');
    if (deckT   > 0)  parts.add('${_fmtIn(deckT)} deck');
    parts.add('${_fmtIn(penetIn)} ${deckType == 'Metal' ? 'into flute' : deckType == 'Wood' ? 'into deck' : 'embedment'}');
    return '$purpose: ${parts.join(' + ')} = ${_fmtIn(r.minNeeded)} min → ${r.label}';
  }

  /// Total insulation stack thickness in inches (all MA + adhered layers +
  /// tapered insulation + cover board).
  /// [throughLayer] controls how deep the fastener must pass:
  ///   1 = only layer 1 (insulation fastener for layer 1)
  ///   2 = layer 1 + layer 2 (insulation fastener for layer 2)
  ///   3 = full stack incl. tapered + cover board (membrane/Rhinobond fastener)
  /// [taperMaxThickness] is the max tapered insulation thickness at the ridge
  /// (from BoardScheduleResult.maxThicknessAtRidge). When present, fasteners
  /// must be long enough for the worst-case (thickest) point on the roof.
  static double _stackThicknessIn(InsulationSystem ins, int throughLayer,
      {double taperMaxThickness = 0}) {
    double t = 0;
    if (throughLayer >= 1 && ins.numberOfLayers >= 1) t += ins.layer1.thickness;
    if (throughLayer >= 2 && ins.numberOfLayers == 2 && ins.layer2 != null) {
      t += ins.layer2!.thickness;
    }
    // Tapered insulation sits on top of flat layers, below cover board
    if (throughLayer >= 3 && ins.hasTaper && taperMaxThickness > 0) {
      t += taperMaxThickness;
    }
    if (throughLayer >= 3 && ins.hasCoverBoard && ins.coverBoard != null) {
      t += ins.coverBoard!.thickness;
    }
    return t;
  }

  // Public accessors for sub_instructions_builder
  static String fastenerNamePublic(String deckType) => _fastenerName(deckType);
  static String selectFastenerLenPublic(String deckType, double stackIn) =>
      _selectFastenerLen(deckType, stackIn);
  static double stackThicknessPublic(InsulationSystem ins, int throughLayer) =>
      _stackThicknessIn(ins, throughLayer);

  /// Public: deck types the BOM knows how to fasten into.
  static const List<String> kFastenerDeckTypes = [
    'Metal', 'Wood', 'Concrete', 'LW Concrete', 'Gypsum', 'Tectum',
  ];

  /// Public: stocked fastener lengths (inches) per deck — single source for UI.
  static List<double> fastenerLengthsPublic(String deckType) => _fastenerLengthsIn(deckType);

  /// Public: insulation fasteners per 4'×8' board for the warranty/deck.
  static int insulationFastenersPerBoard(int warrantyYears, String deckType) =>
      (_insulationDensity(warrantyYears, deckType) * 32).round();

  /// Public: fastener lengths (formatted like "4.5\"") available per deck.
  static List<String> fastenerLengthLabels(String deckType) =>
      _fastenerLengthsIn(deckType).map(_fmtIn).toList();

  static String _ins(double t) => '${t == t.roundToDouble() ? t.toInt() : t}"';
  static String _sf(double v)  => '${v.toStringAsFixed(0)} sf';
  static String _lf(double v)  => '${v.toStringAsFixed(0)} LF';
  static String _pct(double f) => (f * 100).toStringAsFixed(0);

  static BomTrace _insTrace(double area, double base, double withW, double orderQty,
      double waste, double boardSf, String label) {
    return BomTrace(
      baseDescription: '${area.toStringAsFixed(0)} sf ÷ ${boardSf.toInt()} sf/board',
      baseQty: base,
      wastePercent: waste,
      withWaste: withW,
      packageSize: 1,
      orderQty: orderQty,
      breakdown: [
        '$label',
        'Area:       ${_sf(area)}',
        'Board size: ${boardSf.toInt()} sf (${boardSf == 16 ? "4\'×4\'" : "4\'×8\'"})',
        'Base:       ${base.toStringAsFixed(1)} boards',
        'Waste:      ${_pct(waste)}%',
        'With waste: ${withW.toStringAsFixed(1)} boards',
        'ORDER QTY:  ${orderQty.toInt()} boards',
      ],
    );
  }

  /// Helper for simple "each" items (penetrations, accessories).
  /// Counted items (drains, boots, kits, corners, downspouts) are ordered
  /// exactly — no waste, so 1 drain is 1 drain assembly, not 2.
  static BomLineItem _eachItem(String cat, String name, double qty,
      String unit, String notes,
      {String? skuKey, Map<String, dynamic>? attributes}) {
    const waste    = 0.0;
    final withW    = qty;
    final orderQty = withW.ceil().toDouble();
    return BomLineItem(
      category: cat,
      name: name,
      orderQty: orderQty,
      unit: unit,
      notes: notes,
      skuKey: skuKey,
      attributes: attributes,
      trace: BomTrace(
        baseDescription: '${qty.toInt()} $unit',
        baseQty: qty,
        wastePercent: waste,
        withWaste: withW,
        packageSize: 1,
        orderQty: orderQty,
        breakdown: [
          'Quantity: ${qty.toInt()}',
          'ORDER QTY: ${orderQty.toInt()} $unit',
        ],
      ),
    );
  }

  /// Helper for linear items sold in 10' pieces (coping, edge metal, gutter, etc.).
  static BomLineItem _linearItem(String cat, String name, double lf,
      double waste, String notes,
      {String? skuKey, Map<String, dynamic>? attributes}) {
    const pieceLen = 10.0;
    final base     = lf / pieceLen;
    final withW    = base * (1 + waste);
    final orderQty = withW.ceil().toDouble();
    return BomLineItem(
      category: cat,
      name: name,
      orderQty: orderQty,
      unit: 'pieces',
      notes: notes,
      skuKey: skuKey,
      attributes: attributes,
      trace: BomTrace(
        baseDescription: '${lf.toStringAsFixed(0)} LF ÷ 10\'',
        baseQty: base,
        wastePercent: waste,
        withWaste: withW,
        packageSize: 1,
        orderQty: orderQty,
        breakdown: [
          '${lf.toStringAsFixed(0)} LF ÷ 10\' = ${base.toStringAsFixed(1)} pieces',
          'Waste: ${_pct(waste)}%',
          'ORDER QTY: ${orderQty.toInt()} pieces (10\' each)',
        ],
      ),
    );
  }

  /// Field seam length: (rolls − 1) shared seams × 100' roll length.
  static double _fieldSeamLF(double fieldArea, double rollCoverage) {
    final rolls = (fieldArea / rollCoverage).ceil();
    return max(0, rolls - 1) * 100.0;
  }

  /// RUSS strip fastener spacing (inches o.c.): 12" standard, 6" when the
  /// warranty exceeds 20 years or the design wind speed is ≥ 90 mph.
  static double russSpacingIn(int warrantyYears, double windSpeedMph) =>
      (warrantyYears > 20 || windSpeedMph >= 90) ? 6.0 : 12.0;

  // ─── WIND SPEED HELPERS ─────────────────────────────────────────────────────

  /// Parse wind speed string (e.g. "115 mph") to double.
  static double _parseWindSpeed(String? windSpeed) {
    if (windSpeed == null || windSpeed.isEmpty) return 0.0;
    final match = RegExp(r'(\d+)').firstMatch(windSpeed);
    return match != null ? double.tryParse(match.group(1)!) ?? 0.0 : 0.0;
  }

  /// Bump warranty tier for fastening density when wind speed is elevated.
  /// ≥90 mph: bump one tier (e.g. 20yr → 25yr density).
  /// ≥130 mph: bump two tiers (hurricane zone).
  /// Capped at 30-year (maximum density).
  static int _windAdjustedWarranty(int warrantyYears, double windSpeedMph) {
    const tiers = [10, 15, 20, 25, 30];
    var idx = tiers.indexOf(warrantyYears);
    if (idx < 0) idx = 2; // default to 20-year position
    if (windSpeedMph >= 130) {
      idx = min(idx + 2, tiers.length - 1);
    } else if (windSpeedMph >= 90) {
      idx = min(idx + 1, tiers.length - 1);
    }
    return tiers[idx];
  }
}

/// One wind zone's MA membrane fastening.
class MaZoneFastening {
  final double area;            // sf
  final double netSheetWidthFt; // roll width − seam lap = seam row spacing
  final double spacingIn;       // fastener spacing along the seam
  final double fasteners;       // raw count, no waste
  const MaZoneFastening({
    required this.area,
    required this.netSheetWidthFt,
    required this.spacingIn,
    required this.fasteners,
  });
}

class MaFastenerSchedule {
  /// Corner is kept for display; Versico's MA tables fold corners into the
  /// perimeter sheets, so its area and count are 0.
  final MaZoneFastening field, perimeter, corner;
  final VersicoMaResult lookup;
  final double perimeterBandFt; // perimeter sheets × net sheet width
  const MaFastenerSchedule({
    required this.field,
    required this.perimeter,
    required this.corner,
    required this.lookup,
    required this.perimeterBandFt,
  });
  double get total => field.fasteners + perimeter.fasteners + corner.fasteners;
}
