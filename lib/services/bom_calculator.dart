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

// ─── BOM LINE ITEM ────────────────────────────────────────────────────────────

/// A single line in the BOM, including the full calculation trace.
class BomLineItem {
  final String category;      // e.g. "Primary System"
  final String name;          // e.g. "60 mil TPO Membrane (10' rolls)"
  final double orderQty;      // final order quantity (whole units)
  final String unit;          // "rolls", "bundles", "boxes", "each", "LF", "gal", "tubes"
  final String notes;         // e.g. "10'×100', 1,000 sf/roll"
  final BomTrace trace;       // full calculation breakdown for hover math

  const BomLineItem({
    required this.category,
    required this.name,
    required this.orderQty,
    required this.unit,
    required this.notes,
    required this.trace,
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
  }) {
    final warnings = <String>[];
    final items    = <BomLineItem>[];

    final wMat  = projectInfo.wasteMaterial;   // e.g. 0.10
    final wMet  = projectInfo.wasteMetal;      // e.g. 0.05
    final wAcc  = projectInfo.wasteAccessory;  // e.g. 0.05

    final totalArea      = geometry.totalArea;
    final fieldArea      = geometry.windZones.fieldZoneArea;
    final perimArea      = geometry.windZones.perimeterZoneArea;
    final cornerArea     = geometry.windZones.cornerZoneArea;
    final parapetArea    = parapet.hasParapetWalls ? parapet.parapetArea : 0.0;
    final termBarLF      = parapet.hasParapetWalls ? parapet.terminationBarLF : 0.0;
    final totalPerimeter = geometry.totalPerimeter;
    final drainCount     = geometry.numberOfDrains;

    // Check for minimum inputs
    final bool hasArea     = totalArea > 0;
    final bool hasZones    = geometry.windZones.perimeterZoneWidth > 0;
    final bool hasDeckType = systemSpecs.deckType.isNotEmpty;

    if (!hasArea)     warnings.add('BLOCKER: Enter roof dimensions to calculate BOM.');
    if (!hasZones)    warnings.add('WARNING: Wind zone widths missing — fastener quantities estimated from total area.');
    if (!hasDeckType) warnings.add('BLOCKER: Deck type required to select fasteners.');
    if (projectInfo.warrantyYears == 0) {
      warnings.add('WARNING: Warranty years not set — fastening density defaulting to 20-year pattern.');
    }

    // ── EFFECTIVE AREAS ──────────────────────────────────────────────────────
    // When zone areas aren't set, fall back to total area for membrane rolls.
    final effectiveFieldArea  = hasZones ? fieldArea  : totalArea;
    final effectivePerimArea  = hasZones ? perimArea  : 0.0;
    final effectiveCornerArea = hasZones ? cornerArea : 0.0;
    // Flashing area = parapet + perimeter zone + corner zone (all use 6'×100' rolls)
    final flashingArea = parapetArea + effectivePerimArea + effectiveCornerArea;

    // ══════════════════════════════════════════════════════════════════════════
    // 1. MEMBRANE
    // ══════════════════════════════════════════════════════════════════════════

    final fieldRollCoverage = membrane.rollCoverage;         // e.g. 1000 sf
    final flashRollCoverage = membrane.perimeterRollCoverage; // always 600 sf

    // 1a. Field rolls
    if (effectiveFieldArea > 0) {
      final base     = effectiveFieldArea / fieldRollCoverage;
      final withW    = base * (1 + wMat);
      final orderQty = withW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Membrane',
        name: '${membrane.thickness} ${membrane.membraneType} — Field (${membrane.rollWidth}×100\')',
        orderQty: orderQty,
        unit: 'rolls',
        notes: '${membrane.rollWidth}×100\', ${fieldRollCoverage.toInt()} sf/roll',
        trace: BomTrace(
          baseDescription: '${_sf(effectiveFieldArea)} ÷ ${fieldRollCoverage.toInt()} sf/roll',
          baseQty: base,
          wastePercent: wMat,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            'Field area:    ${_sf(effectiveFieldArea)}',
            'Roll coverage: ${fieldRollCoverage.toInt()} sf/roll (${membrane.rollWidth}×100\')',
            'Base qty:      ${base.toStringAsFixed(2)} rolls',
            'Waste:         ${_pct(wMat)}%',
            'With waste:    ${withW.toStringAsFixed(2)} rolls',
            'ORDER QTY:     ${orderQty.toInt()} rolls',
          ],
        ),
      ));
    }

    // 1b. Flashing / perimeter rolls (6'×100')
    if (flashingArea > 0) {
      final base     = flashingArea / flashRollCoverage;
      final withW    = base * (1 + wMat);
      final orderQty = withW.ceil().toDouble();
      final parts = <String>[];
      if (parapetArea > 0)           parts.add('parapet ${_sf(parapetArea)}');
      if (effectivePerimArea > 0)    parts.add('perimeter zone ${_sf(effectivePerimArea)}');
      if (effectiveCornerArea > 0)   parts.add('corner zone ${_sf(effectiveCornerArea)}');
      items.add(BomLineItem(
        category: 'Membrane',
        name: '${membrane.thickness} ${membrane.membraneType} — Flashing (6\'×100\')',
        orderQty: orderQty,
        unit: 'rolls',
        notes: "6'×100', 600 sf/roll — parapet, perimeter & corner zones",
        trace: BomTrace(
          baseDescription: '${_sf(flashingArea)} ÷ 600 sf/roll',
          baseQty: base,
          wastePercent: wMat,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            'Flashing area breakdown:',
            ...parts.map((p) => '  $p'),
            'Total flashing: ${_sf(flashingArea)}',
            'Roll coverage:  600 sf/roll (6\'×100\')',
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
      // Layer 1
      final l1 = insulation.layer1;
      if (l1.thickness > 0) {
        final base     = totalArea / boardSf;
        final withW    = base * (1 + wMat);
        final orderQty = withW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Insulation',
          name: '${l1.type} ${_ins(l1.thickness)} — Layer 1',
          orderQty: orderQty,
          unit: 'boards',
          notes: "4'×8' boards (${boardSf.toInt()} sf each), ${l1.attachmentMethod}",
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
            trace: _insTrace(totalArea, base, withW, orderQty, wMat, boardSf,
                'Layer 2 — ${l2.type} ${_ins(l2.thickness)}'),
          ));
        }
      }

      // Tapered insulation
      if (insulation.hasTaperedInsulation && insulation.tapered != null) {
        final taper      = insulation.tapered!;
        final taperArea  = taper.systemArea > 0 ? taper.systemArea : totalArea;
        final base       = taperArea / boardSf;
        final withW      = base * (1 + wMat);
        final orderQty   = withW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Insulation',
          name: 'Tapered Polyiso — ${taper.taperSlope} slope',
          orderQty: orderQty,
          unit: 'boards',
          notes: 'Min ${_ins(taper.minThicknessAtDrain)} at drain, tapered system',
          trace: _insTrace(taperArea, base, withW, orderQty, wMat, boardSf,
              'Tapered — ${taper.boardType.isNotEmpty ? taper.boardType : "Polyiso"}'),
        ));
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

    // ── MECHANICALLY ATTACHED (MA) ───────────────────────────────────────────
    // Through-membrane fasteners + seam stress plates.
    // Density driven by warranty tier per Versico MA tables.
    if (isMA && totalArea > 0) {
      final densities     = _fasteningDensities(projectInfo.warrantyYears);
      final fieldDensity  = densities.$1;
      final perimDensity  = densities.$2;
      final cornerDensity = densities.$3;

      final fieldFast  = (hasZones ? effectiveFieldArea  : totalArea) * fieldDensity;
      final perimFast  = hasZones ? effectivePerimArea  * perimDensity  : 0.0;
      final cornerFast = hasZones ? effectiveCornerArea * cornerDensity : 0.0;
      final totalFast  = fieldFast + perimFast + cornerFast;

      const boxSize = 500.0;
      final withW    = totalFast * (1 + wAcc);
      final orderQty = (withW / boxSize).ceil().toDouble();

      final fastenerName = _fastenerName(systemSpecs.deckType);
      final memStackIn   = _stackThicknessIn(insulation, 3);
      final memFastLen   = _selectFastenerLen(systemSpecs.deckType, memStackIn);

      items.add(BomLineItem(
        category: 'Fasteners & Plates',
        name: '$fastenerName $memFastLen — ${systemSpecs.deckType} Deck (MA Membrane)',
        orderQty: orderQty,
        unit: 'boxes',
        notes: '500/box — field, perimeter & corner zones',
        trace: BomTrace(
          baseDescription: '${totalFast.toStringAsFixed(0)} fasteners ÷ 500/box',
          baseQty: totalFast,
          wastePercent: wAcc,
          withWaste: withW,
          packageSize: boxSize,
          orderQty: orderQty,
          breakdown: [
            _fastenerBreakdown(systemSpecs.deckType, memStackIn, 'MA membrane fastener'),
            if (hasZones) ...[
              'Fastening: ${projectInfo.warrantyYears}-yr warranty → field ${fieldDensity.toStringAsFixed(2)}/sf, perim ${perimDensity.toStringAsFixed(2)}/sf, corner ${cornerDensity.toStringAsFixed(2)}/sf',
              'Field zone:     ${_sf(effectiveFieldArea)} × ${fieldDensity.toStringAsFixed(2)}/sf = ${fieldFast.toStringAsFixed(0)}',
              'Perimeter zone: ${_sf(effectivePerimArea)} × ${perimDensity.toStringAsFixed(2)}/sf = ${perimFast.toStringAsFixed(0)}',
              'Corner zone:    ${_sf(effectiveCornerArea)} × ${cornerDensity.toStringAsFixed(2)}/sf = ${cornerFast.toStringAsFixed(0)}',
            ] else
              'Total area (no zones): ${_sf(totalArea)} × ${fieldDensity.toStringAsFixed(2)}/sf = ${fieldFast.toStringAsFixed(0)}',
            'Total fasteners: ${totalFast.toStringAsFixed(0)}',
            'Waste: ${_pct(wAcc)}%  →  With waste: ${withW.toStringAsFixed(0)}',
            'ORDER QTY: ${orderQty.toInt()} boxes (500/box)',
          ],
        ),
      ));

      // Seam stress plates — one per MA fastener
      const plateBoxSize = 1000.0;
      final plateWithW   = totalFast * (1 + wAcc);
      final plateOrder   = (plateWithW / plateBoxSize).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Fasteners & Plates',
        name: '3" Seam Stress Plates',
        orderQty: plateOrder,
        unit: 'boxes',
        notes: '1,000/box — one plate per MA fastener',
        trace: BomTrace(
          baseDescription: '${totalFast.toStringAsFixed(0)} plates ÷ 1,000/box',
          baseQty: totalFast,
          wastePercent: wAcc,
          withWaste: plateWithW,
          packageSize: plateBoxSize,
          orderQty: plateOrder,
          breakdown: [
            'One seam plate per fastener: ${totalFast.toStringAsFixed(0)}',
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${plateOrder.toInt()} boxes (1,000/box)',
          ],
        ),
      ));
    }

    // ── RHINOBOND (INDUCTION WELDED) ──────────────────────────────────────────
    // Versico Rhinobond: steel plates fastened through insulation to deck,
    // then membrane inductively welded to plate tops — no through-membrane fasteners.
    //
    // BOM has THREE separate line items:
    //   1. Rhinobond induction weld plates (250/carton)
    //   2. Fasteners for plates — same sizing logic as MA, one per plate
    //   3. Insulation fasteners (handled below in insulation section, same as MA)
    //
    // Plate density is ~33–50% of MA fastener density (larger bond area per plate).
    // Source: Versico Rhinobond TPO Installation Guide & FM approval tables.
    if (isRhinobond && totalArea > 0) {
      final rbDensities     = _rhinobondDensities(projectInfo.warrantyYears);
      final rbFieldDensity  = rbDensities.$1;
      final rbPerimDensity  = rbDensities.$2;
      final rbCornerDensity = rbDensities.$3;

      final rbFieldPlates  = (hasZones ? effectiveFieldArea  : totalArea) * rbFieldDensity;
      final rbPerimPlates  = hasZones ? effectivePerimArea  * rbPerimDensity  : 0.0;
      final rbCornerPlates = hasZones ? effectiveCornerArea * rbCornerDensity : 0.0;
      final rbTotalPlates  = rbFieldPlates + rbPerimPlates + rbCornerPlates;

      // ── Rhinobond induction weld plates ──────────────────────────────────
      const rbCartonSize = 250.0; // Versico Rhinobond plates: 250/carton
      final rbPlateWithW = rbTotalPlates * (1 + wAcc);
      final rbPlateOrder = (rbPlateWithW / rbCartonSize).ceil().toDouble();

      items.add(BomLineItem(
        category: 'Fasteners & Plates',
        name: 'Rhinobond Induction Weld Plates',
        orderQty: rbPlateOrder,
        unit: 'cartons',
        notes: '250/carton — Versico Rhinobond TPO system',
        trace: BomTrace(
          baseDescription: '${rbTotalPlates.toStringAsFixed(0)} plates ÷ 250/carton',
          baseQty: rbTotalPlates,
          wastePercent: wAcc,
          withWaste: rbPlateWithW,
          packageSize: rbCartonSize,
          orderQty: rbPlateOrder,
          breakdown: [
            'Rhinobond plate grid (${projectInfo.warrantyYears}-yr warranty):',
            '  Field density:   ${rbFieldDensity.toStringAsFixed(3)}/sf  (MA equiv: ${(_fasteningDensities(projectInfo.warrantyYears).$1).toStringAsFixed(2)}/sf)',
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
            'ORDER QTY: ${rbPlateOrder.toInt()} cartons (250/carton)',
          ],
        ),
      ));

      // ── Fasteners for Rhinobond plates (one per plate, through insulation to deck) ─
      final memStackIn   = _stackThicknessIn(insulation, 3);
      final rbFastName   = _fastenerName(systemSpecs.deckType);
      final rbFastLen    = _selectFastenerLen(systemSpecs.deckType, memStackIn);
      const rbFastBox    = 500.0;
      final rbFastWithW  = rbTotalPlates * (1 + wAcc);
      final rbFastOrder  = (rbFastWithW / rbFastBox).ceil().toDouble();

      items.add(BomLineItem(
        category: 'Fasteners & Plates',
        name: '$rbFastName $rbFastLen — ${systemSpecs.deckType} Deck (Rhinobond)',
        orderQty: rbFastOrder,
        unit: 'boxes',
        notes: '500/box — one fastener per Rhinobond plate',
        trace: BomTrace(
          baseDescription: '${rbTotalPlates.toStringAsFixed(0)} fasteners ÷ 500/box',
          baseQty: rbTotalPlates,
          wastePercent: wAcc,
          withWaste: rbFastWithW,
          packageSize: rbFastBox,
          orderQty: rbFastOrder,
          breakdown: [
            _fastenerBreakdown(systemSpecs.deckType, memStackIn, 'Rhinobond plate fastener'),
            'One fastener per plate: ${rbTotalPlates.toStringAsFixed(0)}',
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${rbFastOrder.toInt()} boxes (500/box)',
          ],
        ),
      ));
    }

    // Insulation fasteners — one line item per MA layer, each with computed length
    if (totalArea > 0) {
      final l1MA = insulation.layer1.attachmentMethod == 'Mechanically Attached';
      final l2MA = insulation.numberOfLayers == 2 &&
          (insulation.layer2?.attachmentMethod == 'Mechanically Attached' ?? false);
      final cbMA = insulation.hasCoverBoard &&
          (insulation.coverBoard?.attachmentMethod == 'Mechanically Attached' ?? false);

      // 4 fasteners per 4'×8' board = 0.125/sf
      const insDensity = 0.125;
      const insBoxSize = 500.0;

      // Layer 1 MA: fastener only passes through layer 1 stack
      if (l1MA) {
        final l1StackIn = _stackThicknessIn(insulation, 1);
        final l1Len     = _selectFastenerLen(systemSpecs.deckType, l1StackIn);
        final base      = totalArea * insDensity;
        final withW     = base * (1 + wAcc);
        final orderQty  = (withW / insBoxSize).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '${_fastenerName(systemSpecs.deckType)} $l1Len — Layer 1 Insulation',
          orderQty: orderQty,
          unit: 'boxes',
          notes: '500/box — 4 per 4\'×8\' board (${insulation.layer1.type})',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} fasteners ÷ 500/box',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: insBoxSize,
            orderQty: orderQty,
            breakdown: [
              _fastenerBreakdown(systemSpecs.deckType, l1StackIn, 'Layer 1 fastener'),
              '${_sf(totalArea)} × $insDensity/sf = ${base.toStringAsFixed(0)} fasteners',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${orderQty.toInt()} boxes (500/box)',
            ],
          ),
        ));
      }

      // Layer 2 MA: fastener passes through BOTH layer 2 AND layer 1 to reach deck
      if (l2MA) {
        final l2StackIn = _stackThicknessIn(insulation, 2); // L1 + L2 thickness
        final l2Len     = _selectFastenerLen(systemSpecs.deckType, l2StackIn);
        final base      = totalArea * insDensity;
        final withW     = base * (1 + wAcc);
        final orderQty  = (withW / insBoxSize).ceil().toDouble();
        final l2type    = insulation.layer2?.type ?? '';
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '${_fastenerName(systemSpecs.deckType)} $l2Len — Layer 2 Insulation',
          orderQty: orderQty,
          unit: 'boxes',
          notes: '500/box — 4 per board, through L1+L2 ($l2type)',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} fasteners ÷ 500/box',
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
              'ORDER QTY: ${orderQty.toInt()} boxes (500/box)',
            ],
          ),
        ));
      }

      // Cover board MA: passes through cover board + insulation stack
      if (cbMA) {
        final cbStackIn = _stackThicknessIn(insulation, 3); // full stack
        final cbLen     = _selectFastenerLen(systemSpecs.deckType, cbStackIn);
        final base      = totalArea * insDensity;
        final withW     = base * (1 + wAcc);
        final orderQty  = (withW / insBoxSize).ceil().toDouble();
        final cbtype    = insulation.coverBoard?.type ?? 'Cover Board';
        items.add(BomLineItem(
          category: 'Fasteners & Plates',
          name: '${_fastenerName(systemSpecs.deckType)} $cbLen — Cover Board',
          orderQty: orderQty,
          unit: 'boxes',
          notes: '500/box — 4 per board ($cbtype)',
          trace: BomTrace(
            baseDescription: '${base.toStringAsFixed(0)} fasteners ÷ 500/box',
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
              'ORDER QTY: ${orderQty.toInt()} boxes (500/box)',
            ],
          ),
        ));
      }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4. ADHESIVES & SEALANTS
    // ══════════════════════════════════════════════════════════════════════════

    // Bonding adhesive (Fully Adhered membrane or adhered insulation/coverboard)
    final adheredMemArea = isFA ? (totalArea + parapetArea) : parapetArea;
    final adheredInsArea = [
      if (insulation.layer1.attachmentMethod == 'Adhered') totalArea,
      if (insulation.numberOfLayers == 2 &&
          (insulation.layer2?.attachmentMethod == 'Adhered' ?? false)) totalArea,
      if (insulation.hasCoverBoard &&
          (insulation.coverBoard?.attachmentMethod == 'Adhered' ?? false)) totalArea,
    ].fold(0.0, (a, b) => a + b);

    final totalAdheredArea = adheredMemArea + adheredInsArea;
    if (totalAdheredArea > 0) {
      // Cav-Grip III: ~60 sf per gallon, 15-gal cylinder
      const coveragePerGal = 60.0;
      const galPerCylinder = 15.0;
      final base       = totalAdheredArea / coveragePerGal;
      final withW      = base * (1 + wAcc);
      final cylinders  = (withW / galPerCylinder).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Adhesives & Sealants',
        name: 'Bonding Adhesive (Cav-Grip III)',
        orderQty: cylinders,
        unit: 'cylinders',
        notes: '15-gal cylinder, ~60 sf/gal',
        trace: BomTrace(
          baseDescription: '${_sf(totalAdheredArea)} ÷ 60 sf/gal',
          baseQty: base,
          wastePercent: wAcc,
          withWaste: withW,
          packageSize: galPerCylinder,
          orderQty: cylinders,
          breakdown: [
            if (isFA)        'FA membrane area: ${_sf(totalArea + parapetArea)}',
            if (!isFA && parapetArea > 0) 'Parapet flashing (adhered): ${_sf(parapetArea)}',
            if (adheredInsArea > 0) 'Adhered insulation area: ${_sf(adheredInsArea)}',
            'Coverage rate: 60 sf/gal',
            'Base gallons:  ${base.toStringAsFixed(1)}',
            'Waste:         ${_pct(wAcc)}%',
            'With waste:    ${withW.toStringAsFixed(1)} gal',
            'Cylinder size: 15 gal',
            'ORDER QTY:     ${cylinders.toInt()} cylinders',
          ],
        ),
      ));
    }

    // Cut-edge sealant — estimated from seam LF
    // Seam LF ≈ totalArea / rollWidth (each roll creates one seam)
    if (totalArea > 0) {
      final rollWidthFt  = double.tryParse(membrane.rollWidth.replaceAll("'", '')) ?? 10.0;
      final seamLF       = totalArea / rollWidthFt;
      // 1 tube (10 oz) covers ~50 LF of cut edge
      const lfPerTube    = 50.0;
      final base         = seamLF / lfPerTube;
      final withW        = base * (1 + wAcc);
      final orderQty     = withW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Adhesives & Sealants',
        name: 'TPO Cut Edge Sealant',
        orderQty: orderQty,
        unit: 'tubes',
        notes: '10 oz tubes, ~50 LF/tube',
        trace: BomTrace(
          baseDescription: '${seamLF.toStringAsFixed(0)} LF seams ÷ 50 LF/tube',
          baseQty: base,
          wastePercent: wAcc,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            'Est. seam LF: ${_sf(totalArea)} ÷ ${rollWidthFt.toInt()} ft roll = ${seamLF.toStringAsFixed(0)} LF',
            'Coverage: 50 LF/tube',
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${orderQty.toInt()} tubes',
          ],
        ),
      ));
    }

    // Water block / lap sealant
    if (totalArea > 0) {
      // ~1 tube per 10 penetrations / 200 LF of seam — simplified: 1 per 5 rolls
      final fieldRolls = (totalArea / membrane.rollCoverage).ceil();
      final base       = (fieldRolls / 5).ceilToDouble();
      final withW      = base * (1 + wAcc);
      final orderQty   = withW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Adhesives & Sealants',
        name: 'Water Block Sealant',
        orderQty: orderQty,
        unit: 'tubes',
        notes: '10 oz tubes — T-joints, laps, penetrations',
        trace: BomTrace(
          baseDescription: '1 tube per 5 field rolls (estimated)',
          baseQty: base,
          wastePercent: wAcc,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            'Field rolls: $fieldRolls',
            'Est. ratio: 1 tube per 5 rolls',
            'Base: ${base.toStringAsFixed(0)} tubes',
            'ORDER QTY: ${orderQty.toInt()} tubes',
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
        final orderQty = withW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Parapet & Termination',
          name: '$tbFastener $tbLength — Termination Bar (${parapet.wallType})',
          orderQty: orderQty,
          unit: 'each',
          notes: tbNotes,
          trace: BomTrace(
            baseDescription: '${_lf(termBarLF)} × 12" ÷ ${spacingIn.toInt()}" o.c.',
            baseQty: base,
            wastePercent: wAcc,
            withWaste: withW,
            packageSize: 1,
            orderQty: orderQty,
            breakdown: [
              'Wall type:  ${parapet.wallType} → $tbFastener $tbLength',
              'Spacing:    ${spacingIn.toInt()}" o.c.',
              '${_lf(termBarLF)} × 12"/ft ÷ ${spacingIn.toInt()}" = ${base.toStringAsFixed(0)} fasteners',
              'Waste: ${_pct(wAcc)}%',
              'ORDER QTY: ${orderQty.toInt()} each',
            ],
          ),
        ));
      }
    }

    // ── Edge metal fasteners (eave / rake termination into deck) ─────────────
    // Edge metal (gravel stop, drip edge, ES-1) is fastened to the deck nailer
    // or directly into the deck at the roof edge — no insulation in the flange.
    // Spacing: 12" o.c. per SMACNA standards.
    final edgeMetalLF = metalScope.edgeMetalLF;
    if (edgeMetalLF > 0 && hasDeckType) {
      const edgeSpacingIn = 12.0; // 12" o.c. for edge metal
      // Edge metal fastener goes through metal flange only (~0" insulation at edge)
      final edgeFastLen   = _selectFastenerLen(systemSpecs.deckType, 0);
      final edgeFastName  = _fastenerName(systemSpecs.deckType);
      final base          = edgeMetalLF * 12.0 / edgeSpacingIn;
      final withW         = base * (1 + wAcc);
      final orderQty      = withW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Parapet & Termination',
        name: '$edgeFastName $edgeFastLen — Edge Metal (${metalScope.edgeMetalType})',
        orderQty: orderQty,
        unit: 'each',
        notes: '12" o.c. — eave/rake edge attachment',
        trace: BomTrace(
          baseDescription: '${_lf(edgeMetalLF)} × 12" ÷ 12" o.c.',
          baseQty: base,
          wastePercent: wAcc,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            'Deck type:  ${systemSpecs.deckType} → $edgeFastName $edgeFastLen',
            'Location:   eave/rake (no insulation in flange)',
            'Spacing:    12" o.c. per SMACNA standards',
            '${_lf(edgeMetalLF)} × 12"/ft ÷ 12" = ${base.toStringAsFixed(0)} fasteners',
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${orderQty.toInt()} each',
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
          insideCorners.toDouble(), wAcc, 'each', ''));
    }

    // Outside corners — from geometry OR default 4
    final outsideCorners = geometry.outsideCorners > 0 ? geometry.outsideCorners : 4;
    if (outsideCorners > 0) {
      items.add(_eachItem('Details & Accessories', 'TPO Outside Corners (Prefab)',
          outsideCorners.toDouble(), wAcc, 'each', ''));
    }

    // T-joint covers — estimated: 1 per roll minus perimeter
    if (totalArea > 0) {
      final fieldRolls = (effectiveFieldArea / membrane.rollCoverage).ceil();
      final tJoints    = (fieldRolls * 0.75).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Details & Accessories',
        name: 'T-Joint Covers',
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
          drainCount.toDouble(), wAcc, 'each', penetrations.drainType));
    }

    // Pipe boots — small
    if (penetrations.smallPipeCount > 0) {
      items.add(_eachItem('Details & Accessories', 'Pipe Boot — Small (1–4")',
          penetrations.smallPipeCount.toDouble(), wAcc, 'each', ''));
    }

    // Pipe boots — large
    if (penetrations.largePipeCount > 0) {
      items.add(_eachItem('Details & Accessories', 'Pipe Boot — Large (4–12")',
          penetrations.largePipeCount.toDouble(), wAcc, 'each', ''));
    }

    // Skylights
    if (penetrations.skylightCount > 0) {
      items.add(_eachItem('Details & Accessories', 'Skylight Flashing Kit',
          penetrations.skylightCount.toDouble(), wAcc, 'each', ''));
    }

    // Scuppers
    if (penetrations.scupperCount > 0) {
      items.add(_eachItem('Details & Accessories', 'Scupper Assembly',
          penetrations.scupperCount.toDouble(), wAcc, 'each', ''));
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
      items.add(_eachItem('Details & Accessories', 'Pitch Pan',
          penetrations.pitchPanCount.toDouble(), wAcc, 'each', ''));
    }

    // RTU flashing (perimeter rolls)
    if (penetrations.rtuTotalLF > 0) {
      // RTU curb height typically 12" — add 2× for overlap: 2 × LF × (curb + 12" up wall)
      final rtuFlashSF = penetrations.rtuTotalLF * 2.0; // 24" effective strip
      final base       = rtuFlashSF / flashRollCoverage;
      final withW      = base * (1 + wMat);
      final orderQty   = withW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Details & Accessories',
        name: 'TPO Curb Flashing — RTU (6\'×100\')',
        orderQty: orderQty,
        unit: 'rolls',
        notes: "RTU curbs — ${_lf(penetrations.rtuTotalLF)} curb perimeter",
        trace: BomTrace(
          baseDescription: '${_lf(penetrations.rtuTotalLF)} × 2 ÷ 600 sf/roll',
          baseQty: base,
          wastePercent: wMat,
          withWaste: withW,
          packageSize: 1,
          orderQty: orderQty,
          breakdown: [
            'RTU curb LF: ${_lf(penetrations.rtuTotalLF)}',
            'Strip width est.: 24" (curb up + onto field)',
            'Flash SF: ${rtuFlashSF.toStringAsFixed(0)}',
            'Roll: 600 sf/roll',
            'ORDER QTY: ${orderQty.toInt()} rolls',
          ],
        ),
      ));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 7. METAL SCOPE
    // ══════════════════════════════════════════════════════════════════════════

    if (metalScope.copingLF > 0) {
      items.add(_linearItem('Metal Scope', 'Coping Cap — ${metalScope.copingWidth}',
          metalScope.copingLF, wMet, "10' sections"));
    }

    if (metalScope.wallFlashingLF > 0) {
      items.add(_linearItem('Metal Scope', 'Wall Flashing',
          metalScope.wallFlashingLF, wMet, "10' sections"));
    }
    if (metalScope.dripEdgeLF > 0) {
      items.add(_linearItem('Metal Scope', 'Drip Edge — ${metalScope.edgeMetalType}',
          metalScope.dripEdgeLF, wMet, "10' sections"));
    }
    if (metalScope.otherEdgeMetalLF > 0) {
      items.add(_linearItem('Metal Scope', 'Other Edge Metal',
          metalScope.otherEdgeMetalLF, wMet, "10' sections"));
    }

    if (metalScope.gutterLF > 0) {
      items.add(_linearItem('Metal Scope', 'Gutter — ${metalScope.gutterSize}',
          metalScope.gutterLF, wMet, "10' sections"));
    }

    if (metalScope.downspoutCount > 0) {
      items.add(_eachItem('Metal Scope', 'Downspout',
          metalScope.downspoutCount.toDouble(), wMet, 'each', ''));
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

    return BomResult(
      items: items,
      warnings: warnings,
      isComplete: hasArea && hasDeckType,
    );
  }

  // ─── PRIVATE HELPERS ─────────────────────────────────────────────────────────

  // ─── WARRANTY-DRIVEN FASTENING DENSITIES ─────────────────────────────────────

  /// Returns (fieldDensity, perimDensity, cornerDensity) in fasteners/sf
  /// based on the Versico MA warranty tier minimums.
  ///
  /// Source: Versico TPO Mechanically Attached Fastening Tables.
  /// Higher warranty levels require tighter fastening patterns.
  ///
  ///  Warranty │ Field  │ Perim  │ Corner │ Field spacing
  /// ──────────┼────────┼────────┼────────┼──────────────
  ///  10-year  │ 0.20/sf│ 0.40/sf│ 0.60/sf│ 1 per 5 sf
  ///  15-year  │ 0.25/sf│ 0.50/sf│ 0.75/sf│ 1 per 4 sf
  ///  20-year  │ 0.50/sf│ 1.00/sf│ 1.49/sf│ 1 per 2 sf
  ///  25-year  │ 0.75/sf│ 1.49/sf│ 2.00/sf│ 1 per 1.3 sf
  ///  30-year  │ 1.00/sf│ 2.00/sf│ 2.99/sf│ 1 per 1 sf
  static (double, double, double) _fasteningDensities(int warrantyYears) {
    switch (warrantyYears) {
      case 10: return (0.20, 0.40, 0.60);
      case 15: return (0.25, 0.50, 0.75);
      case 20: return (0.50, 1.00, 1.49);
      case 25: return (0.75, 1.49, 2.00);
      case 30: return (1.00, 2.00, 2.99);
      default: return (0.50, 1.00, 1.49); // default to 20-year if unset
    }
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

    static String _fastenerName(String deckType) {
    switch (deckType) {
      case 'Metal':       return '#14 HP';
      case 'Concrete':    return 'Concrete Anchor';
      case 'Wood':        return 'Wood Screw';
      case 'Gypsum':      return 'Gypsum Fastener';
      case 'Tectum':      return 'Tectum Fastener';
      case 'LW Concrete': return 'LW Concrete Anchor';
      default:            return 'Fastener';
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
  /// Metal #14 HP: 3", 4.5", 6", 7.5", 9", 10.5", 12" (Versico catalog).
  /// Wood screws:  2.5", 3.5", 4.5", 6", 8", 10", 12" (IBC-compliant roofing screws).
  /// Concrete / LW: limited anchor lengths per manufacturer.
  static List<double> _fastenerLengthsIn(String deckType) {
    switch (deckType) {
      case 'Metal':       return [3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0];
      case 'Wood':        return [2.5, 3.5, 4.5, 6.0, 8.0, 10.0, 12.0];
      case 'Concrete':    return [2.25, 3.25, 4.25];
      case 'LW Concrete': return [3.25, 4.25, 5.25];
      case 'Gypsum':
      case 'Tectum':      return [3.0, 4.0, 5.0, 6.0, 8.0, 10.0];
      default:            return [3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0];
    }
  }

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

  /// Total insulation stack thickness in inches (all MA + adhered layers + cover board).
  /// [throughLayer] controls how deep the fastener must pass:
  ///   1 = only layer 1 (insulation fastener for layer 1)
  ///   2 = layer 1 + layer 2 (insulation fastener for layer 2)
  ///   3 = full stack incl. cover board (membrane/Rhinobond fastener)
  static double _stackThicknessIn(InsulationSystem ins, int throughLayer) {
    double t = 0;
    if (throughLayer >= 1) t += ins.layer1.thickness;
    if (throughLayer >= 2 && ins.numberOfLayers == 2 && ins.layer2 != null) {
      t += ins.layer2!.thickness;
    }
    if (throughLayer >= 3 && ins.hasCoverBoard && ins.coverBoard != null) {
      t += ins.coverBoard!.thickness;
    }
    return t;
  }

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
        'Board size: ${boardSf.toInt()} sf (4\'×8\')',
        'Base:       ${base.toStringAsFixed(1)} boards',
        'Waste:      ${_pct(waste)}%',
        'With waste: ${withW.toStringAsFixed(1)} boards',
        'ORDER QTY:  ${orderQty.toInt()} boards',
      ],
    );
  }

  /// Helper for simple "each" items (penetrations, accessories).
  static BomLineItem _eachItem(String cat, String name, double qty,
      double waste, String unit, String notes) {
    final withW    = qty * (1 + waste);
    final orderQty = withW.ceil().toDouble();
    return BomLineItem(
      category: cat,
      name: name,
      orderQty: orderQty,
      unit: unit,
      notes: notes,
      trace: BomTrace(
        baseDescription: '${qty.toInt()} $unit',
        baseQty: qty,
        wastePercent: waste,
        withWaste: withW,
        packageSize: 1,
        orderQty: orderQty,
        breakdown: [
          'Quantity: ${qty.toInt()}',
          if (waste > 0) 'Waste: ${_pct(waste)}% → ${withW.ceil()} $unit',
          'ORDER QTY: ${orderQty.toInt()} $unit',
        ],
      ),
    );
  }

  /// Helper for linear items sold in 10' pieces (coping, edge metal, gutter, etc.).
  static BomLineItem _linearItem(String cat, String name, double lf,
      double waste, String notes) {
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
}
