/// lib/services/sub_instructions_builder.dart
///
/// Generates PDF pages for:
///   1. Subcontractor Installation Instructions — field-level detail
///   2. Enhanced Customer Scope of Work — detailed, compliant SOW

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/estimator_state.dart';
import '../models/section_models.dart';
import 'bom_calculator.dart';
import 'r_value_calculator.dart';

// ─── COLORS (match export_service.dart) ──────────────────────────────────────
const _kSlate900 = PdfColor(0.06, 0.09, 0.16);
const _kSlate700 = PdfColor(0.20, 0.25, 0.33);
const _kSlate500 = PdfColor(0.39, 0.45, 0.55);
const _kBlue     = PdfColor(0.12, 0.23, 0.37);
const _kBlueDark = PdfColor(0.07, 0.14, 0.25);

String _s(String v) => v
    .replaceAll('\u2014', '-').replaceAll('\u2013', '-')
    .replaceAll('\u2018', "'").replaceAll('\u2019', "'")
    .replaceAll('\u201C', '"').replaceAll('\u201D', '"')
    .replaceAll('\u00D7', 'x').replaceAll('\u00AE', '(R)')
    .replaceAll('\u00A0', ' ')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '');

// ─── SUBCONTRACTOR INSTRUCTIONS ──────────────────────────────────────────────

