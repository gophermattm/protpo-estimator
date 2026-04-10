/// lib/services/validation_engine.dart
///
/// Real-time validation engine for ProTPO.
///
/// Runs continuously as inputs change and produces:
///   1. Validation issues (errors, warnings, info)
///   2. Missing companion items per Versico spec
///   3. Project health score
///
/// Versico spec rules are hardcoded from the TPO Installation Guide,
/// Detail Manual, and Field Guide.

import '../models/project_info.dart';
import '../models/roof_geometry.dart';
import '../models/insulation_system.dart';
import '../models/section_models.dart';
import '../models/system_specs.dart';
import 'bom_calculator.dart';

// ─── VALIDATION RESULT ───────────────────────────────────────────────────────

enum IssueSeverity { error, warning, info, ok }

class ValidationIssue {
  final IssueSeverity severity;
  final String category;
  final String message;
  final String? fix; // suggested fix

  const ValidationIssue({
    required this.severity,
    required this.category,
    required this.message,
    this.fix,
  });
}

class MissingCompanionItem {
  final String triggerItem;   // what was specified that requires this
  final String missingItem;   // what's missing
  final String reason;        // why it's needed per Versico
  final bool isCritical;      // true = spec violation, false = best practice

  const MissingCompanionItem({
    required this.triggerItem,
    required this.missingItem,
    required this.reason,
    this.isCritical = true,
  });
}

class ValidationResult {
  final List<ValidationIssue> issues;
  final List<MissingCompanionItem> missingItems;
  final int healthScore; // 0-100

  const ValidationResult({
    required this.issues,
    required this.missingItems,
    required this.healthScore,
  });

  int get errorCount => issues.where((i) => i.severity == IssueSeverity.error).length;
  int get warningCount => issues.where((i) => i.severity == IssueSeverity.warning).length;
  int get okCount => issues.where((i) => i.severity == IssueSeverity.ok).length;
}

// ─── ENGINE ──────────────────────────────────────────────────────────────────

class ValidationEngine {
  const ValidationEngine._();

  static ValidationResult validate({
    required ProjectInfo projectInfo,
    required RoofGeometry geometry,
    required SystemSpecs systemSpecs,
    required InsulationSystem insulation,
    required MembraneSystem membrane,
    required ParapetWalls parapet,
    required Penetrations penetrations,
    required MetalScope metalScope,
    required BomResult bom,
  }) {
    final issues = <ValidationIssue>[];
    final missing = <MissingCompanionItem>[];

    // ── 1. INPUT RANGE VALIDATION ──
    _validateRanges(issues, projectInfo, geometry, insulation, parapet, metalScope);

    // ── 2. CROSS-FIELD COMPATIBILITY ──
    _validateCompatibility(issues, systemSpecs, membrane, insulation, parapet, geometry);

    // ── 3. FASTENER VALIDATION ──
    _validateFasteners(issues, systemSpecs, insulation, membrane);

    // ── 4. VERSICO SPEC COMPLIANCE ──
    _validateVersicoSpecs(issues, missing, membrane, parapet, metalScope, penetrations,
        geometry, insulation, systemSpecs, bom, projectInfo);

    // ── 5. COMPLETENESS ──
    _validateCompleteness(issues, projectInfo, geometry, systemSpecs, insulation, membrane);

    // ── 6. BOM SANITY ──
    _validateBomSanity(issues, bom);

    // Calculate health score
    final errorPenalty = issues.where((i) => i.severity == IssueSeverity.error).length * 15;
    final warnPenalty = issues.where((i) => i.severity == IssueSeverity.warning).length * 5;
    final missingPenalty = missing.where((m) => m.isCritical).length * 10;
    final missingMinor = missing.where((m) => !m.isCritical).length * 3;
    final score = (100 - errorPenalty - warnPenalty - missingPenalty - missingMinor).clamp(0, 100);

    return ValidationResult(issues: issues, missingItems: missing, healthScore: score);
  }

