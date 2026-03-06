/// lib/services/serialization.dart
///
/// Converts every ProTPO model to/from plain Map<String, dynamic>
/// suitable for Firestore storage.
///
/// Design rules:
///   - No model files are modified.
///   - All toJson/fromJson logic lives here as static extension-style helpers.
///   - Null-safe: every fromJson uses fallbacks so loading old documents
///     never throws.
///   - DateTime stored as ISO-8601 string.
///   - Enums stored as their string value.

import '../models/project_info.dart';
import '../models/roof_geometry.dart';
import '../models/insulation_system.dart';
import '../models/section_models.dart';
import '../models/system_specs.dart';
import '../models/building_state.dart';
import '../models/estimator_state.dart';
import 'package:uuid/uuid.dart';

// ─── TOP-LEVEL ENTRY POINTS ──────────────────────────────────────────────────

/// Serialise the full [EstimatorState] to a Firestore-ready map.
/// Caller should add `projectId` as the document ID separately.
Map<String, dynamic> stateToJson(EstimatorState state, String projectId) {
  return {
    'projectId':   projectId,
    'savedAt':     DateTime.now().toIso8601String(),
    'schemaVersion': 1,
    'projectInfo': _projectInfoToJson(state.projectInfo),
    'buildings':   state.buildings.map(_buildingStateToJson).toList(),
    'activeBuildingIndex': state.activeBuildingIndex,
  };
}

/// Deserialise a Firestore document map back to [EstimatorState].
/// Returns null if the document is structurally invalid.
EstimatorState? stateFromJson(Map<String, dynamic> json) {
  try {
    final info      = _projectInfoFromJson(json['projectInfo'] as Map? ?? {});
    final buildings = (json['buildings'] as List? ?? [])
        .map((b) => _buildingStateFromJson(b as Map<String, dynamic>))
        .toList();
    final activeIdx = (json['activeBuildingIndex'] as int?) ?? 0;

    if (buildings.isEmpty) return null;

    return EstimatorState(
      projectInfo:          info,
      buildings:            buildings,
      activeBuildingIndex:  activeIdx.clamp(0, buildings.length - 1),
    );
  } catch (e) {
    return null;
  }
}

// ─── PROJECT INFO ─────────────────────────────────────────────────────────────

Map<String, dynamic> _projectInfoToJson(ProjectInfo p) => {
  'projectName':    p.projectName,
  'projectAddress': p.projectAddress,
  'zipCode':        p.zipCode,
  'customerName':   p.customerName,
  'estimatorName':  p.estimatorName,
  'estimateDate':   p.estimateDate.toIso8601String(),
  'warrantyYears':  p.warrantyYears,
  'climateZone':    p.climateZone,
  'designWindSpeed':p.designWindSpeed,
  'requiredRValue': p.requiredRValue,
  'stateCounty':    p.stateCounty,
  'wasteMaterial':  p.wasteMaterial,
  'wasteMetal':     p.wasteMetal,
  'wasteAccessory': p.wasteAccessory,
};

ProjectInfo _projectInfoFromJson(Map j) => ProjectInfo(
  projectName:    _s(j['projectName']),
  projectAddress: _s(j['projectAddress']),
  zipCode:        _s(j['zipCode']),
  customerName:   _s(j['customerName']),
  estimatorName:  _s(j['estimatorName']),
  estimateDate:   _date(j['estimateDate']),
  warrantyYears:  _i(j['warrantyYears'], 20),
  climateZone:    j['climateZone'] as String?,
  designWindSpeed:j['designWindSpeed'] as String?,
  requiredRValue: (j['requiredRValue'] as num?)?.toDouble(),
  stateCounty:    j['stateCounty'] as String?,
  wasteMaterial:  _d(j['wasteMaterial'], 0.10),
  wasteMetal:     _d(j['wasteMetal'], 0.05),
  wasteAccessory: _d(j['wasteAccessory'], 0.05),
);