List<pw.Widget> buildSubInstructions(EstimatorState state, BomResult bom, {RValueResult? rValue}) {
  final info = state.projectInfo;
  final b = state.activeBuilding;
  final geo = b.roofGeometry;
  final specs = b.systemSpecs;
  final insul = b.insulationSystem;
  final membrane = b.membraneSystem;
  final parapet = b.parapetWalls;
  final metal = b.metalScope;
  final pen = b.penetrations;

  final isMA = membrane.fieldAttachment == 'Mechanically Attached';
  final isRB = membrane.fieldAttachment == 'Rhinobond (Induction Welded)';
  final isFA = membrane.fieldAttachment == 'Fully Adhered';
  final area = geo.totalArea;
  final zones = geo.windZones;
  final hasZones = zones.perimeterZoneWidth > 0;

  final widgets = <pw.Widget>[];

  // ── Title ──
  widgets.add(_heading('SUBCONTRACTOR INSTALLATION INSTRUCTIONS'));
  widgets.add(pw.SizedBox(height: 4));
  widgets.add(_body('Project: ${_s(info.projectName)}'));
  widgets.add(_body('Address: ${_s(info.projectAddress)}'));
  widgets.add(_body('Date: ${info.estimateDate.month}/${info.estimateDate.day}/${info.estimateDate.year}'));
  widgets.add(pw.Divider(color: _kSlate500, thickness: 0.5));
  widgets.add(pw.SizedBox(height: 8));

  // ── 1. SYSTEM OVERVIEW ──
  widgets.add(_section('1. SYSTEM OVERVIEW'));
  widgets.add(_body(
    'Project type: ${specs.projectType}. '
    'Deck type: ${specs.deckType}. '
    'Membrane: Versico ${membrane.thickness} ${membrane.membraneType}, ${membrane.color}, '
    '${membrane.fieldAttachment}. '
    'Warranty: ${info.warrantyYears}-year NDL. '
    '${info.designWindSpeed != null ? "Design wind speed: ${info.designWindSpeed}. " : ""}'
    'Total area: ${area.toStringAsFixed(0)} SF.'
  ));

  // ── 2. DECK PREPARATION ──
  widgets.add(_section('2. DECK PREPARATION'));
  if (specs.projectType == 'Tear-off & Replace') {
    widgets.add(_body(
      'Remove existing ${specs.existingRoofType} system (${specs.existingLayers} layer(s)) '
      'to structural ${specs.deckType.toLowerCase()} deck. Inspect for damage, deflection, '
      'or deterioration. All deck deficiencies must be reported and repaired before proceeding. '
      '${specs.existingRoofType == "BUR" || specs.existingRoofType == "Modified Bitumen" ? "Apply substrate primer to all bituminous residue areas before insulation installation." : ""}'
    ));
  } else if (specs.projectType == 'Recover') {
    widgets.add(_body(
      'Perform moisture survey of existing ${specs.existingRoofType} system. Remove and replace '
      'all wet or deteriorated insulation. Address blisters, ridges, and surface deficiencies.'
    ));
  } else {
    widgets.add(_body('Verify ${specs.deckType.toLowerCase()} deck is clean, dry, and free of debris.'));
  }
  if (specs.vaporRetarder != 'None') {
    widgets.add(_body(
      'Install ${specs.vaporRetarder.toLowerCase()} vapor retarder over entire deck area '
      '(${area.toStringAsFixed(0)} SF). '
      '${specs.vaporRetarder == "Self-Adhered" ? "Prime deck with vapor retarder primer before application." : ""}'
    ));
  }

  // ── 3. INSULATION ──
  widgets.add(_section('3. INSULATION INSTALLATION'));
  final l1 = insul.layer1;
  widgets.add(_body(
    'Layer 1: ${l1.type} ${l1.thickness}" - ${l1.attachmentMethod}. '
    '${l1.attachmentMethod == "Mechanically Attached" ? "Secure with 4 fasteners per 4\'x8\' board (0.125/SF). " : "Adhere per manufacturer coverage rates. "}'
    'Stagger all board joints. Do not align joints between layers.'
  ));
  if (l1.attachmentMethod == 'Mechanically Attached') {
    final l1Len = BomCalculator.selectFastenerLenPublic(specs.deckType,
        BomCalculator.stackThicknessPublic(insul, 1));
    widgets.add(_bullet('Fastener: ${BomCalculator.fastenerNamePublic(specs.deckType)} $l1Len with 3" insulation plate'));
    widgets.add(_bullet('Pattern: 4 per board (one in each quadrant, min 3" from edges)'));
  }

  if (insul.numberOfLayers == 2 && insul.layer2 != null) {
    final l2 = insul.layer2!;
    widgets.add(_body(
      'Layer 2: ${l2.type} ${l2.thickness}" - ${l2.attachmentMethod}. '
      'Offset joints min 6" from Layer 1 joints in both directions.'
    ));
    if (l2.attachmentMethod == 'Mechanically Attached') {
      final l2Len = BomCalculator.selectFastenerLenPublic(specs.deckType,
          BomCalculator.stackThicknessPublic(insul, 2));
      widgets.add(_bullet('Fastener: ${BomCalculator.fastenerNamePublic(specs.deckType)} $l2Len (penetrates L1+L2 to deck) with 3" plate'));
    }
  }

  if (insul.hasCoverBoard && insul.coverBoard != null) {
    final cb = insul.coverBoard!;
    widgets.add(_body(
      'Cover Board: ${cb.type} ${cb.thickness}" - ${cb.attachmentMethod}. '
      'Offset joints min 6" from insulation joints below.'
    ));
  }

  // ── 4. MEMBRANE ──
  widgets.add(_section('4. MEMBRANE INSTALLATION'));

  if (isMA) {
    widgets.add(_body(
      'MECHANICALLY ATTACHED: Install Versico ${membrane.thickness} ${membrane.membraneType} '
      '${membrane.rollWidth}x100\' field rolls. Fasten in seam with plates at specified density.'
    ));

    if (hasZones) {
      final windMph = _parseWind(info.designWindSpeed);
      final effW = _windAdj(info.warrantyYears, windMph);
      final d = _maDens(effW);
      widgets.add(_subsection('Fastening Density Schedule (${effW}-year${effW != info.warrantyYears ? ", wind-adjusted from ${info.warrantyYears}-year" : ""}):'));
      widgets.add(_bullet('Field Zone (${zones.fieldZoneArea.toStringAsFixed(0)} SF): ${d.$1.toStringAsFixed(2)}/SF'));
      widgets.add(_bullet('Perimeter Zone (${zones.perimeterZoneArea.toStringAsFixed(0)} SF): ${d.$2.toStringAsFixed(2)}/SF'));
      widgets.add(_bullet('Corner Zone (${zones.cornerZoneArea.toStringAsFixed(0)} SF): ${d.$3.toStringAsFixed(2)}/SF'));
      widgets.add(_bullet('Zone width: ${zones.perimeterZoneWidth.toStringAsFixed(1)}\''));
    }

    final stackIn = BomCalculator.stackThicknessPublic(insul, 3);
    final memLen = BomCalculator.selectFastenerLenPublic(specs.deckType, stackIn);
    widgets.add(_subsection('Membrane Fastener:'));
    widgets.add(_bullet('${BomCalculator.fastenerNamePublic(specs.deckType)} $memLen (through full insulation stack ${stackIn.toStringAsFixed(1)}" to deck)'));
    widgets.add(_bullet('3" seam stress plate at each fastener'));
    widgets.add(_bullet('All seams hot-air welded minimum 1.5" width'));
  } else if (isRB) {
    widgets.add(_body(
      'RHINOBOND (INDUCTION WELDED): Install Rhinobond induction weld plates at specified density. '
      'Lay membrane over plates and weld with induction equipment. No through-membrane fasteners.'
    ));
  } else if (isFA) {
    widgets.add(_body(
      'FULLY ADHERED: Apply bonding adhesive (Cav-Grip III) to both deck/insulation surface '
      'and membrane back at ~60 SF/gallon per finished surface. Roll membrane into adhesive '
      'while tacky. All field seams hot-air welded minimum 1.5" width.'
    ));
  }

  widgets.add(_body(
    'Seam method: ${membrane.seamType}. '
    '${membrane.seamType == "Hot Air Welded" ? "Weld at 15-20 ft/min, verify 1.5\" minimum weld width with probe test every 100 LF." : "Apply TPO primer before seam tape. Min 3\" tape width."} '
    'Apply cut-edge sealant to all reinforced membrane cut edges (1/8" bead).'
  ));

  // ── 5. PARAPET WALLS ──
  if (parapet.hasParapetWalls && parapet.parapetTotalLF > 0) {
    widgets.add(_section('5. PARAPET WALL FLASHINGS'));
    widgets.add(_body(
      'Flash all parapet walls: ${parapet.parapetTotalLF.toStringAsFixed(0)} LF, '
      '${parapet.parapetHeight.toStringAsFixed(0)}" height, ${parapet.wallType} construction.'
    ));

    if (isMA) {
      widgets.add(_bullet('Install RUSS strip (6" wide) at wall/deck transition, fasten at 12" O.C.'));
    }
    widgets.add(_bullet('Adhere TPO flashing to wall face using CAV-Grip 3v spray adhesive (40lb cylinder, ~400 SF/cyl)'));
    widgets.add(_bullet('Pair with UN-TACK cleaner/remover (8lb cylinder, 1:1 with CAV-Grip)'));
    widgets.add(_bullet('Extend flashing from field membrane (min 4" base lap, welded) up wall to termination'));
    widgets.add(_bullet('Apply TPO primer before any pressure-sensitive products at base transition'));
    widgets.add(_bullet('Terminate with ${parapet.terminationType.toLowerCase()} at ${parapet.parapetHeight.toStringAsFixed(0)}" height'));
    widgets.add(_bullet('Apply water cut-off mastic under termination bar (continuous bead)'));
    widgets.add(_bullet('Apply single-ply sealant at top edge of termination bar'));
    widgets.add(_bullet('Termination bar fasteners: ${_termFastenerDesc(parapet)} at 8" O.C.'));
  }

  // ── 6. PENETRATIONS ──
  widgets.add(_section('${parapet.hasParapetWalls ? "6" : "5"}. PENETRATION FLASHINGS'));
  if (pen.rtuDetails.isNotEmpty) {
    widgets.add(_body('RTU/Equipment Curbs: ${pen.rtuDetails.length} units, ${pen.rtuTotalLF.toStringAsFixed(0)} LF total curb perimeter.'));
    widgets.add(_bullet('Flash with 6\'x100\' TPO rolls. 4 curb wrap corners per unit.'));
    widgets.add(_bullet('Weld membrane to curb flashing min 1.5". Cut-edge sealant on all cuts.'));
  }
  if (pen.smallPipeCount > 0) widgets.add(_bullet('Small pipe boots (1-4"): ${pen.smallPipeCount} - use pre-molded TPO pipe boots with clamping ring'));
  if (pen.largePipeCount > 0) widgets.add(_bullet('Large pipe boots (4-12"): ${pen.largePipeCount} - use pre-molded TPO pipe boots with clamping ring'));
  if (pen.pitchPanCount > 0) widgets.add(_bullet('Sealant pockets: ${pen.pitchPanCount} - use Versico TPO molded sealant pockets'));
  if (pen.skylightCount > 0) widgets.add(_bullet('Skylights: ${pen.skylightCount} - flash per Versico curb detail'));
  if (pen.scupperCount > 0) widgets.add(_bullet('Scuppers: ${pen.scupperCount} - flash with EPDM pressure-sensitive flashing per Versico detail'));
  if (geo.numberOfDrains > 0) widgets.add(_bullet('Roof drains: ${geo.numberOfDrains} - flash with TPO, water cut-off mastic under clamping ring'));

  // ── 7. METAL ──
  final secNum = parapet.hasParapetWalls ? 7 : 6;
  widgets.add(_section('$secNum. SHEET METAL & EDGE DETAILS'));
  if (metal.copingLF > 0) widgets.add(_bullet('Coping: ${metal.copingLF.toStringAsFixed(0)} LF, ${metal.copingWidth} width, 10\' sections'));
  if (metal.wallFlashingLF > 0) widgets.add(_bullet('Wall flashing: ${metal.wallFlashingLF.toStringAsFixed(0)} LF, 10\' sections'));
  if (metal.dripEdgeLF > 0) widgets.add(_bullet('Drip edge (${metal.edgeMetalType}): ${metal.dripEdgeLF.toStringAsFixed(0)} LF'));
  if (metal.gutterLF > 0) widgets.add(_bullet('Gutter (${metal.gutterSize}): ${metal.gutterLF.toStringAsFixed(0)} LF with ${metal.downspoutCount} downspout(s)'));
  widgets.add(_bullet('Edge metal fasteners: ${BomCalculator.fastenerNamePublic(specs.deckType)} at 12" O.C.'));

  // ── 8. ACCESSORIES ──
  widgets.add(_section('${secNum + 1}. ACCESSORIES & SEALANTS'));
  widgets.add(_bullet('Inside corners: ${geo.insideCorners} prefab TPO (apply TPO primer first)'));
  widgets.add(_bullet('Outside corners: ${geo.outsideCorners} prefab TPO (apply TPO primer first)'));
  widgets.add(_bullet('T-joint covers at all 3-way membrane intersections (apply TPO primer first)'));
  widgets.add(_bullet('Lap sealant at all T-joint edges, tape overlaps, and flashing edges'));
  widgets.add(_bullet('Cut-edge sealant on all cut edges of reinforced TPO (1/8" continuous bead)'));
  widgets.add(_bullet('Water block sealant at all T-joints, laps, and penetration details'));
  if (pen.rtuDetails.isNotEmpty) {
    widgets.add(_bullet('Walkway pads: install heat-weldable TPO walkway at all HVAC access paths'));
  }

  // ── 9. QUALITY ──
  widgets.add(_section('${secNum + 2}. QUALITY & COMPLIANCE'));
  widgets.add(_bullet('All work per Versico VersiWeld TPO Installation Guide and Detail Manual'));
  widgets.add(_bullet('Probe-test all welds every 100 LF minimum'));
  widgets.add(_bullet('No exposed fasteners through finished membrane surface (except termination bars)'));
  widgets.add(_bullet('Protect all completed work from traffic, debris, and weather'));
  widgets.add(_bullet('Manufacturer inspection required prior to warranty issuance'));
  if (rValue != null && rValue.totalRValue > 0) {
    widgets.add(_bullet('Thermal compliance: R-${rValue.totalRValue.toStringAsFixed(1)} achieved '
        '(code requires R-${info.requiredRValue?.toStringAsFixed(0) ?? "N/A"})'));
  }

  return widgets;
}