  // ─── RANGE VALIDATION ──────────────────────────────────────────────────────

  static void _validateRanges(List<ValidationIssue> issues, ProjectInfo info,
      RoofGeometry geo, InsulationSystem insul, ParapetWalls parapet, MetalScope metal) {

    if (geo.totalArea > 0 && geo.totalArea < 100) {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Geometry', message: 'Roof area under 100 SF is unusually small.',
          fix: 'Verify area entry is in square feet.'));
    }
    if (geo.totalArea > 500000) {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Geometry', message: 'Roof area over 500,000 SF is unusually large.',
          fix: 'Verify area entry. Consider splitting into multiple buildings.'));
    }
    if (geo.buildingHeight > 200) {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Geometry', message: 'Building height over 200 ft is unusual for low-slope roofing.'));
    }
    if (info.wasteMaterial > 0.25) {
      issues.add(ValidationIssue(severity: IssueSeverity.warning,
          category: 'Waste', message: 'Material waste at ${(info.wasteMaterial * 100).toStringAsFixed(0)}% is high. Typical is 5-15%.',
          fix: 'Review waste percentage in settings.'));
    }
    if (info.wasteMaterial <= 0) {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Waste', message: 'Material waste at 0% - no waste allowance. This will undercount materials.',
          fix: 'Set waste to at least 5% for standard projects.'));
    }
    if (parapet.hasParapetWalls && parapet.parapetHeight > 60) {
      issues.add(ValidationIssue(severity: IssueSeverity.warning,
          category: 'Parapet', message: 'Parapet height ${parapet.parapetHeight.toStringAsFixed(0)}" (${(parapet.parapetHeight / 12).toStringAsFixed(1)} ft) is unusually tall.',
          fix: 'Verify height is entered in inches.'));
    }
    if (parapet.hasParapetWalls && parapet.parapetHeight > 0 && parapet.parapetHeight < 8) {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Parapet', message: 'Parapet under 8" does not meet Versico minimum flashing height.',
          fix: 'Versico requires minimum 8" flashing height above finished membrane.'));
    }
    if (insul.layer1.thickness > 8) {
      issues.add(ValidationIssue(severity: IssueSeverity.warning,
          category: 'Insulation', message: 'Layer 1 at ${insul.layer1.thickness}" is thick. Verify fastener availability.',
          fix: 'Consider splitting into two layers for easier fastening.'));
    }
  }

  // ─── CROSS-FIELD COMPATIBILITY ─────────────────────────────────────────────

  static void _validateCompatibility(List<ValidationIssue> issues, SystemSpecs specs,
      MembraneSystem membrane, InsulationSystem insul, ParapetWalls parapet, RoofGeometry geo) {

    // Rhinobond on concrete — requires special plates
    if (membrane.fieldAttachment == 'Rhinobond (Induction Welded)' && specs.deckType == 'Concrete') {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Compatibility', message: 'Rhinobond on concrete deck requires special fastener/plate combination.',
          fix: 'Verify Versico approves Rhinobond for concrete deck at this wind rating.'));
    }

    // Fully adhered requires bonding adhesive — check insulation surface compatibility
    if (membrane.fieldAttachment == 'Fully Adhered' && insul.layer1.attachmentMethod == 'Mechanically Attached'
        && !insul.hasCoverBoard) {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Compatibility',
          message: 'Fully adhered membrane over MA insulation without cover board may have adhesion issues.',
          fix: 'Consider adding a cover board for better adhesive surface, or switch membrane to MA.'));
    }

    // Parapet without perimeter edges
    if (parapet.hasParapetWalls && parapet.parapetTotalLF > 0 && geo.totalPerimeter > 0) {
      if (parapet.parapetTotalLF > geo.totalPerimeter * 1.1) {
        issues.add(const ValidationIssue(severity: IssueSeverity.warning,
            category: 'Geometry', message: 'Parapet LF exceeds roof perimeter by >10%.',
            fix: 'Verify parapet LF. Parapets typically follow the building perimeter.'));
      }
    }

    // Note: wind speed check is handled in _validateVersicoSpecs where ProjectInfo is available
  }

  // ─── FASTENER VALIDATION ───────────────────────────────────────────────────

  static void _validateFasteners(List<ValidationIssue> issues, SystemSpecs specs,
      InsulationSystem insul, MembraneSystem membrane) {

    if (specs.deckType.isEmpty) return;

    // Check full stack for membrane fastener
    final isMA = membrane.fieldAttachment == 'Mechanically Attached';
    final isRB = membrane.fieldAttachment == 'Rhinobond (Induction Welded)';

    if (isMA || isRB) {
      final stackIn = BomCalculator.stackThicknessPublic(insul, 3);
      final fastLen = BomCalculator.selectFastenerLenPublic(specs.deckType, stackIn);
      if (fastLen.contains('verify')) {
        issues.add(ValidationIssue(severity: IssueSeverity.error,
            category: 'Fasteners',
            message: 'Insulation stack ${stackIn.toStringAsFixed(1)}" exceeds standard fastener catalog for ${specs.deckType} deck.',
            fix: 'Reduce insulation thickness, split into more layers, or contact Versico for custom fastener options.'));
      }
    }

    // Layer-specific fastener checks
    if (insul.layer1.attachmentMethod == 'Mechanically Attached') {
      final l1Stack = BomCalculator.stackThicknessPublic(insul, 1);
      final l1Len = BomCalculator.selectFastenerLenPublic(specs.deckType, l1Stack);
      if (l1Len.contains('verify')) {
        issues.add(ValidationIssue(severity: IssueSeverity.error,
            category: 'Fasteners',
            message: 'Layer 1 insulation (${l1Stack.toStringAsFixed(1)}") exceeds fastener catalog.',
            fix: 'Reduce Layer 1 thickness or switch to adhered attachment.'));
      }
    }
  }

  // ─── VERSICO SPEC & COMPANION ITEMS ────────────────────────────────────────

  static void _validateVersicoSpecs(List<ValidationIssue> issues, List<MissingCompanionItem> missing,
      MembraneSystem membrane, ParapetWalls parapet, MetalScope metal,
      Penetrations pen, RoofGeometry geo, InsulationSystem insul,
      SystemSpecs specs, BomResult bom, ProjectInfo projectInfo) {

    final bomNames = bom.items.map((i) => i.name.toLowerCase()).toSet();
    final isMA = membrane.fieldAttachment == 'Mechanically Attached';

    // ── DRIP EDGE → requires cover strip/tape OR TPO-coated metal ──
    if (metal.dripEdgeLF > 0) {
      final hasCoverStrip = bomNames.any((n) =>
          n.contains('cover tape') || n.contains('cover strip') || n.contains('overlayment'));
      final isTPOCoated = metal.edgeMetalType.toLowerCase().contains('tpo');

      if (!isTPOCoated && !hasCoverStrip) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'Drip Edge',
          missingItem: 'VersiWeld TPO Reinforced Overlayment Strip (6" wide) OR TPO-Coated Drip Edge',
          reason: 'Versico requires either: (a) TPO-coated drip edge for direct hot-air welding, or (b) reinforced overlayment strip to seal non-coated metal flange to membrane. Cover strip must match membrane color.',
          isCritical: true,
        ));
      }
      if (!isTPOCoated) {
        missing.add(MissingCompanionItem(
          triggerItem: 'Drip Edge (${metal.edgeMetalType})',
          missingItem: 'Consider VersiTrim TPO-Coated Drip Edge',
          reason: 'TPO-coated metal (24GA with .035" TPO coating) allows direct hot-air welding, eliminating separate cover strips. Available in white, gray, tan, and custom colors.',
          isCritical: false,
        ));
      }
    }

    // ── COPING → requires cover strip at membrane-to-metal transition ──
    if (metal.copingLF > 0) {
      final hasCoverStrip = bomNames.any((n) =>
          n.contains('cover tape') || n.contains('cover strip') || n.contains('overlayment'));
      if (!hasCoverStrip) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'Coping Cap',
          missingItem: 'TPO Reinforced Overlayment Strip at Coping Transition',
          reason: 'Versico requires overlayment strip or hot-air weld at coping-to-membrane transition. For 25/30-year warranties, must use reinforced overlayment (not pressure-sensitive cover strip).',
          isCritical: true,
        ));
      }
    }

    // ── PIPE BOOTS → require clamping ring + cut-edge sealant ──
    if (pen.smallPipeCount + pen.largePipeCount > 0) {
      final hasClampRing = bomNames.any((n) => n.contains('clamp') || n.contains('pipe seal'));
      if (!hasClampRing) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'Pipe Boots',
          missingItem: 'Stainless Steel Clamping Rings',
          reason: 'Versico requires clamping ring at top of each pipe boot. Pre-molded boots include rings; field-fabricated require separate purchase.',
          isCritical: true,
        ));
      }
      // 25/30yr warranty requires pre-molded only
      if (projectInfo.warrantyYears >= 25) {
        issues.add(const ValidationIssue(severity: IssueSeverity.info,
            category: 'Versico Spec',
            message: '25/30-year warranty: pre-fabricated pipe boots are MANDATORY. Field-fabricated details not acceptable.'));
      }
    }

    // ── DRAINS → require water cut-off mastic under clamping ring ──
    if (geo.numberOfDrains > 0) {
      final hasMastic = bomNames.any((n) => n.contains('water cut-off') || n.contains('water block'));
      if (!hasMastic) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'Roof Drains',
          missingItem: 'Water Cut-Off Mastic (under drain clamping ring)',
          reason: 'Versico requires water cut-off mastic gasket between membrane and drain clamping ring.',
          isCritical: true,
        ));
      }
    }

    // ── MA PARAPET → requires RUSS + TPO primer + specific fastener spacing ──
    if (isMA && parapet.hasParapetWalls && parapet.parapetTotalLF > 0) {
      final hasRuss = bomNames.any((n) => n.contains('russ'));
      if (!hasRuss) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'MA Membrane + Parapet Walls',
          missingItem: 'RUSS Strip (6" wide) at Wall/Deck Transition',
          reason: 'Versico requires 6" wide Pressure-Sensitive RUSS at all wall-to-deck transitions for MA systems. Extends 1"-6" up wall. Fasteners at 12" O.C. (6" O.C. for >90 mph wind or >20yr warranty).',
          isCritical: true,
        ));
      }
      final hasPrimer = bomNames.any((n) => n.contains('tpo primer'));
      if (!hasPrimer) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'Parapet Wall Flashings',
          missingItem: 'TPO Primer',
          reason: 'Versico requires TPO primer before all pressure-sensitive products (RUSS, cover strips, corners, T-joints).',
          isCritical: true,
        ));
      }
      // Check RUSS fastener spacing for high wind/long warranty
      if (projectInfo.warrantyYears > 20 || _parseWindFromInfo(projectInfo) >= 90) {
        issues.add(ValidationIssue(severity: IssueSeverity.info,
            category: 'Versico Spec',
            message: 'RUSS fastener spacing: 6" O.C. required (warranty >${projectInfo.warrantyYears > 20 ? "20yr" : ""}${_parseWindFromInfo(projectInfo) >= 90 ? " wind ${_parseWindFromInfo(projectInfo).toInt()} mph" : ""}).',
            fix: 'Verify BOM RUSS fastener quantity uses 6" O.C. instead of standard 12" O.C.'));
      }
    }

    // ── CORNERS → require TPO primer ──
    if (geo.insideCorners + geo.outsideCorners > 0) {
      final hasPrimer = bomNames.any((n) => n.contains('tpo primer'));
      if (!hasPrimer) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'Inside/Outside Corners',
          missingItem: 'TPO Primer',
          reason: 'Versico requires TPO primer on membrane surface before installing pre-molded corners.',
          isCritical: true,
        ));
      }
    }

    // ── T-JOINTS → mandatory on 60/80-mil systems, require primer + lap sealant ──
    final hasTJoints = bomNames.any((n) => n.contains('t-joint') || n.contains('t joint'));
    if (hasTJoints) {
      final hasLapSealant = bomNames.any((n) => n.contains('lap sealant'));
      if (!hasLapSealant) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'T-Joint Covers',
          missingItem: 'Lap Sealant',
          reason: 'Versico requires lap sealant around perimeter of all T-joint covers, extending 2" in both directions from splice intersection.',
          isCritical: true,
        ));
      }
    }
    // T-joints mandatory for 60/80-mil
    if (membrane.thickness.contains('60') || membrane.thickness.contains('80')) {
      if (!hasTJoints && geo.totalArea > 0) {
        missing.add(MissingCompanionItem(
          triggerItem: '${membrane.thickness} TPO Membrane',
          missingItem: 'T-Joint Covers (mandatory for 60/80-mil)',
          reason: 'Versico requires T-joint covers at ALL field splice intersections on 60-mil and 80-mil TPO systems.',
          isCritical: true,
        ));
      }
    }

    // ── SCUPPERS → require EPDM flashing layers + primer ──
    if (pen.scupperCount > 0) {
      missing.add(const MissingCompanionItem(
        triggerItem: 'Scuppers',
        missingItem: 'VersiGard EPDM Pressure-Sensitive Flashing (6" + 12" wide) + EPDM Primer',
        reason: 'Versico scupper detail requires two layers: first 6" wide, second 12" wide with 3" overlaps. EPDM primer on both TPO and scupper surfaces. Single-ply sealant at top edge.',
        isCritical: false,
      ));
    }

    // ── RTU CURBS → require curb wrap corners ──
    if (pen.rtuDetails.isNotEmpty) {
      final hasCurbCorners = bomNames.any((n) => n.contains('curb wrap'));
      if (!hasCurbCorners) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'RTU/Equipment Curbs',
          missingItem: 'TPO Curb Wrap Corners (4 per curb)',
          reason: 'Versico requires pre-fabricated 60-mil reinforced curb wrap corners (6" base flange, 12" height) at each curb corner. 25/30-year warranty: pre-fabricated mandatory.',
          isCritical: true,
        ));
      }
    }

    // ── TERMINATION BAR → requires water cut-off mastic + single-ply sealant ──
    if (parapet.hasParapetWalls && parapet.terminationBarLF > 0) {
      final hasMastic = bomNames.any((n) => n.contains('water cut-off'));
      final hasSealant = bomNames.any((n) => n.contains('single-ply') || n.contains('single ply'));
      if (!hasMastic) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'Termination Bar',
          missingItem: 'Water Cut-Off Mastic',
          reason: 'Versico requires continuous bead of water cut-off mastic under termination bar for constant compression seal.',
          isCritical: true,
        ));
      }
      if (!hasSealant) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'Termination Bar',
          missingItem: 'Universal Single-Ply Sealant',
          reason: 'Versico requires single-ply sealant at top edge of termination bar. 1" gap at vertical panel joints.',
          isCritical: true,
        ));
      }
    }

    // ── CUT-EDGE SEALANT → always required with reinforced TPO ──
    final hasCutEdge = bomNames.any((n) => n.contains('cut edge') || n.contains('cut-edge'));
    if (!hasCutEdge && geo.totalArea > 0) {
      missing.add(const MissingCompanionItem(
        triggerItem: 'TPO Membrane Installation',
        missingItem: 'Cut-Edge Sealant',
        reason: 'Versico requires 1/8" diameter bead of cut-edge sealant on all cut edges of reinforced TPO membrane.',
        isCritical: true,
      ));
    }

    // ── SEAM TAPE → requires TPO primer underneath ──
    if (membrane.seamType == 'Tape') {
      final hasPrimer = bomNames.any((n) => n.contains('tpo primer'));
      if (!hasPrimer) {
        missing.add(const MissingCompanionItem(
          triggerItem: 'Seam Tape Installation',
          missingItem: 'TPO Primer',
          reason: 'Versico requires TPO primer on membrane surface before applying pressure-sensitive seam tape. Gap of 1/8" to 1/2" between tape edge and primer line.',
          isCritical: true,
        ));
      }
    }
  }

  // ─── COMPLETENESS ──────────────────────────────────────────────────────────

  static void _validateCompleteness(List<ValidationIssue> issues, ProjectInfo info,
      RoofGeometry geo, SystemSpecs specs, InsulationSystem insul, MembraneSystem membrane) {

    if (info.projectName.isEmpty) {
      issues.add(const ValidationIssue(severity: IssueSeverity.error,
          category: 'Project', message: 'Project name is required.'));
    }
    if (geo.totalArea <= 0) {
      issues.add(const ValidationIssue(severity: IssueSeverity.error,
          category: 'Geometry', message: 'Roof area is required to generate BOM.'));
    }
    if (specs.deckType.isEmpty) {
      issues.add(const ValidationIssue(severity: IssueSeverity.error,
          category: 'System', message: 'Deck type is required for fastener selection.'));
    }
    if (insul.layer1.thickness <= 0 && geo.totalArea > 0) {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Insulation', message: 'No insulation specified. Verify this is intentional.'));
    }
    if (info.warrantyYears == 0) {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Project', message: 'Warranty not set. Defaulting to 20-year fastening density.',
          fix: 'Set warranty duration in Project Info.'));
    }
    if (geo.windZones.perimeterZoneWidth <= 0 && geo.totalArea > 0) {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Geometry', message: 'Wind zone widths not set. Fastener estimates use total area only.',
          fix: 'Enter building height to auto-calculate zone widths.'));
    }
    if (geo.totalArea > 0 && membrane.fieldAttachment == 'Mechanically Attached') {
      issues.add(const ValidationIssue(severity: IssueSeverity.ok,
          category: 'Membrane', message: 'Mechanically attached TPO with Versico-spec fastening schedule.'));
    }
  }

  // ─── BOM SANITY ────────────────────────────────────────────────────────────

  static void _validateBomSanity(List<ValidationIssue> issues, BomResult bom) {
    if (!bom.isComplete) return;

    // Check for any zero-qty items that should have quantity
    for (final item in bom.items) {
      if (item.orderQty < 0) {
        issues.add(ValidationIssue(severity: IssueSeverity.error,
            category: 'BOM', message: '${item.name} has negative quantity (${item.orderQty}).'));
      }
    }

    // Check for reasonable total item count
    final activeCount = bom.activeItems.length;
    if (activeCount < 5 && bom.isComplete) {
      issues.add(ValidationIssue(severity: IssueSeverity.warning,
          category: 'BOM', message: 'Only $activeCount BOM items. A typical TPO project has 15-30+ items.',
          fix: 'Review inputs - some sections may be incomplete.'));
    }
  }

  // ─── HELPERS ───────────────────────────────────────────────────────────────

  static double _parseWindFromInfo(ProjectInfo info) {
    final ws = info.designWindSpeed;
    if (ws == null || ws.isEmpty) return 0;
    final m = RegExp(r'(\d+)').firstMatch(ws);
    return m != null ? double.tryParse(m.group(1)!) ?? 0 : 0;
  }
}