// ─── BUILDING STATE ───────────────────────────────────────────────────────────

Map<String, dynamic> _buildingStateToJson(BuildingState b) => {
  'id':               b.id,
  'buildingName':     b.buildingName,
  'roofGeometry':     _roofGeometryToJson(b.roofGeometry),
  'systemSpecs':      _systemSpecsToJson(b.systemSpecs),
  'insulationSystem': _insulationSystemToJson(b.insulationSystem),
  'membraneSystem':   _membraneSystemToJson(b.membraneSystem),
  'parapetWalls':     _parapetWallsToJson(b.parapetWalls),
  'penetrations':     _penetrationsToJson(b.penetrations),
  'metalScope':       _metalScopeToJson(b.metalScope),
  'sowOverrides':     b.sowOverrides,
};

BuildingState _buildingStateFromJson(Map<String, dynamic> j) => BuildingState(
  id:               j['id'] as String? ?? const Uuid().v4(),
  buildingName:     _s(j['buildingName'], 'Building'),
  roofGeometry:     _roofGeometryFromJson(j['roofGeometry'] as Map? ?? {}),
  systemSpecs:      _systemSpecsFromJson(j['systemSpecs'] as Map? ?? {}),
  insulationSystem: _insulationSystemFromJson(j['insulationSystem'] as Map? ?? {}),
  membraneSystem:   _membraneSystemFromJson(j['membraneSystem'] as Map? ?? {}),
  parapetWalls:     _parapetWallsFromJson(j['parapetWalls'] as Map? ?? {}),
  penetrations:     _penetrationsFromJson(j['penetrations'] as Map? ?? {}),
  metalScope:       _metalScopeFromJson(j['metalScope'] as Map? ?? {}),
  sowOverrides:     Map<String, String>.from(j['sowOverrides'] as Map? ?? {}),
);

// ─── ROOF GEOMETRY ────────────────────────────────────────────────────────────

Map<String, dynamic> _roofGeometryToJson(RoofGeometry g) => {
  'shapes':         g.shapes.map(_roofShapeToJson).toList(),
  'buildingHeight': g.buildingHeight,
  'roofSlope':      g.roofSlope,
  'customSlope':    g.customSlope,
  'drainLocations': g.drainLocations.map(_drainToJson).toList(),
  'totalPerimeterOverride': g.totalPerimeterOverride,
  'totalAreaOverride':      g.totalAreaOverride,
  'perimeterCorners': g.perimeterCorners,
  'insideCorners':    g.insideCorners,
  'outsideCorners':   g.outsideCorners,
  'windZones':        _windZonesToJson(g.windZones),
};

RoofGeometry _roofGeometryFromJson(Map j) => RoofGeometry(
  shapes:         (j['shapes'] as List? ?? [])
      .map((s) => _roofShapeFromJson(s as Map<String, dynamic>))
      .toList(),
  buildingHeight: _d(j['buildingHeight'], 0.0),
  roofSlope:      _s(j['roofSlope'], 'Flat'),
  customSlope:    _d(j['customSlope'], 0.0),
  drainLocations: (j['drainLocations'] as List? ?? [])
      .map((d) => _drainFromJson(d as Map<String, dynamic>))
      .toList(),
  totalPerimeterOverride: (j['totalPerimeterOverride'] as num?)?.toDouble(),
  totalAreaOverride:      (j['totalAreaOverride'] as num?)?.toDouble(),
  perimeterCorners: _i(j['perimeterCorners'], 0),
  insideCorners:    _i(j['insideCorners'], 0),
  outsideCorners:   _i(j['outsideCorners'], 0),
  windZones:        _windZonesFromJson(j['windZones'] as Map? ?? {}),
);

Map<String, dynamic> _roofShapeToJson(RoofShape s) => {
  'shapeIndex':  s.shapeIndex,
  'shapeType':   s.shapeType,
  'operation':   s.operation,
  'edgeLengths': s.edgeLengths,
};

