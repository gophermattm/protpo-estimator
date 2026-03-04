/// lib/widgets/left_panel.dart
///
/// Left input panel — all sections wired to Riverpod providers.
///
/// Wiring strategy:
///   - TextEditingControllers are local (Flutter requires them).
///   - Provider is the source of truth for all data.
///   - initState() seeds controllers from current provider state via postFrameCallback.
///   - ref.listen(activeBuildingIndexProvider) detects building tab switches and
///     calls _syncFromState() to reload every controller from the newly active building.
///   - Every onChange / onChanged writes back to the provider via notifier.
///   - Dropdown values are local Strings seeded from provider, written back on change.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/zone_width_lookup.dart';
import 'ui_polish.dart';
import '../models/roof_geometry.dart';
import '../models/insulation_system.dart';
import '../models/section_models.dart';
import '../providers/estimator_providers.dart';
import '../services/zip_lookup.dart';

// ─── EDGE LABELS ─────────────────────────────────────────────────────────────

List<String> _edgeLabelsFor(String shapeType) =>
    kShapeTemplates[shapeType]?.edgeLabels ??
    List.generate(kEdgeCountByShape[shapeType] ?? 4, (i) => "Edge ${i+1} (ft)");

// ─── UI-ONLY SHAPE ENTRY ─────────────────────────────────────────────────────
// Holds TextEditingControllers for one shape row. Mirrors RoofShape model.

class _ShapeEntry {
  final String type;
  final String operation;
  final List<TextEditingController> edgeControllers;
  final List<String> edgeTypes;

  _ShapeEntry({
    required this.type,
    required this.operation,
    required this.edgeControllers,
    List<String>? edgeTypes,
  }) : edgeTypes = edgeTypes ??
            (kShapeDefaultEdgeTypes[type] ??
                List.filled(kEdgeCountByShape[type] ?? 4, kDefaultEdgeType));

  factory _ShapeEntry.fromModel(RoofShape s) {
    final count = kEdgeCountByShape[s.shapeType] ?? 4;
    return _ShapeEntry(
      type: s.shapeType,
      operation: s.operation,
      edgeControllers: List.generate(count, (i) {
        final c = TextEditingController();
        if (i < s.edgeLengths.length && s.edgeLengths[i] > 0) {
          final v = s.edgeLengths[i];
          c.text = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
        }
        return c;
      }),
      edgeTypes: s.edgeTypes.isNotEmpty
          ? List<String>.from(s.edgeTypes)
          : List<String>.from(kShapeDefaultEdgeTypes[s.shapeType] ??
              List.filled(count, kDefaultEdgeType)),
    );
  }

  factory _ShapeEntry.blank({String type = 'Rectangle', String operation = 'Add'}) {
    final count = kEdgeCountByShape[type] ?? 4;
    return _ShapeEntry(
      type: type, operation: operation,
      edgeControllers: List.generate(count, (_) => TextEditingController()),
      edgeTypes: List<String>.from(
          kShapeDefaultEdgeTypes[type] ?? List.filled(count, kDefaultEdgeType)),
    );
  }

  List<double> get edgeLengths =>
      edgeControllers.map((c) => double.tryParse(c.text) ?? 0.0).toList();

  double get area {
    final e = edgeLengths;
    if (e.length < 4 || e.every((v) => v <= 0)) return 0;
    const _t = <String,List<int>>{
      'Rectangle': [1,1,1,1], 'Square': [1,1,1,1],
      'L-Shape':  [1,1,-1,1,1],
      'T-Shape':  [1,1,-1,1,1,-1,1],
      'U-Shape':  [1,1,1,-1,-1,1,1],
    };
    final turns = _t[type] ?? List.filled(e.length, 1);
    const ddx = [1.0, 0.0, -1.0, 0.0];
    const ddy = [0.0, -1.0, 0.0, 1.0];
    final xs = <double>[0]; final ys = <double>[0];
    var px = 0.0, py = 0.0, dir = 0;
    for (int i = 0; i < e.length; i++) {
      px += ddx[dir % 4] * e[i]; py += ddy[dir % 4] * e[i];
      xs.add(px); ys.add(py);
      if (i < turns.length) dir = (dir + (turns[i] == 1 ? 1 : 3)) % 4;
    }
    xs.removeLast(); ys.removeLast();
    double a = 0; final n = xs.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      a += xs[i] * ys[j] - xs[j] * ys[i];
    }
    return (a / 2).abs();
  }

  double get perimeter => edgeLengths.fold(0.0, (s, v) => s + v);

  _ShapeEntry withEdgeType(int index, String edgeType) {
    final updated = List<String>.from(edgeTypes);
    if (index >= 0 && index < updated.length) updated[index] = edgeType;
    return _ShapeEntry(type: type, operation: operation,
        edgeControllers: edgeControllers, edgeTypes: updated);
  }

  void dispose() { for (final c in edgeControllers) c.dispose(); }
}

// ─── LEFT PANEL ──────────────────────────────────────────────────────────────

class LeftPanel extends ConsumerStatefulWidget {
  const LeftPanel({super.key});
  @override
  ConsumerState<LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends ConsumerState<LeftPanel> {
  int _expandedSection = 0;

  // ── Project Info ─────────────────────────────────────────────────────────────
  final _cProjectName    = TextEditingController();
  final _cProjectAddress = TextEditingController();
  final _cZipCode        = TextEditingController();
  final _cCustomerName   = TextEditingController();
  final _cEstimatorName  = TextEditingController();
  String _warrantyYears  = '20';
  String _estimateDate   = '';
  String? _climateZone, _windSpeed, _requiredRValue;
  bool _zipLoading = false;

  // ── Geometry ─────────────────────────────────────────────────────────────────
  List<_ShapeEntry> _shapes = [];
  final _cBuildingHeight  = TextEditingController();
  String _roofSlope       = 'Flat';
  final _cDrainCount      = TextEditingController();
  final _cPerimeterWidth  = TextEditingController();
  final _cCornerCount     = TextEditingController(text: '4');
  bool _zonesOverridden   = false;

  // ── System Specs ─────────────────────────────────────────────────────────────
  String _projectType      = 'New Construction';
  String _deckType         = 'Metal';
  String _vaporRetarder    = 'None';
  String _existingRoofType = 'BUR';
  final _cExistingLayers   = TextEditingController(text: '1');

  // ── Insulation ───────────────────────────────────────────────────────────────
  String _insLayers        = '1';
  String _l1Type           = 'Polyiso';
  String _l1Thickness      = '2.5';
  String _l1Attachment     = 'Mechanically Attached';
  String _l2Type           = 'Polyiso';
  String _l2Thickness      = '2.0';
  String _l2Attachment     = 'Adhered';
  bool   _hasTapered       = false;
  String _taperSlope       = '1/4:12';
  String _taperMinThick    = '1.0';
  final _cTaperBoard       = TextEditingController();
  final _cTaperArea        = TextEditingController();
  bool   _hasCoverBoard    = false;
  String _cbType           = 'HD Polyiso';
  String _cbThickness      = '0.5';
  String _cbAttachment     = 'Adhered';

  // ── Membrane ─────────────────────────────────────────────────────────────────
  String _memType       = 'TPO';
  String _memThickness  = '60 mil';
  String _memColor      = 'White';
  String _fieldAttach   = 'Mechanically Attached';
  String _rollWidth     = "10'";
  String _seamType      = 'Hot Air Welded';
  String _perimRollWidth = "6'";

  // ── Penetrations ─────────────────────────────────────────────────────────────
  final _cWallHeight    = TextEditingController(text: '12');
  final _cWallLF        = TextEditingController();
  final _cRtuLF         = TextEditingController();
  final _cDrainCountPen = TextEditingController();
  String _drainType     = 'Standard';
  final _cSmallPipes    = TextEditingController();
  final _cLargePipes    = TextEditingController();
  final _cSkylights     = TextEditingController();
  final _cScuppers      = TextEditingController();
  final _cExpJointLF    = TextEditingController();
  final _cPitchPans     = TextEditingController();

  // ── Parapet ──────────────────────────────────────────────────────────────────
  bool   _hasParapet     = false;
  final _cParapetHeight  = TextEditingController();
  final _cParapetLF      = TextEditingController();
  final _cTermBarLF      = TextEditingController();
  String _parapetWallType = 'Concrete Block';
  String _terminationType = 'Termination Bar';
  bool   _termBarOverride = false;

  // ── Metal Scope ──────────────────────────────────────────────────────────────
  String _copingWidth  = '12"';
  final _cCopingLF     = TextEditingController();
  String _edgeMetalType = 'ES-1';
  final _cEdgeMetalLF  = TextEditingController();
  String _gutterSize   = '6"';
  final _cGutterLF     = TextEditingController();
  final _cDownspouts   = TextEditingController();

  // ── Waste ────────────────────────────────────────────────────────────────────
  final _cWasteMaterial  = TextEditingController(text: '10');
  final _cWasteMetal     = TextEditingController(text: '5');
  final _cWasteAccessory = TextEditingController(text: '5');

  // ─── Derived values ───────────────────────────────────────────────────────────
  double get _totalArea {
    double t = 0;
    for (final s in _shapes) t += s.operation == 'Subtract' ? -s.area : s.area;
    return t.clamp(0.0, double.infinity);
  }
  double get _totalPerimeter => _shapes
      .where((s) => s.operation == 'Add')
      .fold(0.0, (sum, s) => sum + s.perimeter);
  double get _perimWidth => double.tryParse(_cPerimeterWidth.text) ?? 0;
  int    get _cornerCnt  => int.tryParse(_cCornerCount.text) ?? 4;
  double get _cornerArea => _perimWidth > 0 ? _cornerCnt * _perimWidth * _perimWidth : 0;
  double get _perimArea  => _perimWidth > 0
      ? (_totalPerimeter * _perimWidth - _cornerCnt * _perimWidth * _perimWidth).clamp(0, 1e9) : 0;
  double get _fieldArea  => (_totalArea - _cornerArea - _perimArea).clamp(0.0, double.infinity);

  double get _parapetArea {
    final h  = double.tryParse(_cParapetHeight.text) ?? 0;
    final lf = double.tryParse(_cParapetLF.text) ?? 0;
    return (h / 12) * lf;
  }
  double get _parapetLFval => double.tryParse(_cParapetLF.text) ?? 0;
  double get _termBarLF    => _termBarOverride
      ? (double.tryParse(_cTermBarLF.text) ?? _parapetLFval)
      : _parapetLFval;

  double get _wMat   => (double.tryParse(_cWasteMaterial.text)  ?? 10) / 100;
  double get _wMetal => (double.tryParse(_cWasteMetal.text)     ??  5) / 100;

  String get _anchorType {
    switch (_parapetWallType) {
      case 'Wood':       return 'Wood Nailers';
      case 'Metal Stud': return 'Metal Anchors';
      default:           return 'Concrete Anchors';
    }
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _estimateDate = DateFormat('MM/dd/yyyy').format(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncFromState();
    });
  }