// ─── ENHANCED CUSTOMER SCOPE OF WORK ─────────────────────────────────────────

List<pw.Widget> buildEnhancedScope(EstimatorState state, BomResult bom, {RValueResult? rValue}) {
  final info = state.projectInfo;
  final b = state.activeBuilding;
  final geo = b.roofGeometry;
  final specs = b.systemSpecs;
  final insul = b.insulationSystem;
  final membrane = b.membraneSystem;
  final parapet = b.parapetWalls;
  final metal = b.metalScope;
  final pen = b.penetrations;
  final area = geo.totalArea;

  final widgets = <pw.Widget>[];

  widgets.add(_heading('SCOPE OF WORK'));
  widgets.add(pw.SizedBox(height: 2));
  widgets.add(_body('${_s(info.projectName)} - ${_s(info.projectAddress)}'));
  widgets.add(pw.Divider(color: _kSlate500, thickness: 0.5));
  widgets.add(pw.SizedBox(height: 6));

  // 1. GENERAL
  widgets.add(_section('1. GENERAL CONDITIONS'));
  widgets.add(_body(
    'Contractor shall furnish all labor, materials, equipment, transportation, and supervision '
    'necessary to complete the roofing system as described herein. Work area is approximately '
    '${area.toStringAsFixed(0)} square feet (${(area / 100).toStringAsFixed(1)} squares)'
    '${geo.totalPerimeter > 0 ? " with ${geo.totalPerimeter.toStringAsFixed(0)} linear feet of perimeter" : ""}. '
    'All work shall conform to Versico manufacturer installation specifications, applicable building codes, '
    'and OSHA safety requirements. Contractor is responsible for maintaining watertight conditions '
    'at the end of each work day.'
  ));

  // 2. EXISTING ROOF
  if (specs.projectType == 'Tear-off & Replace') {
    widgets.add(_section('2. TEAR-OFF & DISPOSAL'));
    widgets.add(_body(
      'Remove and legally dispose of existing ${specs.existingRoofType} roofing system '
      '(${specs.existingLayers} layer(s)) down to the structural ${specs.deckType.toLowerCase()} deck. '
      'Inspect deck for damage, deterioration, deflection, or moisture damage. Report all findings '
      'to building owner in writing. Replace damaged deck sections as directed (additional cost if required). '
      'Protect all rooftop mechanical equipment, electrical conduits, plumbing vents, and adjacent surfaces '
      'during removal operations.'
    ));
  } else if (specs.projectType == 'Recover') {
    widgets.add(_section('2. EXISTING ROOF PREPARATION'));
    widgets.add(_body(
      'Prepare existing ${specs.existingRoofType} roof surface for recover. Conduct infrared or '
      'nuclear moisture survey to identify wet insulation areas. Remove and replace all wet or '
      'deteriorated insulation. Repair all blisters, ridges, open seams, and surface deficiencies. '
      'Verify existing roof can structurally support additional recover system weight.'
    ));
  }

  // 3. INSULATION
  widgets.add(_section('${specs.projectType != "New Construction" ? "3" : "2"}. INSULATION SYSTEM'));
  final l1 = insul.layer1;
  var insulDesc = 'Install ${l1.type} rigid roof insulation, ${l1.thickness}" thick (Layer 1), '
      '${l1.attachmentMethod.toLowerCase()} to ${specs.deckType.toLowerCase()} deck.';
  if (insul.numberOfLayers == 2 && insul.layer2 != null) {
    final l2 = insul.layer2!;
    insulDesc += ' Install ${l2.type} ${l2.thickness}" (Layer 2) over Layer 1, '
        '${l2.attachmentMethod.toLowerCase()}. All board joints offset minimum 6" between layers.';
  }
  if (insul.hasCoverBoard && insul.coverBoard != null) {
    final cb = insul.coverBoard!;
    insulDesc += ' Install ${cb.type} ${cb.thickness}" cover board, ${cb.attachmentMethod.toLowerCase()}.';
  }
  if (specs.vaporRetarder != 'None') {
    insulDesc += ' ${specs.vaporRetarder} vapor retarder installed between deck and insulation.';
  }
  if (rValue != null && rValue.totalRValue > 0) {
    insulDesc += ' System achieves R-${rValue.totalRValue.toStringAsFixed(1)} thermal value.';
  }
  widgets.add(_body(insulDesc));

  // 4. MEMBRANE
  final memNum = specs.projectType != 'New Construction' ? 4 : 3;
  widgets.add(_section('$memNum. ROOFING MEMBRANE'));
  widgets.add(_body(
    'Install Versico VersiWeld ${membrane.thickness} ${membrane.membraneType} single-ply roofing membrane, '
    '${membrane.color} color, ${membrane.fieldAttachment.toLowerCase()}. '
    '${membrane.fieldAttachment == "Mechanically Attached" ? "Membrane secured with concealed fasteners and stress plates in the seam overlap per Versico warranty fastening schedule." : ""}'
    '${membrane.fieldAttachment == "Fully Adhered" ? "Membrane fully adhered to substrate with Versico-approved bonding adhesive." : ""}'
    '${membrane.fieldAttachment == "Rhinobond (Induction Welded)" ? "Membrane inductively welded to Rhinobond plates - no through-membrane fasteners." : ""} '
    'All field seams ${membrane.seamType == "Hot Air Welded" ? "hot-air welded with minimum 1.5\" weld width" : "sealed with factory-applied seam tape"}. '
    'Cut-edge sealant applied to all exposed membrane edges.'
  ));

  // 5. FLASHINGS
  widgets.add(_section('${memNum + 1}. FLASHINGS & DETAILS'));
  if (parapet.hasParapetWalls && parapet.parapetTotalLF > 0) {
    widgets.add(_body(
      'Parapet wall flashings: Install TPO membrane wall flashings at all ${parapet.wallType.toLowerCase()} '
      'parapet walls (${parapet.parapetTotalLF.toStringAsFixed(0)} LF, ${parapet.parapetHeight.toStringAsFixed(0)}" height). '
      'Flashings adhered with spray contact adhesive, terminated with ${parapet.terminationType.toLowerCase()} '
      'and sealed with water cut-off mastic and single-ply sealant at termination.'
    ));
  }
  final details = <String>[];
  if (pen.rtuDetails.isNotEmpty) details.add('${pen.rtuDetails.length} RTU/equipment curb(s) flashed with TPO curb wrap system');
  if (pen.smallPipeCount > 0) details.add('${pen.smallPipeCount} small pipe penetration(s) (1-4") with pre-molded boots');
  if (pen.largePipeCount > 0) details.add('${pen.largePipeCount} large pipe penetration(s) (4-12") with pre-molded boots');
  if (pen.pitchPanCount > 0) details.add('${pen.pitchPanCount} irregular penetration(s) with molded sealant pockets');
  if (pen.skylightCount > 0) details.add('${pen.skylightCount} skylight curb(s) flashed per Versico detail');
  if (pen.scupperCount > 0) details.add('${pen.scupperCount} scupper(s) flashed per Versico detail');
  if (geo.numberOfDrains > 0) details.add('${geo.numberOfDrains} roof drain(s) flashed with TPO');
  if (pen.expansionJointLF > 0) details.add('${pen.expansionJointLF.toStringAsFixed(0)} LF expansion joint cover');
  if (details.isNotEmpty) {
    widgets.add(_body('Penetration and detail flashings include: ${details.join("; ")}. '
        'All flashing work per Versico standard detail drawings and installation guide.'));
  }

  // 6. SHEET METAL
  if (metal.copingLF > 0 || metal.edgeMetalLF > 0 || metal.gutterLF > 0) {
    widgets.add(_section('${memNum + 2}. SHEET METAL'));
    final metalParts = <String>[];
    if (metal.copingLF > 0) metalParts.add('${metal.copingLF.toStringAsFixed(0)} LF ${metal.copingWidth} coping');
    if (metal.wallFlashingLF > 0) metalParts.add('${metal.wallFlashingLF.toStringAsFixed(0)} LF wall flashing');
    if (metal.dripEdgeLF > 0) metalParts.add('${metal.dripEdgeLF.toStringAsFixed(0)} LF ${metal.edgeMetalType} drip edge');
    if (metal.gutterLF > 0) metalParts.add('${metal.gutterLF.toStringAsFixed(0)} LF ${metal.gutterSize} gutter with ${metal.downspoutCount} downspout(s)');
    widgets.add(_body('Install: ${metalParts.join("; ")}. All sheet metal factory-finished or primed, '
        'installed per SMACNA standards with appropriate fasteners.'));
  }

  // 7. WARRANTY
  widgets.add(_section('${memNum + 3}. WARRANTY'));
  widgets.add(_body(
    'Upon satisfactory completion, final inspection, and Versico manufacturer approval, contractor '
    'shall deliver: (1) Versico ${info.warrantyYears}-Year No Dollar Limit (NDL) manufacturer roofing '
    'system warranty covering all materials and labor for defects in the roofing system'
    '${info.designWindSpeed != null ? " including wind speeds up to ${info.designWindSpeed}" : ""}; '
    '(2) Contractor minimum 2-year workmanship warranty covering defects in installation, materials, '
    'and labor. Warranty commencement date is the date of Versico final inspection.'
  ));

  // 8. EXCLUSIONS
  widgets.add(_section('${memNum + 4}. EXCLUSIONS'));
  widgets.add(_body(
    'Unless specifically noted above, the following are excluded from this scope: '
    'structural deck repairs or replacement; interior work of any kind; electrical, mechanical, '
    'or plumbing modifications; painting or caulking of building exterior; metal counter flashings '
    '(by others unless noted); wood blocking or nailers (by others unless noted); permits and '
    'engineering (by owner unless noted); hazardous material abatement.'
  ));

  return widgets;
}