RoofShape _roofShapeFromJson(Map<String, dynamic> j) => RoofShape(
  shapeIndex:  _i(j['shapeIndex'], 1),
  shapeType:   _s(j['shapeType'], 'Rectangle'),
  operation:   _s(j['operation'], 'Add'),
  edgeLengths: (j['edgeLengths'] as List? ?? [])
      .map((e) => (e as num).toDouble()).toList(),
);

Map<String, dynamic> _drainToJson(DrainLocation d) => {'x': d.x, 'y': d.y};
DrainLocation _drainFromJson(Map<String, dynamic> j) =>
    DrainLocation(x: _d(j['x'], 0.0), y: _d(j['y'], 0.0));

Map<String, dynamic> _windZonesToJson(WindZones w) => {
  'cornerZoneWidth':    w.cornerZoneWidth,
  'perimeterZoneWidth': w.perimeterZoneWidth,
  'cornerZoneArea':     w.cornerZoneArea,
  'perimeterZoneArea':  w.perimeterZoneArea,
  'fieldZoneArea':      w.fieldZoneArea,
};

WindZones _windZonesFromJson(Map j) => WindZones(
  cornerZoneWidth:    _d(j['cornerZoneWidth'], 0.0),
  perimeterZoneWidth: _d(j['perimeterZoneWidth'], 0.0),
  cornerZoneArea:     _d(j['cornerZoneArea'], 0.0),
  perimeterZoneArea:  _d(j['perimeterZoneArea'], 0.0),
  fieldZoneArea:      _d(j['fieldZoneArea'], 0.0),
);

// ─── SYSTEM SPECS ─────────────────────────────────────────────────────────────

Map<String, dynamic> _systemSpecsToJson(SystemSpecs s) => {
  'projectType':      s.projectType,
  'deckType':         s.deckType,
  'vaporRetarder':    s.vaporRetarder,
  'existingRoofType': s.existingRoofType,
  'existingLayers':   s.existingLayers,
  'moistureScanRequired': s.moistureScanRequired,
};

SystemSpecs _systemSpecsFromJson(Map j) => SystemSpecs(
  projectType:      _s(j['projectType'], 'New Construction'),
  deckType:         _s(j['deckType'], 'Metal'),
  vaporRetarder:    _s(j['vaporRetarder'], 'None'),
  existingRoofType: _s(j['existingRoofType']),
  existingLayers:   _i(j['existingLayers'], 0),
  moistureScanRequired: j['moistureScanRequired'] as bool? ?? false,
);

// ─── INSULATION SYSTEM ────────────────────────────────────────────────────────

Map<String, dynamic> _insulationSystemToJson(InsulationSystem ins) => {
  'numberOfLayers':       ins.numberOfLayers,
  'layer1':               _insLayerToJson(ins.layer1),
  'layer2':               ins.layer2 != null ? _insLayerToJson(ins.layer2!) : null,
  'hasTaperedInsulation': ins.hasTaperedInsulation,
  'tapered':              ins.tapered != null ? _taperedToJson(ins.tapered!) : null,
  'hasCoverBoard':        ins.hasCoverBoard,
  'coverBoard':           ins.coverBoard != null ? _coverBoardToJson(ins.coverBoard!) : null,
};

InsulationSystem _insulationSystemFromJson(Map j) {
  final layer2json = j['layer2'];
  final taperedJson = j['tapered'];
  final cbJson = j['coverBoard'];
  return InsulationSystem(
    numberOfLayers:       _i(j['numberOfLayers'], 1),
    layer1:               _insLayerFromJson(j['layer1'] as Map? ?? {}),
    layer2:               layer2json != null ? _insLayerFromJson(layer2json as Map) : null,
    hasTaperedInsulation: j['hasTaperedInsulation'] as bool? ?? false,
    tapered:              taperedJson != null ? _taperedFromJson(taperedJson as Map) : null,
    hasCoverBoard:        j['hasCoverBoard'] as bool? ?? false,
    coverBoard:           cbJson != null ? _coverBoardFromJson(cbJson as Map) : null,
  );
}