  @override
  void dispose() {
    for (final c in [
      _cProjectName, _cProjectAddress, _cZipCode, _cCustomerName, _cEstimatorName,
      _cBuildingHeight, _cDrainCount, _cPerimeterWidth, _cCornerCount, _cExistingLayers,
      _cTaperBoard, _cTaperArea,
      _cWallHeight, _cWallLF, _cRtuLF, _cDrainCountPen,
      _cSmallPipes, _cLargePipes, _cSkylights, _cScuppers, _cExpJointLF, _cPitchPans,
      _cParapetHeight, _cParapetLF, _cTermBarLF,
      _cCopingLF, _cEdgeMetalLF, _cGutterLF, _cDownspouts,
      _cWasteMaterial, _cWasteMetal, _cWasteAccessory,
    ]) c.dispose();
    for (final s in _shapes) s.dispose();
    super.dispose();
  }

  // ─── Sync from provider → controllers ────────────────────────────────────────
  void _syncFromState() {
    final state = ref.read(estimatorProvider);
    final info  = state.projectInfo;
    final bld   = state.activeBuilding;
    final geo   = bld.roofGeometry;
    final specs = bld.systemSpecs;
    final ins   = bld.insulationSystem;
    final mem   = bld.membraneSystem;
    final pen   = bld.penetrations;
    final par   = bld.parapetWalls;
    final met   = bld.metalScope;

    // ── Project Info ────────────────────────────────────────────────
    _set(_cProjectName,    info.projectName);
    _set(_cProjectAddress, info.projectAddress);
    _set(_cZipCode,        info.zipCode);
    _set(_cCustomerName,   info.customerName);
    _set(_cEstimatorName,  info.estimatorName);
    _set(_cWasteMaterial,  _pct(info.wasteMaterial));
    _set(_cWasteMetal,     _pct(info.wasteMetal));
    _set(_cWasteAccessory, _pct(info.wasteAccessory));

    // ── Geometry ────────────────────────────────────────────────────
    _set(_cBuildingHeight, _nz(geo.buildingHeight));
    _set(_cDrainCount,     geo.numberOfDrains > 0 ? '${geo.numberOfDrains}' : '');
    _set(_cPerimeterWidth, _nz(geo.windZones.perimeterZoneWidth));
    int totalCorners = 0;
    for (final sh in geo.shapes) { totalCorners += kEdgeCountByShape[sh.shapeType] ?? 4; }
    if (totalCorners == 0) totalCorners = 4;
    _set(_cCornerCount, '$totalCorners');

    // Rebuild shape entries
    for (final s in _shapes) s.dispose();
    _shapes = geo.shapes.isEmpty
        ? [_ShapeEntry.blank()]
        : geo.shapes.map(_ShapeEntry.fromModel).toList();

    // ── System Specs ────────────────────────────────────────────────
    _set(_cExistingLayers, specs.existingLayers > 0 ? '${specs.existingLayers}' : '1');

    // ── Insulation ──────────────────────────────────────────────────
    _set(_cTaperBoard, ins.tapered?.boardType ?? '');
    _set(_cTaperArea,  ins.tapered?.systemArea != null && ins.tapered!.systemArea > 0
        ? ins.tapered!.systemArea.toStringAsFixed(0) : '');

    // ── Penetrations ────────────────────────────────────────────────
    _set(_cRtuLF,        _nz(pen.rtuTotalLF));
    _set(_cSmallPipes,   pen.smallPipeCount > 0 ? '${pen.smallPipeCount}' : '');
    _set(_cLargePipes,   pen.largePipeCount > 0 ? '${pen.largePipeCount}' : '');
    _set(_cSkylights,    pen.skylightCount  > 0 ? '${pen.skylightCount}'  : '');
    _set(_cScuppers,     pen.scupperCount   > 0 ? '${pen.scupperCount}'   : '');
    _set(_cExpJointLF,   _nz(pen.expansionJointLF));
    _set(_cPitchPans,    pen.pitchPanCount  > 0 ? '${pen.pitchPanCount}'  : '');

    // ── Parapet ─────────────────────────────────────────────────────
    _set(_cParapetHeight, _nz(par.parapetHeight));
    _set(_cParapetLF,     _nz(par.parapetTotalLF));
    final override = par.terminationBarLFOverride;
    if (override != null) {
      _set(_cTermBarLF, override.toStringAsFixed(0));
      _termBarOverride = true;
    } else {
      _set(_cTermBarLF, _nz(par.parapetTotalLF));
      _termBarOverride = false;
    }

    // ── Metal Scope ─────────────────────────────────────────────────
    _set(_cCopingLF,    _nz(met.copingLF));
    _set(_cEdgeMetalLF, _nz(met.edgeMetalLF));
    _set(_cGutterLF,    _nz(met.gutterLF));
    _set(_cDownspouts,  met.downspoutCount > 0 ? '${met.downspoutCount}' : '');

    setState(() {
      _warrantyYears   = '${info.warrantyYears}';
      _climateZone     = info.climateZone;
      _windSpeed       = info.designWindSpeed;
      _requiredRValue  = info.requiredRValue != null
          ? 'R-${info.requiredRValue!.toStringAsFixed(0)} (req)' : null;
      _roofSlope       = geo.roofSlope;
      _zonesOverridden = geo.windZones.perimeterZoneWidth > 0;
      _projectType     = specs.projectType.isNotEmpty ? specs.projectType : 'New Construction';
      _deckType        = specs.deckType.isNotEmpty    ? specs.deckType    : 'Metal';
      _vaporRetarder   = specs.vaporRetarder.isNotEmpty ? specs.vaporRetarder : 'None';
      _existingRoofType = specs.existingRoofType.isNotEmpty ? specs.existingRoofType : 'BUR';
      _insLayers       = '${ins.numberOfLayers}';
      _l1Type          = ins.layer1.type;
      _l1Thickness     = ins.layer1.thickness.toString();
      _l1Attachment    = ins.layer1.attachmentMethod;
      _l2Type          = ins.layer2?.type ?? 'Polyiso';
      _l2Thickness     = (ins.layer2?.thickness ?? 2.0).toString();
      _l2Attachment    = ins.layer2?.attachmentMethod ?? 'Adhered';
      _hasTapered      = ins.hasTaperedInsulation;
      _taperSlope      = ins.tapered?.taperSlope ?? '1/4:12';
      _taperMinThick   = (ins.tapered?.minThicknessAtDrain ?? 1.0).toString();
      _hasCoverBoard   = ins.hasCoverBoard;
      _cbType          = ins.coverBoard?.type ?? 'HD Polyiso';
      _cbThickness     = (ins.coverBoard?.thickness ?? 0.5).toString();
      _cbAttachment    = ins.coverBoard?.attachmentMethod ?? 'Adhered';
      _memType         = mem.membraneType;
      _memThickness    = mem.thickness;
      _memColor        = mem.color;
      _fieldAttach     = mem.fieldAttachment;
      _rollWidth       = mem.rollWidth;
      _perimRollWidth  = mem.perimeterRollWidth;
      _seamType        = mem.seamType;
      _drainType       = pen.drainType;
      _hasParapet      = par.hasParapetWalls;
      _parapetWallType = par.wallType;
      _terminationType = par.terminationType;
      _copingWidth     = met.copingWidth;
      _edgeMetalType   = met.edgeMetalType;
      _gutterSize      = met.gutterSize;
    });
  }

  void _set(TextEditingController c, String v) { if (c.text != v) c.text = v; }
  String _pct(double f) => (f * 100).toStringAsFixed(0);
  String _nz(double v)  => v > 0 ? (v == v.roundToDouble() ? v.toInt().toString() : v.toString()) : '';

  // ─── Push zone areas to provider ─────────────────────────────────────────────
  void _pushZones(double pw) {
    final ca = _cornerCnt * pw * pw;
    final pa = (_totalPerimeter * pw - ca).clamp(0.0, 1e9);
    final fa = (_totalArea - ca - pa).clamp(0.0, 1e9);
    final n = ref.read(estimatorProvider.notifier);
    n.updateWindZones(WindZones(
      perimeterZoneWidth: pw, cornerZoneWidth: pw,
      cornerZoneArea: ca, perimeterZoneArea: pa, fieldZoneArea: fa,
    ));
    n.updateOutsideCorners(_cornerCnt);
  }