// ─── PDF WIDGET HELPERS ──────────────────────────────────────────────────────

pw.Widget _heading(String text) => pw.Text(_s(text),
    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _kBlueDark));

pw.Widget _section(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
    child: pw.Text(_s(text),
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
            color: _kBlue, letterSpacing: 0.5)));

pw.Widget _subsection(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
    child: pw.Text(_s(text),
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _kSlate700)));

pw.Widget _body(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Text(_s(text),
        style: pw.TextStyle(fontSize: 9, color: _kSlate700, lineSpacing: 1.3)));

pw.Widget _bullet(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(left: 12, bottom: 2),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('- ', style: pw.TextStyle(fontSize: 9, color: _kSlate500)),
      pw.Expanded(child: pw.Text(_s(text),
          style: pw.TextStyle(fontSize: 9, color: _kSlate700, lineSpacing: 1.2))),
    ]));

String _termFastenerDesc(ParapetWalls p) {
  switch (p.wallType) {
    case 'Wood': return 'Wood screws 1-5/8"';
    case 'Metal Stud': return 'TEK screws (self-drilling) 1"';
    default: return 'Masonry anchors 1-1/4"';
  }
}

double _parseWind(String? ws) {
  if (ws == null) return 0;
  final m = RegExp(r'(\d+)').firstMatch(ws);
  return m != null ? double.tryParse(m.group(1)!) ?? 0 : 0;
}

int _windAdj(int wy, double mph) {
  const t = [10, 15, 20, 25, 30];
  var i = t.indexOf(wy);
  if (i < 0) i = 2;
  if (mph >= 130) i = (i + 2).clamp(0, t.length - 1);
  else if (mph >= 90) i = (i + 1).clamp(0, t.length - 1);
  return t[i];
}

(double, double, double) _maDens(int wy) {
  switch (wy) {
    case 10: return (0.20, 0.40, 0.60);
    case 15: return (0.25, 0.50, 0.75);
    case 20: return (0.50, 1.00, 1.49);
    case 25: return (0.75, 1.49, 2.00);
    case 30: return (1.00, 2.00, 2.99);
    default: return (0.50, 1.00, 1.49);
  }
}