Map<String, dynamic> _insLayerToJson(InsulationLayer l) => {
  'type':             l.type,
  'thickness':        l.thickness,
  'attachmentMethod': l.attachmentMethod,
};

InsulationLayer _insLayerFromJson(Map j) => InsulationLayer(
  type:             _s(j['type'], 'Polyiso'),
  thickness:        _d(j['thickness'], 0.0),
  attachmentMethod: _s(j['attachmentMethod'], 'Mechanically Attached'),
);

Map<String, dynamic> _taperedToJson(TaperedInsulation t) => {
  'boardType':           t.boardType,
  'taperSlope':          t.taperSlope,
  'minThicknessAtDrain': t.minThicknessAtDrain,
  'maxThickness':        t.maxThickness,
  'systemArea':          t.systemArea,
};

TaperedInsulation _taperedFromJson(Map j) => TaperedInsulation(
  boardType:           _s(j['boardType']),
  taperSlope:          _s(j['taperSlope'], '1/4:12'),
  minThicknessAtDrain: _d(j['minThicknessAtDrain'], 0.5),
  maxThickness:        _d(j['maxThickness'], 0.0),
  systemArea:          _d(j['systemArea'], 0.0),
);

Map<String, dynamic> _coverBoardToJson(CoverBoard cb) => {
  'type':             cb.type,
  'thickness':        cb.thickness,
  'attachmentMethod': cb.attachmentMethod,
};

CoverBoard _coverBoardFromJson(Map j) => CoverBoard(
  type:             _s(j['type'], 'HD Polyiso'),
  thickness:        _d(j['thickness'], 0.5),
  attachmentMethod: _s(j['attachmentMethod'], 'Adhered'),
);

// ─── MEMBRANE ─────────────────────────────────────────────────────────────────

Map<String, dynamic> _membraneSystemToJson(MembraneSystem m) => {
  'membraneType':      m.membraneType,
  'thickness':         m.thickness,
  'color':             m.color,
  'manufacturer':      m.manufacturer,
  'fieldAttachment':   m.fieldAttachment,
  'rollWidth':         m.rollWidth,
  'perimeterRollWidth':m.perimeterRollWidth,
  'seamType':          m.seamType,
};

MembraneSystem _membraneSystemFromJson(Map j) => MembraneSystem(
  membraneType:       _s(j['membraneType'], 'TPO'),
  thickness:          _s(j['thickness'], '60 mil'),
  color:              _s(j['color'], 'White'),
  manufacturer:       _s(j['manufacturer'], 'Versico'),
  fieldAttachment:    _s(j['fieldAttachment'], 'Mechanically Attached'),
  rollWidth:          _s(j['rollWidth'], "10'"),
  perimeterRollWidth: _s(j['perimeterRollWidth'], "6'"),
  seamType:           _s(j['seamType'], 'Hot Air Welded'),
);

// ─── PARAPET WALLS ────────────────────────────────────────────────────────────

Map<String, dynamic> _parapetWallsToJson(ParapetWalls p) => {
  'hasParapetWalls':         p.hasParapetWalls,
  'parapetHeight':           p.parapetHeight,
  'parapetTotalLF':          p.parapetTotalLF,
  'wallType':                p.wallType,
  'terminationBarLFOverride':p.terminationBarLFOverride,
  'terminationType':         p.terminationType,
};

ParapetWalls _parapetWallsFromJson(Map j) => ParapetWalls(
  hasParapetWalls:          j['hasParapetWalls'] as bool? ?? false,
  parapetHeight:            _d(j['parapetHeight'], 0.0),
  parapetTotalLF:           _d(j['parapetTotalLF'], 0.0),
  wallType:                 _s(j['wallType'], 'Concrete Block'),
  terminationBarLFOverride: (j['terminationBarLFOverride'] as num?)?.toDouble(),
  terminationType:          _s(j['terminationType'], 'Termination Bar'),
);