  // ─── Zone width auto-calculation ─────────────────────────────────────────────
  //
  // Fires whenever building height, ZIP wind speed, or warranty years change.
  // Skipped if the user has manually edited the zone width field (_zonesOverridden).
  //
  // All three inputs are required for a table lookup.  If any are missing the
  // method falls back gracefully: wind unknown → uses height-only heuristic;
  // height missing → no-op.

  void _autoZoneWidth({double? height, String? windSpeed, int? warrantyYrs}) {
    if (_zonesOverridden) return;

    // Resolve each parameter: use the supplied value, or fall back to current state.
    final h  = height      ?? double.tryParse(_cBuildingHeight.text) ?? 0;
    final ws = windSpeed   ?? _windSpeed ?? '';
    final wy = warrantyYrs ?? int.tryParse(_warrantyYears) ?? 0;

    if (h <= 0) return; // nothing to compute without height

    double? zw = ZoneWidthLookup.lookup(
      buildingHeight:  h,
      designWindSpeed: ws,
      warrantyYears:   wy,
    );

    // Graceful fallback: if wind speed or warranty are missing, use the
    // conservative height-based heuristic (matches old behaviour).
    zw ??= (h * 0.1).clamp(3.0, 10.0);

    _cPerimeterWidth.text = zw.toStringAsFixed(1);
    setState(() {});
    _pushZones(zw);
  }

  // ─── Shape management ────────────────────────────────────────────────────────
  void _addShape() {
    setState(() => _shapes.add(_ShapeEntry.blank()));
    ref.read(estimatorProvider.notifier).addShape();
  }

  void _removeShape(int i) {
    if (_shapes.length <= 1) return;
    setState(() { _shapes[i].dispose(); _shapes.removeAt(i); });
    ref.read(estimatorProvider.notifier).removeShape(i);
  }

  void _changeShapeType(int i, String newType) {
    setState(() {
      _shapes[i].dispose();
      _shapes[i] = _ShapeEntry.blank(type: newType, operation: _shapes[i].operation);
    });
    ref.read(estimatorProvider.notifier)
        .updateShape(i, RoofShape.initial(i + 1).withShapeType(newType));
  }

  void _syncEdgeTypeTotals() {
    double eaveLF = 0, headwallLF = 0, parapetLF = 0;
    int corners = 0;
    for (final s in _shapes) {
      final edges = s.edgeLengths; final types = s.edgeTypes;
      corners += s.edgeLengths.length;  // use actual edge count, not lookup
      for (int i = 0; i < edges.length && i < types.length; i++) {
        final len = edges[i].abs();
        switch (types[i]) {
          case 'Eave':     eaveLF    += len; break;
          case 'Headwall': headwallLF += len; break;
          case 'Parapet':  parapetLF  += len; break;
          default: break;
        }
      }
    }
    if (corners > 0) {
      _set(_cCornerCount, '$corners');
      ref.read(estimatorProvider.notifier).updateOutsideCorners(corners);
    }
    final n = ref.read(estimatorProvider.notifier);
    if (headwallLF > 0) _set(_cWallLF, headwallLF.toStringAsFixed(1));
    if (parapetLF > 0) {
      _set(_cParapetLF, parapetLF.toStringAsFixed(1));
      n.updateParapetTotalLF(parapetLF);
      if (!_termBarOverride) _set(_cTermBarLF, parapetLF.toStringAsFixed(1));
    }
    if (eaveLF > 0) {
      _set(_cEdgeMetalLF, eaveLF.toStringAsFixed(1));
      n.updateEdgeMetalLF(eaveLF);
    }
  }

  void _pushShape(int i) {
    final s = _shapes[i];
    final notifier = ref.read(estimatorProvider.notifier);
    final geo = ref.read(estimatorProvider).activeBuilding.roofGeometry;
    final model = RoofShape(
      shapeIndex: i + 1,
      shapeType: s.type,
      operation: s.operation,
      edgeLengths: s.edgeLengths,
      edgeTypes: s.edgeTypes,
    );
    if (i < geo.shapes.length) {
      notifier.updateShape(i, model);
    } else {
      notifier.addShape();
      notifier.updateShape(i, model);
    }
    if (_perimWidth > 0) _pushZones(_perimWidth);
    _syncEdgeTypeTotals();
  }