// ─── PENETRATIONS ─────────────────────────────────────────────────────────────

Map<String, dynamic> _penetrationsToJson(Penetrations p) => {
  'rtuTotalLF':       p.rtuTotalLF,
  'rtuDetails':       p.rtuDetails.map(_rtuDetailToJson).toList(),
  'drainType':        p.drainType,
  'smallPipeCount':   p.smallPipeCount,
  'largePipeCount':   p.largePipeCount,
  'skylightCount':    p.skylightCount,
  'scupperCount':     p.scupperCount,
  'expansionJointLF': p.expansionJointLF,
  'pitchPanCount':    p.pitchPanCount,
};

Penetrations _penetrationsFromJson(Map j) => Penetrations(
  rtuTotalLF:       _d(j['rtuTotalLF'], 0.0),
  rtuDetails:       (j['rtuDetails'] as List? ?? [])
      .map((r) => _rtuDetailFromJson(r as Map<String, dynamic>))
      .toList(),
  drainType:        _s(j['drainType'], 'Standard'),
  smallPipeCount:   _i(j['smallPipeCount'], 0),
  largePipeCount:   _i(j['largePipeCount'], 0),
  skylightCount:    _i(j['skylightCount'], 0),
  scupperCount:     _i(j['scupperCount'], 0),
  expansionJointLF: _d(j['expansionJointLF'], 0.0),
  pitchPanCount:    _i(j['pitchPanCount'], 0),
);

Map<String, dynamic> _rtuDetailToJson(RTUDetail r) =>
    {'length': r.length, 'width': r.width, 'height': r.height};

RTUDetail _rtuDetailFromJson(Map<String, dynamic> j) => RTUDetail(
  length: _d(j['length'], 0.0),
  width:  _d(j['width'], 0.0),
  height: _d(j['height'], 0.0),
);

// ─── METAL SCOPE ─────────────────────────────────────────────────────────────

Map<String, dynamic> _metalScopeToJson(MetalScope m) => {
  'copingWidth':      m.copingWidth,
  'copingLF':         m.copingLF,
  'wallFlashingLF':   m.wallFlashingLF,
  'dripEdgeLF':       m.dripEdgeLF,
  'otherEdgeMetalLF': m.otherEdgeMetalLF,
  'edgeMetalType':    m.edgeMetalType,
  'gutterSize':       m.gutterSize,
  'gutterLF':         m.gutterLF,
  'downspoutCount':   m.downspoutCount,
};

MetalScope _metalScopeFromJson(Map j) => MetalScope(
  copingWidth:      _s(j['copingWidth'], '12"'),
  copingLF:         _d(j['copingLF'], 0.0),
  // Migrate old single edgeMetalLF into dripEdgeLF if new fields absent
  wallFlashingLF:   _d(j['wallFlashingLF'], 0.0),
  dripEdgeLF:       _d(j['dripEdgeLF'] ?? j['edgeMetalLF'], 0.0),
  otherEdgeMetalLF: _d(j['otherEdgeMetalLF'], 0.0),
  edgeMetalType:    _s(j['edgeMetalType'], 'ES-1'),
  gutterSize:       _s(j['gutterSize'], '6"'),
  gutterLF:         _d(j['gutterLF'], 0.0),
  downspoutCount:   _i(j['downspoutCount'], 0),
);

// ─── PRIMITIVE HELPERS ────────────────────────────────────────────────────────

String _s(dynamic v, [String fallback = '']) =>
    v is String ? v : fallback;

double _d(dynamic v, [double fallback = 0.0]) =>
    v is num ? v.toDouble() : fallback;

int _i(dynamic v, [int fallback = 0]) =>
    v is int ? v : (v is num ? v.toInt() : fallback);

DateTime _date(dynamic v) {
  if (v is String) {
    try { return DateTime.parse(v); } catch (_) {}
  }
  return DateTime.now();
}