  // ─── BUILD ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Detect building tab switch → resync all controllers
    ref.listen<int>(activeBuildingIndexProvider, (prev, next) {
      if (prev != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncFromState();
        });
      }
    });

    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Row(children: [
          Icon(Icons.input, color: AppTheme.primary, size: 20),
          const SizedBox(width: 8),
          Text('Project Inputs', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppTheme.textPrimary)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
          InputProgressBar(complete: _completeSectionCount, total: 8),
          _sec(0, Icons.assignment,         'Project Info',              _buildProjectInfo(),    dot: _statusProjectInfo()),
          _sec(1, Icons.square_foot,        'Project Geometry',          _buildGeometry(),       dot: _statusGeometry()),
          _sec(2, Icons.layers,             'System Specs',              _buildSystemSpecs(),    dot: _statusSystemSpecs()),
          _sec(3, Icons.view_in_ar,         'Insulation & Cover Board',  _buildInsulation(),     dot: _statusInsulation()),
          _sec(4, Icons.texture,            'Membrane',                  _buildMembrane(),       dot: _statusMembrane()),
          _sec(5, Icons.border_style,       'Perimeters & Penetrations', _buildPenetrations(),   dot: _statusPenetrations()),
          _sec(6, Icons.vertical_align_top, 'Parapet Walls',             _buildParapet(),        dot: _statusParapet()),
          _sec(7, Icons.view_day,           'Metal Scope',               _buildMetalScope(),     dot: _statusMetal()),
          _sec(8, Icons.recycling,          'Waste Settings',            _buildWasteSettings()),
        ]),
      ),
    ]);
  }


  // ─── Section completion status ───────────────────────────────────────────────
  // Each helper reads from state/local fields to decide dot color.

  DotStatus _statusProjectInfo() {
    final info = ref.read(projectInfoProvider);
    return dotStatus([
      info.projectName.isNotEmpty,
      info.projectAddress.isNotEmpty,
      info.zipCode.length == 5,
      info.zipLookupComplete,
    ]);
  }

  DotStatus _statusGeometry() {
    final geo = ref.read(roofGeometryProvider);
    return dotStatus([
      geo.totalArea > 0,
      geo.buildingHeight > 0,
      geo.windZones.perimeterZoneWidth > 0,
    ]);
  }

  DotStatus _statusSystemSpecs() {
    final specs = ref.read(systemSpecsProvider);
    return dotStatus([
      specs.projectType.isNotEmpty,
      specs.deckType.isNotEmpty,
    ]);
  }

  DotStatus _statusInsulation() {
    final ins = ref.read(insulationSystemProvider);
    return dotStatus([
      ins.layer1.thickness > 0,
    ]);
  }

  DotStatus _statusMembrane() {
    final mem = ref.read(membraneSystemProvider);
    return dotStatus([
      mem.membraneType.isNotEmpty,
      mem.thickness.isNotEmpty,
      mem.fieldAttachment.isNotEmpty,
    ]);
  }

  DotStatus _statusPenetrations() {
    final pen = ref.read(penetrationsProvider);
    final geo = ref.read(roofGeometryProvider);
    // "done" when drain count matches geometry, or user has touched it
    return dotStatus([
      pen.rtuTotalLF > 0 || pen.smallPipeCount > 0 || pen.scupperCount > 0
          || geo.drainLocations.isNotEmpty,
    ]);
  }

  DotStatus _statusParapet() {
    final par = ref.read(parapetWallsProvider);
    if (!par.hasParapetWalls) return DotStatus.complete; // opted out = done
    return dotStatus([
      par.parapetHeight > 0,
      par.parapetTotalLF > 0,
    ]);
  }

  DotStatus _statusMetal() {
    final met = ref.read(metalScopeProvider);
    return dotStatus([
      met.copingLF > 0 || met.edgeMetalLF > 0 || met.gutterLF > 0,
    ]);
  }

  int get _completeSectionCount {
    return [
      _statusProjectInfo(),
      _statusGeometry(),
      _statusSystemSpecs(),
      _statusInsulation(),
      _statusMembrane(),
      _statusPenetrations(),
      _statusParapet(),
      _statusMetal(),
    ].where((s) => s == DotStatus.complete).length;
  }

  Widget _sec(int idx, IconData icon, String title, Widget child,
      {DotStatus dot = DotStatus.empty}) {
    final open = _expandedSection == idx;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: open ? AppTheme.primary.withOpacity(0.02) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: open ? AppTheme.primary.withOpacity(0.2) : Colors.transparent),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expandedSection = open ? -1 : idx),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: open ? AppTheme.primary.withOpacity(0.1) : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 18, color: open ? AppTheme.primary : AppTheme.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14,
                  color: open ? AppTheme.primary : AppTheme.textPrimary))),
              if (!open) SectionDot(status: dot),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: AppTheme.textSecondary, size: 20),
            ]),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: child),
      ]),
    );
  }

  // ─── PROJECT INFO ─────────────────────────────────────────────────────────────
  Widget _buildProjectInfo() {
    final n = ref.read(estimatorProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tf('Project Name *', 'Enter project name', _cProjectName,
          onChange: (v) => n.updateProjectName(v)),
      _sp12,
      _tf('Project Address *', 'Street address', _cProjectAddress,
          onChange: (v) => n.updateProjectAddress(v)),
      _sp12,
      _lbl('ZIP Code *'), _sp4,
      SizedBox(height: 40, child: TextField(
        controller: _cZipCode, keyboardType: TextInputType.number, maxLength: 5,
        onChanged: (v) { n.updateZipCode(v); _onZipChange(v); },
        decoration: _dec('00000', counterText: '',
          suffix: _zipLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : (_climateZone != null ? Icon(Icons.check_circle, color: AppTheme.accent, size: 18) : null)),
        style: const TextStyle(fontSize: 14),
      )),
      if (_climateZone != null) ...[
        _sp8,
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.accent.withOpacity(0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Auto-Populated from ZIP', style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w600, color: AppTheme.accent)),
            const SizedBox(height: 6),
            _zipRow(Icons.map,        'Climate Zone', _climateZone!),
            _zipRow(Icons.air,        'Wind Speed',   _windSpeed!),
            _zipRow(Icons.thermostat, 'Required R',   _requiredRValue!),
          ]),
        ),
      ],
      _sp12,
      _tf('Customer Name', 'Optional', _cCustomerName, onChange: (v) => n.updateCustomerName(v)),
      _sp12,
      _tf('Estimator Name', 'Optional', _cEstimatorName, onChange: (v) => n.updateEstimatorName(v)),
      _sp12,
      _lbl('Estimate Date'), _sp4,
      SizedBox(height: 40, child: TextField(enabled: false,
          controller: TextEditingController(text: _estimateDate),
          decoration: _dec('', suffix: Icon(Icons.calendar_today, size: 16, color: AppTheme.textMuted), disabled: true),
          style: const TextStyle(fontSize: 14))),
      _sp12,
      _dd('Warranty Duration *', _warrantyYears,
          ['10','15','20','25','30'].map((y) => '$y Year').toList(), (v) {
        if (v != null) {
          final yr = int.parse(v.split(' ')[0]);
          setState(() => _warrantyYears = v.split(' ')[0]);
          n.updateWarrantyYears(yr);
          _autoZoneWidth(warrantyYrs: yr);
        }
      }),
      _sp8,
      _info('Warranty level affects fastening density and assembly requirements.'),
    ]);
  }

  void _onZipChange(String zip) {
    // Clear results whenever the field changes
    setState(() { _climateZone = null; _windSpeed = null; _requiredRValue = null; });

    if (zip.length < 5) return;

    // Instant offline lookup — no network call needed
    setState(() => _zipLoading = true);

    // Small delay so the loading spinner is visible to the user
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;

      final result = ZipLookupService.lookup(zip);

      if (result.found) {
        final rLabel = 'R-${result.requiredRValue.toStringAsFixed(0)} (ASHRAE 90.1)';
        setState(() {
          _zipLoading     = false;
          _climateZone    = result.climateZone;
          _windSpeed      = result.designWindSpeed;
          _requiredRValue = rLabel;
        });
        ref.read(estimatorProvider.notifier).applyZipLookup(
          climateZone:      result.zoneCode,
          designWindSpeed:  result.designWindSpeed,
          requiredRValue:   result.requiredRValue,
        );
        _applyRValueDefaults(result.requiredRValue);
        _autoZoneWidth(windSpeed: result.designWindSpeed);
      } else {
        // Prefix not in table — show fallback with clear label
        setState(() {
          _zipLoading     = false;
          _climateZone    = 'Zone unknown — verify manually';
          _windSpeed      = '115 mph (default)';
          _requiredRValue = 'R-25 (default)';
        });
        ref.read(estimatorProvider.notifier).applyZipLookup(
          climateZone:      '4',
          designWindSpeed:  '115 mph',
          requiredRValue:   25.0,
        );
        _applyRValueDefaults(25.0);
        _autoZoneWidth(windSpeed: '115 mph');
      }
    });
  }

  // ─── R-VALUE DRIVEN INSULATION DEFAULTS ────────────────────────────────────
  /// Called after ZIP lookup. If insulation hasn't been customised yet,
  /// applies a code-compliant starting point based on [requiredR].
  /// Decision table (Polyiso @ 5.7 R/in + 0.5 membrane):
  ///   R < 20  → 1 layer, 3.5"  ≈ R-20.5
  ///   R 20-25 → 2 layers, 2.5" ≈ R-29.0
  ///   R 25+   → 2 layers, 2.6" ≈ R-30.1  ← covers R-25 & R-30
  ///   R > 35  → 2 layers, 3.5" ≈ R-40.4
  void _applyRValueDefaults(double requiredR) {
    final n = ref.read(estimatorProvider.notifier);
    // Only auto-fill if user hasn't already changed from the factory default
    // (factory default is 1 layer, 2.5")
    final current = ref.read(estimatorProvider).activeBuilding.insulationSystem;
    final isDefaultState = current.numberOfLayers == 1 &&
        current.layer1.thickness == 2.5 &&
        current.layer1.type == 'Polyiso';
    if (!isDefaultState) return; // user already customised — don't overwrite

    late int layers;
    late double thickness;

    if (requiredR < 20) {
      layers = 1; thickness = 3.5;
    } else if (requiredR < 25) {
      layers = 2; thickness = 2.5;
    } else if (requiredR <= 32) {
      layers = 2; thickness = 2.6; // 2×2.6"×5.7 + 0.5 = R-30.1
    } else if (requiredR <= 38) {
      layers = 2; thickness = 3.0; // 2×3.0"×5.7 + 0.5 = R-34.7
    } else {
      layers = 2; thickness = 3.5; // 2×3.5"×5.7 + 0.5 = R-40.4
    }

    final defaultL1 = InsulationLayer(
        type: 'Polyiso', thickness: thickness,
        attachmentMethod: 'Mechanically Attached');
    final defaultL2 = InsulationLayer(
        type: 'Polyiso', thickness: thickness,
        attachmentMethod: 'Adhered');

    setState(() {
      _insLayers    = layers.toString();
      _l1Thickness  = thickness.toString();
      _l2Thickness  = thickness.toString();
      _l1Type = _l2Type = 'Polyiso';
      _l1Attachment = 'Mechanically Attached';
      _l2Attachment = 'Adhered';
    });

    n.setNumberOfLayers(layers);
    n.updateLayer1(defaultL1);
    if (layers == 2) n.updateLayer2(defaultL2);
  }

  // ─── GEOMETRY ─────────────────────────────────────────────────────────────────
  Widget _buildGeometry() {
    final n = ref.read(estimatorProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _tf('Building Height *', '0', _cBuildingHeight, suffix: 'ft',
            kb: TextInputType.number, onChange: (v) {
              final h = double.tryParse(v) ?? 0;
              n.updateBuildingHeight(h);
              _autoZoneWidth(height: h);
            })),
        const SizedBox(width: 8),
        Expanded(child: _dd('Roof Slope', _roofSlope,
            ['Flat','1/4:12','1/2:12','1:12','2:12','Custom'], (v) {
          setState(() => _roofSlope = v!);
          n.updateRoofSlope(v!);
        })),
      ]),
      _sp16,

      // Shape header
      Row(children: [
        Text('Roof Shapes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const Spacer(),
        if (_shapes.length < 4) GestureDetector(
          onTap: _addShape,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add, size: 13, color: AppTheme.primary), const SizedBox(width: 4),
              Text('Add Shape', style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
      _sp8,
      for (int i = 0; i < _shapes.length; i++) ...[
        _shapeCard(i),
        if (i < _shapes.length - 1) _sp8,
      ],
      _sp16,

      // Totals
      _lbl('Calculated Totals'), _sp8,
      Row(children: [
        Expanded(child: _calcBox('Total Area', _totalArea > 0 ? '${_totalArea.toStringAsFixed(0)} sq ft' : '—', Icons.crop_square)),
        const SizedBox(width: 8),
        Expanded(child: _calcBox('Perimeter', _totalPerimeter > 0 ? '${_totalPerimeter.toStringAsFixed(0)} LF' : '—', Icons.border_outer)),
      ]),
      _sp16,

      // Wind zones
      Row(children: [
        Text('Wind Zones', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(width: 6),
        Tooltip(message: 'Auto-calculated: Versico zone width table\n(height + wind + warranty). Edit to override.',
            child: Icon(Icons.info_outline, size: 14, color: AppTheme.textMuted)),
      ]),
      _sp4,
      _info('Corner = # outside corners × width². Perimeter = (perim LF × width) − corners. Field = total − both.', color: AppTheme.primary),
      _sp8,
      Row(children: [
        Expanded(child: _tfHelper('Perimeter Zone Width', 'Auto', _cPerimeterWidth,
            helper: 'From Versico table — edit to override', suffix: 'ft',
            kb: TextInputType.number, onChange: (v) {
          setState(() => _zonesOverridden = true);
          _pushZones(double.tryParse(v) ?? 0);
        })),
        const SizedBox(width: 8),
        Expanded(child: _tfHelper('# Outside Corners', '4', _cCornerCount,
            helper: 'Count of outside roof corners', kb: TextInputType.number,
            onChange: (_) {
              setState(() {});
              if (_perimWidth > 0) _pushZones(_perimWidth);
            })),
      ]),
      _sp8,
      _tf('Number of Drains', '0', _cDrainCount, kb: TextInputType.number, onChange: (v) {
        final cnt = int.tryParse(v) ?? 0;
        final geo = ref.read(estimatorProvider).activeBuilding.roofGeometry;
        final cur = geo.drainLocations.length;
        if (cnt > cur) {
          for (int i = cur; i < cnt; i++) n.addDrain(const DrainLocation(x: 0, y: 0));
        } else {
          for (int i = cur - 1; i >= cnt; i--) n.removeDrain(i);
        }
      }),
      _sp12,
      _zoneChips(),
    ]);
  }

  Widget _shapeCard(int idx) {
    final s      = _shapes[idx];
    final isFirst = idx == 0;
    final labels = _edgeLabelsFor(s.type);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFirst ? AppTheme.primary.withOpacity(0.04) : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isFirst ? AppTheme.primary.withOpacity(0.2) : AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isFirst ? AppTheme.primary : AppTheme.textSecondary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(isFirst ? 'Shape 1 (Primary)' : 'Shape ${idx + 1}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: isFirst ? Colors.white : AppTheme.textSecondary)),
          ),
          const Spacer(),
          if (!isFirst) GestureDetector(
              onTap: () => _removeShape(idx),
              child: Icon(Icons.close, size: 16, color: AppTheme.textMuted)),
        ]),
        _sp10,
        _dd('Shape Type', s.type,
            ['Rectangle','Square','L-Shape','T-Shape','U-Shape'],
            (v) { if (v != null) _changeShapeType(idx, v); }),
        if (!isFirst) ...[
          _sp8,
          _dd('Operation', s.operation, ['Add','Subtract'], (v) {
            if (v == null) return;
            setState(() {
              _shapes[idx] = _ShapeEntry(
                  type: s.type, operation: v, edgeControllers: s.edgeControllers,
                  edgeTypes: s.edgeTypes);
            });
            _pushShape(idx);
          }),
        ],
        _sp10,
        _shapeDiagramHint(s.type),
        _sp8,
        Text('${s.edgeControllers.length} Edges — Measurement + Type',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary, letterSpacing: 0.4)),
        _sp6,
        for (int e = 0; e < s.edgeControllers.length; e++) ...[
          if (e > 0) _sp8,
          Text(e < labels.length ? labels[e] : 'Edge ${e+1}',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted, letterSpacing: 0.3)),
          const SizedBox(height: 3),
          Row(children: [
            Expanded(flex: 2, child: SizedBox(height: 40, child: TextField(
              controller: s.edgeControllers[e],
              keyboardType: TextInputType.number,
              onChanged: (_) { setState(() {}); _pushShape(idx); },
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                suffixText: 'ft',
                suffixStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true, fillColor: Colors.white,
              ),
              style: const TextStyle(fontSize: 14),
            ))),
            const SizedBox(width: 6),
            Expanded(flex: 3, child: SizedBox(height: 40, child: DropdownButtonFormField<String>(
              value: kEdgeTypes.contains(
                  e < s.edgeTypes.length ? s.edgeTypes[e] : kDefaultEdgeType)
                  ? (e < s.edgeTypes.length ? s.edgeTypes[e] : kDefaultEdgeType)
                  : kDefaultEdgeType,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                filled: true, fillColor: Colors.white,
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
              isExpanded: true,
              items: kEdgeTypes.map((t) => DropdownMenuItem(
                value: t,
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(
                    color: Color(kEdgeTypeColors[t] ?? 0xFF94A3B8), shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Flexible(child: Text(t, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12))),
                ]),
              )).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() { _shapes[idx] = _shapes[idx].withEdgeType(e, v); });
                _pushShape(idx);
              },
            ))),
          ]),
        ],
        if (s.area > 0 || s.perimeter > 0) ...[
          _sp10,
          Row(children: [
            _miniCalc('Area', '${s.area.toStringAsFixed(0)} sf'),
            const SizedBox(width: 8),
            _miniCalc('Perim', '${s.perimeter.toStringAsFixed(0)} LF'),
          ]),
        ],
        if (s.type == 'T-Shape' || s.type == 'U-Shape')
          Padding(padding: const EdgeInsets.only(top: 8),
              child: _info('T/U area estimated — verify total and override if needed.', color: AppTheme.warning)),
      ]),
    );
  }

  Widget _shapeDiagramHint(String shapeType) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 13, color: AppTheme.primary),
        const SizedBox(width: 6),
        Expanded(child: SizedBox(
          height: 80,
          child: CustomPaint(painter: _ShapeDiagramPainter(shapeType)),
        )),
      ]),
    );
  }

  Widget _zoneChips() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Zone Areas', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary, letterSpacing: 0.5)),
      _sp10,
      Row(children: [
        Expanded(child: _chip('Field',     _fieldArea,  const Color(0xFFDBEAFE))),
        const SizedBox(width: 6),
        Expanded(child: _chip('Perimeter', _perimArea,  const Color(0xFF93C5FD))),
        const SizedBox(width: 6),
        Expanded(child: _chip('Corner',    _cornerArea, const Color(0xFF3B82F6))),
      ]),
      if (_totalArea <= 0 || _perimWidth <= 0)
        Padding(padding: const EdgeInsets.only(top: 8),
            child: Text('Enter edges and building height to calculate zones.',
                style: TextStyle(fontSize: 10, color: AppTheme.textMuted))),
    ]),
  );

  // ─── SYSTEM SPECS ─────────────────────────────────────────────────────────────
  Widget _buildSystemSpecs() {
    final n = ref.read(estimatorProvider.notifier);
    final reroof = _projectType != 'New Construction';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dd('Project Type', _projectType,
          ['New Construction','Recover','Tear-off & Replace'], (v) {
        setState(() => _projectType = v!);
        n.updateProjectType(v!);
      }),
      _sp12,
      if (reroof) ...[
        _dd('Existing Roof Type', _existingRoofType,
            ['BUR','Modified Bitumen','Single-Ply','Metal'], (v) {
          setState(() => _existingRoofType = v!);
          n.updateExistingRoofType(v!);
        }),
        _sp12,
        _tf('Existing Layers', '1', _cExistingLayers, kb: TextInputType.number,
            onChange: (v) => n.updateExistingLayers(int.tryParse(v) ?? 1)),
        _sp12,
      ],
      _dd('Deck Type *', _deckType,
          ['Metal','Concrete','Wood','Gypsum','Tectum','LW Concrete'], (v) {
        setState(() => _deckType = v!);
        n.updateDeckType(v!);
      }),
      _sp12,
      _dd('Vapor Retarder', _vaporRetarder,
          ['None','Self-Adhered','Hot Applied','Mechanically Attached'], (v) {
        setState(() => _vaporRetarder = v!);
        n.updateVaporRetarder(v!);
      }),
      if (reroof) ...[_sp10, _info('Moisture scan auto-required for Recover/Tear-off.')],
    ]);
  }

  // ─── INSULATION ───────────────────────────────────────────────────────────────
  Widget _buildInsulation() {
    final n = ref.read(estimatorProvider.notifier);
    final thickLabels = ['0.5"','1.0"','1.5"','2.0"','2.5"','2.6"','3.0"','3.5"','4.0"'];
    final thickVals   = [0.5, 1.0, 1.5, 2.0, 2.5, 2.6, 3.0, 3.5, 4.0];

    String tLabel(double v) => '${v == v.roundToDouble() ? v.toInt() : v}"';
    double tVal(String s) { final i = thickLabels.indexOf(s); return i >= 0 ? thickVals[i] : 2.5; }

    void pushL1() => n.updateLayer1(InsulationLayer(type: _l1Type,
        thickness: double.tryParse(_l1Thickness) ?? 2.5, attachmentMethod: _l1Attachment));
    void pushL2() => n.updateLayer2(InsulationLayer(type: _l2Type,
        thickness: double.tryParse(_l2Thickness) ?? 2.0, attachmentMethod: _l2Attachment));
    void pushTaper() => n.updateTapered(TaperedInsulation(boardType: _cTaperBoard.text,
        taperSlope: _taperSlope,
        minThicknessAtDrain: double.tryParse(_taperMinThick) ?? 1.0,
        maxThickness: ref.read(estimatorProvider).activeBuilding.insulationSystem.tapered?.maxThickness ?? 0,
        systemArea: double.tryParse(_cTaperArea.text) ?? 0));
    void pushCB() => n.updateCoverBoard(CoverBoard(type: _cbType,
        thickness: double.tryParse(_cbThickness) ?? 0.5, attachmentMethod: _cbAttachment));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dd('Number of Insulation Layers', _insLayers, ['1','2'], (v) {
        setState(() => _insLayers = v!);
        n.setNumberOfLayers(int.parse(v!));
      }),
      _sp12, _lbl('LAYER 1'), _sp6,
      _dd('Type', _l1Type, kInsulationTypes, (v) { setState(() => _l1Type = v!); pushL1(); }),
      _sp8,
      _dd('Thickness', tLabel(double.tryParse(_l1Thickness) ?? 2.5), thickLabels, (v) {
        setState(() => _l1Thickness = tVal(v!).toString()); pushL1(); }),
      _sp8,
      _dd('Attachment', _l1Attachment, kAttachmentMethods, (v) {
        setState(() => _l1Attachment = v!); pushL1(); }),

      if (_insLayers == '2') ...[
        _sp14, _lbl('LAYER 2'), _sp6,
        _dd('Type', _l2Type, kInsulationTypes, (v) { setState(() => _l2Type = v!); pushL2(); }),
        _sp8,
        _dd('Thickness', tLabel(double.tryParse(_l2Thickness) ?? 2.0), thickLabels, (v) {
          setState(() => _l2Thickness = tVal(v!).toString()); pushL2(); }),
        _sp8,
        _dd('Attachment', _l2Attachment, kAttachmentMethods, (v) {
          setState(() => _l2Attachment = v!); pushL2(); }),
      ],

      _sp14,
      _toggle('Tapered Insulation', 'Slopes toward drains', _hasTapered, (v) {
        setState(() => _hasTapered = v); n.setTaperedEnabled(v);
      }),
      if (_hasTapered) ...[
        _sp10,
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppTheme.border)),
          child: Column(children: [
            _tf('Board Type (Versico/Tri-Built)', 'e.g. Versico Tapered Polyiso', _cTaperBoard,
                onChange: (_) => pushTaper()),
            _sp8,
            Row(children: [
              Expanded(child: _dd('Taper Slope', _taperSlope, kTaperSlopeOptions, (v) {
                setState(() => _taperSlope = v!); pushTaper(); })),
              const SizedBox(width: 8),
              Expanded(child: _dd('Min at Drain', _taperMinThick,
                  kTaperMinThicknesses.map((v) => v.toString()).toList(), (v) {
                setState(() => _taperMinThick = v!); pushTaper(); })),
            ]),
            _sp8,
            _tf('System Area', '0', _cTaperArea, suffix: 'sq ft',
                kb: TextInputType.number, onChange: (_) => pushTaper()),
          ]),
        ),
      ],

      _sp12,
      _toggle('Cover Board', 'HD Polyiso, Gypsum, DensDeck', _hasCoverBoard, (v) {
        setState(() => _hasCoverBoard = v); n.setCoverBoardEnabled(v);
      }),
      if (_hasCoverBoard) ...[
        _sp10,
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppTheme.border)),
          child: Column(children: [
            _dd('Type', _cbType, kCoverBoardTypes, (v) { setState(() => _cbType = v!); pushCB(); }),
            _sp8,
            Row(children: [
              Expanded(child: _dd('Thickness', _cbThickness,
                  kCoverBoardThicknesses.map((v) => v.toString()).toList(), (v) {
                setState(() => _cbThickness = v!); pushCB(); })),
              const SizedBox(width: 8),
              Expanded(child: _dd('Attachment', _cbAttachment, kAttachmentMethods, (v) {
                setState(() => _cbAttachment = v!); pushCB(); })),
            ]),
          ]),
        ),
      ],

      _sp14,
      _buildRValueSummary(),
    ]);
  }

  /// Live R-value summary + code compliance banner.
  Widget _buildRValueSummary() {
    final rv       = ref.watch(rValueResultProvider);
    final info     = ref.watch(projectInfoProvider);
    final reqR     = info.requiredRValue;
    final totalR   = rv?.totalRValue ?? 0.0;
    final meets    = reqR == null || (rv != null && totalR >= reqR);
    final color    = meets ? AppTheme.accent : AppTheme.warning;
    final icon     = meets ? Icons.check_circle : Icons.warning_amber_rounded;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // R-value bar
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Assembly R-Value: ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Text('R-${totalR.toStringAsFixed(1)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
              if (reqR != null) ...[
                const SizedBox(width: 6),
                Text('(req. R-${reqR.toStringAsFixed(0)})',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ],
            ]),
            if (reqR != null && !meets) ...[
              const SizedBox(height: 4),
              Text('Add ${(reqR - totalR).toStringAsFixed(1)} R to meet code.',
                  style: TextStyle(color: AppTheme.warning, fontSize: 11)),
            ],
          ])),
        ]),
      ),

      // Suggested-by-ZIP banner — only shown if ZIP lookup ran
      if (reqR != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
          ),
          child: Row(children: [
            Icon(Icons.auto_fix_high, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(
              'Climate zone requires R-${reqR.toStringAsFixed(0)}. '
              'Defaults set to ${_insLayers == "2" ? "2 layers" : "1 layer"} '
              'Polyiso ${_l1Thickness}" — edit above as needed.',
              style: TextStyle(fontSize: 11, color: AppTheme.primary),
            )),
          ]),
        ),
      ],
    ]);
  }

  // ─── MEMBRANE ─────────────────────────────────────────────────────────────────
  Widget _buildMembrane() {
    final n = ref.read(estimatorProvider.notifier);
    void pushMem() => n.updateMembraneSystem(MembraneSystem(
        membraneType: _memType, thickness: _memThickness, color: _memColor,
        fieldAttachment: _fieldAttach, rollWidth: _rollWidth, seamType: _seamType));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dd('Membrane Type', _memType, ['TPO','PVC','EPDM'], (v) {
        setState(() => _memType = v!); pushMem(); }),
      _sp12,
      _dd('Thickness', _memThickness, ['45 mil','60 mil','80 mil'], (v) {
        setState(() => _memThickness = v!); pushMem(); }),
      _sp12,
      _dd('Color', _memColor, ['White','Gray','Tan','Reflective White'], (v) {
        setState(() => _memColor = v!); pushMem(); }),
      _sp12,
      _dd('Field Attachment Method *', _fieldAttach,
          ['Mechanically Attached','Fully Adhered','Rhinobond (Induction Welded)'], (v) {
        setState(() => _fieldAttach = v!); n.updateFieldAttachment(v!); }),
      if (_fieldAttach == 'Rhinobond (Induction Welded)') ...[
        _sp8,
        _info('Rhinobond: induction heat welds membrane to plates through insulation. '
            'No field fasteners penetrate the membrane. Plate spacing from Versico wind uplift table.',
            color: AppTheme.secondary),
      ],
      if (_fieldAttach == 'Fully Adhered') ...[
        _sp8,
        _info('Fully Adhered: bonding adhesive applied to both surfaces. '
            'Check climate zone for adhesive temperature limits.', color: AppTheme.warning),
      ],
      _sp12,
      _dd('Seam Type', _seamType, ['Hot Air Welded','Tape'], (v) {
        setState(() => _seamType = v!); n.updateSeamType(v!); }),

      // ── Roll Selection ────────────────────────────────────────────────────────
      _sp16,
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TPO Roll Selection', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: AppTheme.primary, letterSpacing: 0.4)),
          _sp10,

          // Field roll — user selects width
          _lbl('FIELD AREA ROLL (user-selectable)'), _sp4,
          SizedBox(height: 40, child: DropdownButtonFormField<String>(
            value: ["5'","10'","12'"].contains(_rollWidth) ? _rollWidth : "10'",
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              filled: true, fillColor: Colors.white),
            style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            items: [
              DropdownMenuItem(value: "5'",  child: Text("5' × 100' (500 sf)")),
              DropdownMenuItem(value: "10'", child: Text("10' × 100' (1,000 sf)")),
              DropdownMenuItem(value: "12'", child: Text("12' × 100' (1,200 sf)")),
            ],
            onChanged: (v) {
              if (v != null) { setState(() => _rollWidth = v); n.updateRollWidth(v); }
            },
          )),
          _sp4,
          Text('Used for: Field zone membrane area calculation only',
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),

          _sp12,

          // Perimeter / flashing roll — default 6'×100' per Versico spec, user-overridable
          _lbl('PERIMETER / FLASHING ROLL'), _sp4,
          _dd('Perimeter Roll Width', _perimRollWidth,
              ["5'", "6'", "10'", "12'"],
              (v) { if (v != null) { setState(() => _perimRollWidth = v); n.updatePerimRollWidth(v); } }),
          _sp4,
          Text('Default 6\'×100\' (600 sf) per Versico spec — used for parapet flashing, detail work',
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        ]),
      ),
    ]);
  }

  // ─── PENETRATIONS ─────────────────────────────────────────────────────────────
  Widget _buildPenetrations() {
    final n = ref.read(estimatorProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tf('Headwall Flashing Height', '12', _cWallHeight, suffix: 'in'),
      _sp12, _tf('Total Headwall LF', '0', _cWallLF, suffix: 'LF'),
      _sp16, _lbl('PENETRATIONS'), _sp8,
      Row(children: [
        Expanded(child: _tf('RTU Curb LF', '0', _cRtuLF, kb: TextInputType.number,
            onChange: (v) => n.updateRtuTotalLF(double.tryParse(v) ?? 0))),
        const SizedBox(width: 8),
        Expanded(child: _tf('Drains', '0', _cDrainCountPen, kb: TextInputType.number)),
      ]),
      _sp8,
      _dd('Drain Type', _drainType, ['Standard','Overflow','Retrofit'], (v) {
        setState(() => _drainType = v!); n.updateDrainType(v!); }),
      _sp8,
      Row(children: [
        Expanded(child: _tf('Pipes (sm 1–4")', '0', _cSmallPipes, kb: TextInputType.number,
            onChange: (v) => n.updateSmallPipeCount(int.tryParse(v) ?? 0))),
        const SizedBox(width: 8),
        Expanded(child: _tf('Pipes (lg 4–12")', '0', _cLargePipes, kb: TextInputType.number,
            onChange: (v) => n.updateLargePipeCount(int.tryParse(v) ?? 0))),
      ]),
      _sp8,
      Row(children: [
        Expanded(child: _tf('Skylights', '0', _cSkylights, kb: TextInputType.number,
            onChange: (v) => n.updateSkylightCount(int.tryParse(v) ?? 0))),
        const SizedBox(width: 8),
        Expanded(child: _tf('Scuppers', '0', _cScuppers, kb: TextInputType.number,
            onChange: (v) => n.updateScupperCount(int.tryParse(v) ?? 0))),
      ]),
      _sp8,
      Row(children: [
        Expanded(child: _tf('Expansion Joint LF', '0', _cExpJointLF, suffix: 'LF',
            kb: TextInputType.number,
            onChange: (v) => n.updateExpansionJointLF(double.tryParse(v) ?? 0))),
        const SizedBox(width: 8),
        Expanded(child: _tf('Pitch Pans', '0', _cPitchPans, kb: TextInputType.number,
            onChange: (v) => n.updatePitchPanCount(int.tryParse(v) ?? 0))),
      ]),
    ]);
  }

  // ─── PARAPET ──────────────────────────────────────────────────────────────────
  // Toggle hidden per design decision — parapet section off by default.
  Widget _buildParapet() {
    final n = ref.read(estimatorProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Toggle removed — parapet walls off by default. Re-enable in code if needed.
      if (_hasParapet) ...[
        _sp16,
        Row(children: [
          Expanded(child: _tf('Parapet Height *', '0', _cParapetHeight, suffix: 'in',
              kb: TextInputType.number, onChange: (v) {
                setState(() {});
                n.updateParapetHeight(double.tryParse(v) ?? 0);
              })),
          const SizedBox(width: 8),
          Expanded(child: _tf('Total LF *', '0', _cParapetLF, suffix: 'LF',
              kb: TextInputType.number, onChange: (v) {
                setState(() { if (!_termBarOverride) _cTermBarLF.text = v; });
                n.updateParapetTotalLF(double.tryParse(v) ?? 0);
              })),
        ]),
        _sp12,
        _calcBox('Parapet Area',
            _parapetArea > 0 ? '${_parapetArea.toStringAsFixed(0)} sq ft' : '—', Icons.calculate),
        if (_parapetArea > 0) Padding(padding: const EdgeInsets.only(top: 3),
            child: Text('(${_cParapetHeight.text}" ÷ 12) × ${_cParapetLF.text} LF = ${_parapetArea.toStringAsFixed(1)} sq ft',
                style: TextStyle(fontSize: 10, color: AppTheme.textMuted))),
        _sp12,
        _dd('Wall Type', _parapetWallType, kParapetWallTypes, (v) {
          setState(() => _parapetWallType = v!); n.updateParapetWallType(v!); }),
        _sp12,
        _lbl('Anchor Type (Auto)'), _sp4,
        Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border)),
          child: Row(children: [
            Icon(Icons.auto_fix_high, size: 14, color: AppTheme.textMuted), const SizedBox(width: 8),
            Text(_anchorType, style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
            const Spacer(),
            Text('Auto', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          ]),
        ),
        _sp12,
        _tfHelper('Termination Bar LF',
            _parapetLFval > 0 ? _parapetLFval.toStringAsFixed(0) : '0',
            _cTermBarLF,
            helper: 'Defaults to Total Parapet LF — edit to override',
            suffix: 'LF', kb: TextInputType.number, onChange: (v) {
          final parsed = double.tryParse(v) ?? 0;
          setState(() => _termBarOverride = parsed != _parapetLFval);
          if (_termBarOverride) {
            n.overrideTerminationBarLF(parsed);
          } else {
            n.clearTerminationBarLFOverride();
          }
        }),
        _sp12,
        _dd('Termination Type', _terminationType, kTerminationTypes, (v) {
          setState(() => _terminationType = v!); n.updateTerminationType(v!); }),
        if (_parapetArea > 0) ...[_sp16, _parapetBOM()],
      ],
    ]);
  }

  Widget _parapetBOM() {
    final flashRolls = (_parapetArea * (1 + _wMat) / 600).ceil();
    final termPieces = (_termBarLF * (1 + _wMetal) / 10).ceil();
    final adhesiveGal = (_parapetArea / 60).ceil();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withOpacity(0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('BOM IMPACT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: AppTheme.primary, letterSpacing: 0.8)),
          const Spacer(),
          Text('Waste: ${(_wMat * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        ]),
        _sp8,
        _impactRow(Icons.layers,      'TPO Flashing Rolls',  "$flashRolls rolls (6'×100')"),
        _impactRow(Icons.straighten,  _terminationType,
            "$termPieces pcs (${_termBarLF.toStringAsFixed(0)} LF ÷ 10')"),
        _impactRow(Icons.format_paint,'Bonding Adhesive',    '+$adhesiveGal gal'),
      ]),
    );
  }

  // ─── METAL SCOPE ──────────────────────────────────────────────────────────────
  Widget _buildMetalScope() {
    final n = ref.read(estimatorProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _dd('Coping Width', _copingWidth, kCopingWidths, (v) {
          setState(() => _copingWidth = v!); n.updateCopingWidth(v!); })),
        const SizedBox(width: 8),
        Expanded(child: _tf('Coping LF', '0', _cCopingLF, suffix: 'LF',
            kb: TextInputType.number, onChange: (v) => n.updateCopingLF(double.tryParse(v) ?? 0))),
      ]),
      _sp12,
      _dd('Edge Metal Type', _edgeMetalType, kEdgeMetalTypes, (v) {
        setState(() => _edgeMetalType = v!); n.updateEdgeMetalType(v!); }),
      _sp8,
      _tf('Edge Metal LF', '0', _cEdgeMetalLF, suffix: 'LF',
          kb: TextInputType.number, onChange: (v) => n.updateEdgeMetalLF(double.tryParse(v) ?? 0)),
      _sp12,
      Row(children: [
        Expanded(child: _dd('Gutter Size', _gutterSize, kGutterSizes, (v) {
          setState(() => _gutterSize = v!); n.updateGutterSize(v!); })),
        const SizedBox(width: 8),
        Expanded(child: _tf('Gutter LF', '0', _cGutterLF, suffix: 'LF',
            kb: TextInputType.number, onChange: (v) => n.updateGutterLF(double.tryParse(v) ?? 0))),
      ]),
      _sp12,
      _tf('Downspout Count', '0', _cDownspouts, kb: TextInputType.number,
          onChange: (v) => n.updateDownspoutCount(int.tryParse(v) ?? 0)),
    ]);
  }

  // ─── WASTE SETTINGS ───────────────────────────────────────────────────────────
  Widget _buildWasteSettings() {
    final n = ref.read(estimatorProvider.notifier);
    void pushWaste() {
      final info = ref.read(projectInfoProvider);
      n.updateProjectInfo(info.copyWith(
        wasteMaterial:  (double.tryParse(_cWasteMaterial.text)  ?? 10) / 100,
        wasteMetal:     (double.tryParse(_cWasteMetal.text)     ??  5) / 100,
        wasteAccessory: (double.tryParse(_cWasteAccessory.text) ??  5) / 100,
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _info('Waste % applied in all BOM calculations. '
          'Material waste (TPO, insulation) is typically higher than metal/accessory waste.',
          color: AppTheme.primary),
      _sp12,
      _tfHelper('TPO & Insulation Waste %', '10', _cWasteMaterial,
          helper: 'Applied to membrane rolls and insulation boards',
          suffix: '%', kb: TextInputType.number, onChange: (_) { setState(() {}); pushWaste(); }),
      _sp12,
      _tfHelper('Metal Waste %', '5', _cWasteMetal,
          helper: 'Applied to coping, edge metal, gutter, termination bar',
          suffix: '%', kb: TextInputType.number, onChange: (_) { setState(() {}); pushWaste(); }),
      _sp12,
      _tfHelper('Accessory / Fastener Waste %', '5', _cWasteAccessory,
          helper: 'Applied to fasteners, adhesive, sealants, accessories',
          suffix: '%', kb: TextInputType.number, onChange: (_) { setState(() {}); pushWaste(); }),
      _sp12,
      Container(padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CURRENT WASTE FACTORS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary, letterSpacing: 0.5)),
          _sp8,
          _impactRow(Icons.texture,  'TPO + Insulation', '${_cWasteMaterial.text}%'),
          _impactRow(Icons.view_day, 'Metals',           '${_cWasteMetal.text}%'),
          _impactRow(Icons.hardware, 'Accessories',      '${_cWasteAccessory.text}%'),
        ]),
      ),
    ]);
  }

  // ─── SHARED UI HELPERS ────────────────────────────────────────────────────────

  // Spacing shortcuts
  Widget get _sp4  => const SizedBox(height: 4);
  Widget get _sp6  => const SizedBox(height: 6);
  Widget get _sp8  => const SizedBox(height: 8);
  Widget get _sp10 => const SizedBox(height: 10);
  Widget get _sp12 => const SizedBox(height: 12);
  Widget get _sp14 => const SizedBox(height: 14);
  Widget get _sp16 => const SizedBox(height: 16);

  Widget _lbl(String t) => Text(t, style: TextStyle(fontSize: 11,
      fontWeight: FontWeight.w600, color: AppTheme.textSecondary, letterSpacing: 0.3));

  InputDecoration _dec(String hint, {Widget? suffix, bool disabled = false, String? counterText}) =>
      InputDecoration(
        hintText: hint, hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
        suffixIcon: suffix, counterText: counterText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        filled: true, fillColor: disabled ? AppTheme.surfaceAlt : Colors.white,
      );

  Widget _tf(String label, String hint, TextEditingController c, {
    String? suffix, TextInputType kb = TextInputType.text,
    bool enabled = true, ValueChanged<String>? onChange,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _lbl(label), _sp4,
    SizedBox(height: 40, child: TextField(
      controller: c, enabled: enabled, keyboardType: kb, onChanged: onChange,
      decoration: _dec(hint, suffix: suffix != null
          ? Text(suffix, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)) : null,
          disabled: !enabled),
      style: const TextStyle(fontSize: 14),
    )),
  ]);

  Widget _tfHelper(String label, String hint, TextEditingController c, {
    required String helper, String? suffix,
    TextInputType kb = TextInputType.text, ValueChanged<String>? onChange,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _tf(label, hint, c, suffix: suffix, kb: kb, onChange: onChange),
    Padding(padding: const EdgeInsets.only(top: 3),
        child: Text(helper, style: TextStyle(fontSize: 10, color: AppTheme.textMuted))),
  ]);

  Widget _dd(String label, String value, List<String> items, ValueChanged<String?> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lbl(label), _sp4,
        SizedBox(height: 40, child: DropdownButtonFormField<String>(
          value: items.contains(value) ? value : items.first,
          decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              filled: true, fillColor: Colors.white),
          style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
          items: items.map((i) => DropdownMenuItem(value: i,
              child: Text(i, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        )),
      ]);

  Widget _toggle(String label, String subtitle, bool value, ValueChanged<bool> onChanged,
      {bool primary = false}) {
    final col = primary ? AppTheme.primary : AppTheme.secondary;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: value ? col.withOpacity(0.06) : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: value ? col.withOpacity(0.25) : AppTheme.border),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ])),
          Switch(value: value, activeColor: col, onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ]),
      ),
    );
  }

  Widget _calcBox(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(icon, size: 12, color: AppTheme.textMuted), const SizedBox(width: 5),
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            overflow: TextOverflow.ellipsis, maxLines: 1)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(3)),
          child: Text('Auto', style: TextStyle(fontSize: 9, color: AppTheme.textMuted,
              fontWeight: FontWeight.w500)),
        ),
      ]),
      const SizedBox(height: 4),
      Text(value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
              color: value == '—' ? AppTheme.textMuted : AppTheme.primary),
          overflow: TextOverflow.ellipsis, maxLines: 1),
    ]),
  );

  Widget _chip(String label, double area, Color color) {
    final dark = color == const Color(0xFF3B82F6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: dark ? Colors.white : AppTheme.primary)),
        const SizedBox(height: 4),
        Text(area > 0 ? '${area.toStringAsFixed(0)}\nsf' : '—', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: dark ? Colors.white : AppTheme.textPrimary)),
      ]),
    );
  }

  Widget _miniCalc(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.08), borderRadius: BorderRadius.circular(5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 9, color: AppTheme.textMuted,
            fontWeight: FontWeight.w600, letterSpacing: 0.4)),
        Text(value, style: TextStyle(fontSize: 12, color: AppTheme.accent, fontWeight: FontWeight.w700)),
      ]),
    ),
  );

  Widget _info(String msg, {Color? color}) {
    final c = color ?? AppTheme.warning;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, color: c, size: 14), const SizedBox(width: 7),
        Expanded(child: Text(msg, style: TextStyle(fontSize: 11, color: c.withOpacity(0.9)))),
      ]),
    );
  }

  Widget _impactRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(children: [
      Icon(icon, size: 13, color: AppTheme.primary.withOpacity(0.6)), const SizedBox(width: 6),
      Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
      Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
          color: value == '—' ? AppTheme.textMuted : AppTheme.textPrimary)),
    ]),
  );

  Widget _zipRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(children: [
      Icon(icon, size: 13, color: AppTheme.accent), const SizedBox(width: 6),
      Text('$label: ', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      Expanded(child: Text(value, style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
    ]),
  );
}

// ─── Shape diagram painter ────────────────────────────────────────────────────
class _ShapeDiagramPainter extends CustomPainter {
  final String shapeType;
  const _ShapeDiagramPainter(this.shapeType);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2563EB).withOpacity(0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final labelStyle = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF2563EB).withOpacity(0.85),
    );

    final w = size.width;
    final h = size.height;

    switch (shapeType) {
      case 'Rectangle':
      case 'Square':
        // Simple rectangle
        final r = Rect.fromLTWH(4, 4, w - 8, h - 8);
        canvas.drawRect(r, paint);
        _label(canvas, labelStyle, 'E1', Offset(w * 0.5, h - 2), center: true);
        _label(canvas, labelStyle, 'E2', Offset(w - 2,   h * 0.5), center: true);
        _label(canvas, labelStyle, 'E3', Offset(w * 0.5, 4),       center: true);
        _label(canvas, labelStyle, 'E4', Offset(2,        h * 0.5), center: true);
        break;

      case 'L-Shape':
        // Notch at top-right. Points (origin = bottom-left):
        // E1=bottom, E2=right full height, E3=notch top, E4=notch left wall,
        // E5=horizontal step, E6=left side
        //
        //        ┌──E3──┐
        //        E4     E2
        //  ┌─E5──┘       │
        //  E6             │
        //  └─────E1───────┘
        //
        // Proportions: notch occupies right 35% of width, top 45% of height
        final double nW = w * 0.35;  // notch width
        final double nH = h * 0.45;  // notch height (step up)
        final double bL = 4.0;       // border left
        final double bB = h - 4;     // border bottom
        final double bR = w - 4;     // border right

        final path = Path()
          ..moveTo(bL, bB)                        // bottom-left
          ..lineTo(bR, bB)                        // E1: bottom →
          ..lineTo(bR, 4)                         // E2: right side ↑
          ..lineTo(bR - nW, 4)                    // E3: notch top ←
          ..lineTo(bR - nW, 4 + nH)              // E4: notch left wall ↓
          ..lineTo(bL + (w - nW) * 0.35, 4 + nH)// E5: step ←
          ..lineTo(bL, bB)                        // E6: left side ↓ (closes)
          ..close();
        canvas.drawPath(path, paint);

        // Labels
        _label(canvas, labelStyle, 'E1', Offset(w * 0.4,  bB - 1),       center: true);
        _label(canvas, labelStyle, 'E2', Offset(bR + 1,   h * 0.35),     center: false);
        _label(canvas, labelStyle, 'E3', Offset(bR - nW * 0.5, 3),       center: true);
        _label(canvas, labelStyle, 'E4', Offset(bR - nW - 1, 4 + nH * 0.5), center: false, right: true);
        _label(canvas, labelStyle, 'E5', Offset(bL + (w - nW) * 0.15, 4 + nH - 1), center: true);
        _label(canvas, labelStyle, 'E6', Offset(bL + 1,  h * 0.75),      center: false);
        break;

      case 'T-Shape':
        // Stem at bottom, bar across top
        final double sW = w * 0.3;   // stem width
        final double sX = (w - sW) / 2; // stem left x
        final double barH = h * 0.45;

        final path = Path()
          ..moveTo(sX + sW * 0.5 - sW * 0.5, h - 4)  // stem bottom-left
          ..lineTo(sX + sW, h - 4)                     // E1 bottom
          ..lineTo(sX + sW, 4 + barH)                  // E2 stem right
          ..lineTo(w - 4,   4 + barH)                  // E3 right step
          ..lineTo(w - 4,   4)                          // E4 bar right
          ..lineTo(4,       4)                          // E5 bar top
          ..lineTo(4,       4 + barH)                  // E6 bar left
          ..lineTo(sX,      4 + barH)                  // E7 left step
          ..lineTo(sX,      h - 4)                     // E8 stem left
          ..close();
        canvas.drawPath(path, paint);

        _label(canvas, labelStyle, 'E1', Offset(w * 0.5, h - 2),         center: true);
        _label(canvas, labelStyle, 'E2', Offset(sX + sW + 1, h * 0.75), center: false);
        _label(canvas, labelStyle, 'E3', Offset(w * 0.8, 4 + barH - 1), center: true);
        _label(canvas, labelStyle, 'E4', Offset(w - 3,   h * 0.2),       center: false, right: true);
        _label(canvas, labelStyle, 'E5', Offset(w * 0.5, 3),             center: true);
        _label(canvas, labelStyle, 'E6', Offset(5,        h * 0.2),      center: false);
        _label(canvas, labelStyle, 'E7', Offset(w * 0.2, 4 + barH - 1), center: true);
        _label(canvas, labelStyle, 'E8', Offset(sX - 1,  h * 0.75),     center: false, right: true);
        break;

      case 'U-Shape':
        // Open at bottom-center
        final double uW = w * 0.3;
        final double uX = (w - uW) / 2;
        final double uH = h * 0.5;

        final path = Path()
          ..moveTo(4, h - 4)
          ..lineTo(uX, h - 4)                  // E1 bottom-left
          ..lineTo(uX, 4 + uH)                 // E2 inner-left up
          ..lineTo(uX + uW, 4 + uH)            // ... inner bottom
          ..lineTo(uX + uW, h - 4)             // E3
          ..lineTo(w - 4, h - 4)               // E4
          ..lineTo(w - 4, 4)                   // E5 right
          ..lineTo(4, 4)                        // E6 top
          ..lineTo(4, h - 4)                    // E7 left
          ..close();
        canvas.drawPath(path, paint);

        _label(canvas, labelStyle, 'E1', Offset(uX * 0.5, h - 2),        center: true);
        _label(canvas, labelStyle, 'E2', Offset(uX + 1,   h * 0.75),     center: false);
        _label(canvas, labelStyle, 'E3', Offset(uX + uW * 0.5, 4 + uH - 1), center: true);
        _label(canvas, labelStyle, 'E4', Offset((uX + uW + w) * 0.5, h - 2), center: true);
        _label(canvas, labelStyle, 'E5', Offset(w - 3,   h * 0.5),       center: false, right: true);
        _label(canvas, labelStyle, 'E6', Offset(w * 0.5, 3),             center: true);
        _label(canvas, labelStyle, 'E7', Offset(5,        h * 0.5),      center: false);
        _label(canvas, labelStyle, 'E8', Offset(uX + uW + 1, h * 0.75), center: false);
        break;

      default:
        canvas.drawRect(Rect.fromLTWH(4, 4, w - 8, h - 8), paint);
    }
  }

  void _label(Canvas canvas, TextStyle style, String text, Offset pos,
      {bool center = false, bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    double dx = pos.dx;
    double dy = pos.dy - tp.height / 2;
    if (center) dx -= tp.width / 2;
    if (right)  dx -= tp.width;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_ShapeDiagramPainter old) => old.shapeType != shapeType;
}
