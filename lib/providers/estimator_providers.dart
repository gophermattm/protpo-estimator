/// lib/providers/estimator_providers.dart
///
/// All Riverpod providers for the ProTPO estimator.
///
/// Multi-building architecture:
///   - One root StateNotifierProvider owns the full EstimatorState tree.
///   - activeBuildingProvider exposes the currently-selected BuildingState.
///   - All section providers (roofGeometryProvider, etc.) select from
///     activeBuilding — widgets are unaware of the building list.
///   - The notifier has building CRUD methods (add, remove, rename, setActive)
///     plus all per-section update methods that operate on the active building.
///
/// Widgets always read/write the active building via section providers.
/// Only the building tab bar widget needs the full buildings list.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/estimator_state.dart';
import '../models/building_state.dart';
import '../models/project_info.dart';
import '../models/roof_geometry.dart';
import '../models/system_specs.dart';
import '../models/drainage_zone.dart';
import '../models/insulation_system.dart';
import '../models/section_models.dart';
import 'dart:ui';
import '../services/r_value_calculator.dart';
import '../services/bom_calculator.dart';
import '../services/validation_engine.dart';
import '../services/qxo_pricing_service.dart';
import '../services/drain_distance_calculator.dart';
import '../services/board_schedule_calculator.dart';
import '../services/watershed_calculator.dart';
import '../models/labor_models.dart';

// ─── ROOT PROVIDER ────────────────────────────────────────────────────────────

final estimatorProvider =
    StateNotifierProvider<EstimatorNotifier, EstimatorState>(
  (ref) => EstimatorNotifier(),
);

// ─── PROJECT-LEVEL PROVIDERS ──────────────────────────────────────────────────

final projectInfoProvider = Provider<ProjectInfo>(
  (ref) => ref.watch(estimatorProvider.select((s) => s.projectInfo)),
);

/// The full list of buildings — used only by the building tab bar widget.
final buildingsProvider = Provider<List<BuildingState>>(
  (ref) => ref.watch(estimatorProvider.select((s) => s.buildings)),
);

/// Index of the currently active building tab.
final activeBuildingIndexProvider = Provider<int>(
  (ref) => ref.watch(estimatorProvider.select((s) => s.activeBuildingIndex)),
);

// ─── ACTIVE BUILDING PROVIDER ─────────────────────────────────────────────────

/// The building currently being edited. All section providers derive from this.
final activeBuildingProvider = Provider<BuildingState>(
  (ref) => ref.watch(estimatorProvider.select((s) => s.activeBuilding)),
);

// ─── SECTION SELECTOR PROVIDERS (all read from active building) ───────────────
// These use select() so widgets only rebuild when their specific section changes.

final roofGeometryProvider = Provider<RoofGeometry>(
  (ref) =>
      ref.watch(estimatorProvider.select((s) => s.activeBuilding.roofGeometry)),
);

final systemSpecsProvider = Provider<SystemSpecs>(
  (ref) =>
      ref.watch(estimatorProvider.select((s) => s.activeBuilding.systemSpecs)),
);

final insulationSystemProvider = Provider<InsulationSystem>(
  (ref) => ref
      .watch(estimatorProvider.select((s) => s.activeBuilding.insulationSystem)),
);

final membraneSystemProvider = Provider<MembraneSystem>(
  (ref) => ref
      .watch(estimatorProvider.select((s) => s.activeBuilding.membraneSystem)),
);

final parapetWallsProvider = Provider<ParapetWalls>(
  (ref) =>
      ref.watch(estimatorProvider.select((s) => s.activeBuilding.parapetWalls)),
);

final penetrationsProvider = Provider<Penetrations>(
  (ref) =>
      ref.watch(estimatorProvider.select((s) => s.activeBuilding.penetrations)),
);

final metalScopeProvider = Provider<MetalScope>(
  (ref) =>
      ref.watch(estimatorProvider.select((s) => s.activeBuilding.metalScope)),
);


// ── VALIDATION ENGINE PROVIDER ─────────────────────────────────────────────────

final validationResultProvider = Provider<ValidationResult>((ref) {
  final info = ref.watch(projectInfoProvider);
  final geo = ref.watch(roofGeometryProvider);
  final specs = ref.watch(systemSpecsProvider);
  final insul = ref.watch(insulationSystemProvider);
  final membrane = ref.watch(membraneSystemProvider);
  final parapet = ref.watch(parapetWallsProvider);
  final pen = ref.watch(penetrationsProvider);
  final metal = ref.watch(metalScopeProvider);
  final bom = ref.watch(bomProvider);

  return ValidationEngine.validate(
    projectInfo: info, geometry: geo, systemSpecs: specs,
    insulation: insul, membrane: membrane, parapet: parapet,
    penetrations: pen, metalScope: metal, bom: bom,
  );
});

// ── SOW overrides provider ─────────────────────────────────────────────────────
final sowOverridesProvider = Provider<Map<String, String>>((ref) =>
    ref.watch(activeBuildingProvider).sowOverrides);

// ── Sub instructions overrides provider ──────────────────────────────────────
final subInstructionOverridesProvider =
    StateProvider<Map<String, String>>((ref) => {});
// ─── CALCULATION PROVIDERS ────────────────────────────────────────────────────

/// R-value result for the active building.
final rValueResultProvider = Provider<RValueResult?>((ref) {
  final insulation = ref.watch(insulationSystemProvider);
  final projectInfo = ref.watch(projectInfoProvider);
  final boardSchedule = ref.watch(boardScheduleProvider);

  // No flat insulation layers and no tapered — nothing to calculate
  final hasLayers = insulation.numberOfLayers >= 1 && insulation.layer1.thickness > 0;
  final hasTapered = insulation.hasTaper && insulation.taperDefaults != null;
  final hasCB = insulation.hasCoverBoard && insulation.coverBoard != null;
  if (!hasLayers && !hasTapered && !hasCB) return null;

  return RValueCalculator.calculate(
    layer1: hasLayers
        ? InsulationLayerInput(
            materialType: insulation.layer1.type,
            thickness: insulation.layer1.thickness,
          )
        : InsulationLayerInput(materialType: 'None', thickness: 0),
    layer2: insulation.numberOfLayers == 2 && insulation.layer2 != null
        ? InsulationLayerInput(
            materialType: insulation.layer2!.type,
            thickness: insulation.layer2!.thickness,
          )
        : null,
    tapered: insulation.hasTaper && insulation.taperDefaults != null
        ? TaperedInsulationInput(
            materialType: 'Polyiso',
            minThicknessAtDrain: insulation.taperDefaults!.minThickness,
            maxThickness: boardSchedule?.maxThicknessAtRidge ?? 0,
          )
        : null,
    coverBoard: insulation.hasCoverBoard && insulation.coverBoard != null
        ? CoverBoardInput(
            materialType: insulation.coverBoard!.type,
            thickness: insulation.coverBoard!.thickness,
          )
        : null,
    requiredRValue: projectInfo.requiredRValue,
  );
});

/// R-value validation messages for the active building.
final rValueValidationProvider = Provider<List<ValidationMessage>>((ref) {
  final insulation = ref.watch(insulationSystemProvider);
  final projectInfo = ref.watch(projectInfoProvider);
  final boardSchedule = ref.watch(boardScheduleProvider);

  return RValueCalculator.validate(
    layer1: insulation.numberOfLayers >= 1
        ? InsulationLayerInput(
            materialType: insulation.layer1.type,
            thickness: insulation.layer1.thickness,
          )
        : InsulationLayerInput(materialType: 'None', thickness: 0),
    layer2: insulation.numberOfLayers == 2 && insulation.layer2 != null
        ? InsulationLayerInput(
            materialType: insulation.layer2!.type,
            thickness: insulation.layer2!.thickness,
          )
        : null,
    tapered: insulation.hasTaper && insulation.taperDefaults != null
        ? TaperedInsulationInput(
            materialType: 'Polyiso',
            minThicknessAtDrain: insulation.taperDefaults!.minThickness,
            maxThickness: boardSchedule?.maxThicknessAtRidge ?? 0,
          )
        : null,
    coverBoard: insulation.hasCoverBoard && insulation.coverBoard != null
        ? CoverBoardInput(
            materialType: insulation.coverBoard!.type,
            thickness: insulation.coverBoard!.thickness,
          )
        : null,
    requiredRValue: projectInfo.requiredRValue,
  );
});

/// Board schedule result for the active building's tapered insulation.
/// Returns null when taper is disabled or no drains are placed.
final boardScheduleProvider = Provider<BoardScheduleResult?>((ref) {
  final insulation = ref.watch(insulationSystemProvider);
  final geo = ref.watch(roofGeometryProvider);
  return _computeBoardSchedule(geo, insulation);
});

/// Watershed zones for the active building — one per drain/scupper when
/// tapered insulation is active. Used by the UI to show per-zone breakdown.
final watershedZonesProvider = Provider<List<ZoneWatershed>>((ref) {
  final insulation = ref.watch(insulationSystemProvider);
  final geo = ref.watch(roofGeometryProvider);

  if (!insulation.hasTaper) return [];
  if (geo.drainLocations.isEmpty && geo.scupperLocations.isEmpty) return [];

  final primaryShape = geo.shapes.isNotEmpty ? geo.shapes.first : null;
  if (primaryShape == null) return [];
  final vertices = _buildPolygonVertices(primaryShape);
  if (vertices.isEmpty) return [];

  final lowPoints = <Offset>[
    ...geo.drainLocations.map((d) => Offset(d.x, d.y)),
    ...geo.scupperLocations.map((s) => scupperWorldPosition(s, vertices)),
  ];

  return WatershedCalculator.computeZones(
    polygonVertices: vertices,
    lowPoints: lowPoints,
    totalPolygonArea: geo.totalArea,
  );
});

/// Cross-section validation for the active building.
final crossSectionValidationProvider = Provider<List<String>>(
  (ref) => ref.watch(estimatorProvider.select((s) => s.activeBuildingValidation)),
);

/// Total material area for the active building (roof + parapet).
final totalMaterialAreaProvider = Provider<double>(
  (ref) =>
      ref.watch(estimatorProvider.select((s) => s.activeBuilding.totalMaterialArea)),
);

/// Sum of material area across ALL buildings — used in the right panel summary.
final projectTotalMaterialAreaProvider = Provider<double>(
  (ref) =>
      ref.watch(estimatorProvider.select((s) => s.projectTotalMaterialArea)),
);

/// Whether the project can generate a BOM (ZIP complete + at least one building ready).
final canGenerateBOMProvider = Provider<bool>(
  (ref) => ref.watch(estimatorProvider.select((s) => s.canGenerateBOM)),
);

// ─── STATE NOTIFIER ───────────────────────────────────────────────────────────

class EstimatorNotifier extends StateNotifier<EstimatorState> {
  EstimatorNotifier() : super(EstimatorState.initial());

  // ── Building management ────────────────────────────────────────────────────

  /// Adds a new blank building and switches to it.
  void addBuilding() {
    final buildings = List<BuildingState>.from(state.buildings);
    final newBuilding =
        BuildingState.initial(buildingNumber: buildings.length + 1);
    buildings.add(newBuilding);
    state = state.copyWith(
      buildings: buildings,
      activeBuildingIndex: buildings.length - 1,
    );
  }

  /// Removes a building by index. Cannot remove the last building.
  /// If the active building is removed, switches to the previous one.
  void removeBuilding(int index) {
    if (state.buildings.length <= 1) return; // always keep at least one
    final buildings = List<BuildingState>.from(state.buildings);
    buildings.removeAt(index);
    int newActive = state.activeBuildingIndex;
    if (newActive >= buildings.length) {
      newActive = buildings.length - 1;
    }
    state = state.copyWith(
      buildings: buildings,
      activeBuildingIndex: newActive,
    );
  }

  /// Switches the active building tab.
  void setActiveBuilding(int index) {
    if (index >= 0 && index < state.buildings.length) {
      state = state.copyWith(activeBuildingIndex: index);
    }
  }

  /// Renames a building by index.
  void renameBuilding(int index, String name) {
    if (index < 0 || index >= state.buildings.length) return;
    final buildings = List<BuildingState>.from(state.buildings);
    buildings[index] = buildings[index].copyWith(buildingName: name);
    state = state.copyWith(buildings: buildings);
  }

  // ── Internal helper: update active building ────────────────────────────────

  void _updateActive(BuildingState Function(BuildingState) updater) {
    state = state.withActiveBuilding(updater(state.activeBuilding));
  }

  // ── Project Info (project-level, not per-building) ─────────────────────────

  void updateProjectInfo(ProjectInfo info) =>
      state = state.copyWith(projectInfo: info);

  void updateProjectName(String value) => state = state.copyWith(
        projectInfo: state.projectInfo.copyWith(projectName: value),
      );

  void updateProjectAddress(String value) => state = state.copyWith(
        projectInfo: state.projectInfo.copyWith(projectAddress: value),
      );

  void updateZipCode(String zip) => state = state.copyWith(
        projectInfo:
            state.projectInfo.copyWith(zipCode: zip).clearZipLookup(),
      );

  void applyZipLookup({
    required String climateZone,
    required String designWindSpeed,
    required double requiredRValue,
    String? stateCounty,
  }) =>
      state = state.copyWith(
        projectInfo: state.projectInfo.copyWith(
          climateZone: climateZone,
          designWindSpeed: designWindSpeed,
          requiredRValue: requiredRValue,
          stateCounty: stateCounty,
        ),
      );

  void updateCustomerName(String value) => state = state.copyWith(
        projectInfo: state.projectInfo.copyWith(customerName: value),
      );

  void updateEstimatorName(String value) => state = state.copyWith(
        projectInfo: state.projectInfo.copyWith(estimatorName: value),
      );

  void updateWarrantyYears(int years) => state = state.copyWith(
        projectInfo: state.projectInfo.copyWith(warrantyYears: years),
      );

  // ── Roof Geometry (active building) ───────────────────────────────────────

  void updateRoofGeometry(RoofGeometry geometry) =>
      _updateActive((b) => b.copyWith(roofGeometry: geometry));

  void updateBuildingHeight(double height) => _updateActive(
        (b) => b.copyWith(
            roofGeometry: b.roofGeometry.copyWith(buildingHeight: height)),
      );

  void updateRoofSlope(String slope) => _updateActive(
        (b) => b.copyWith(
            roofGeometry: b.roofGeometry.copyWith(roofSlope: slope)),
      );

  void updateShape(int index, RoofShape shape) {
    final shapes = List<RoofShape>.from(state.activeBuilding.roofGeometry.shapes);
    if (index >= 0 && index < shapes.length) shapes[index] = shape;
    _updateActive(
      (b) => b.copyWith(
          roofGeometry: b.roofGeometry.copyWith(shapes: shapes)),
    );
  }

  void addShape() {
    final shapes =
        List<RoofShape>.from(state.activeBuilding.roofGeometry.shapes);
    if (shapes.length < 10) {
      shapes.add(RoofShape.initial(shapes.length + 1));
      _updateActive(
        (b) => b.copyWith(
            roofGeometry: b.roofGeometry.copyWith(shapes: shapes)),
      );
    }
  }

  void removeShape(int index) {
    final shapes =
        List<RoofShape>.from(state.activeBuilding.roofGeometry.shapes);
    if (shapes.length > 1 && index >= 0 && index < shapes.length) {
      shapes.removeAt(index);
      final reindexed = shapes
          .asMap()
          .entries
          .map((e) => e.value.copyWith(shapeIndex: e.key + 1))
          .toList();
      _updateActive(
        (b) => b.copyWith(
            roofGeometry: b.roofGeometry.copyWith(shapes: reindexed)),
      );
    }
  }

  void addDrain(DrainLocation location) {
    final drains = List<DrainLocation>.from(
        state.activeBuilding.roofGeometry.drainLocations);
    drains.add(location);
    _updateActive(
      (b) => b.copyWith(
          roofGeometry: b.roofGeometry.copyWith(drainLocations: drains)),
    );
  }

  void removeDrain(int index) {
    final drains = List<DrainLocation>.from(
        state.activeBuilding.roofGeometry.drainLocations);
    if (index >= 0 && index < drains.length) {
      drains.removeAt(index);
      _updateActive(
        (b) => b.copyWith(
            roofGeometry: b.roofGeometry.copyWith(drainLocations: drains)),
      );
    }
  }

  void addScupper(ScupperLocation location) {
    final scuppers = List<ScupperLocation>.from(
        state.activeBuilding.roofGeometry.scupperLocations);
    scuppers.add(location);
    _updateActive(
      (b) => b.copyWith(
          roofGeometry: b.roofGeometry.copyWith(scupperLocations: scuppers)),
    );
  }

  void removeScupper(int index) {
    final scuppers = List<ScupperLocation>.from(
        state.activeBuilding.roofGeometry.scupperLocations);
    if (index >= 0 && index < scuppers.length) {
      scuppers.removeAt(index);
      _updateActive(
        (b) => b.copyWith(
            roofGeometry: b.roofGeometry.copyWith(scupperLocations: scuppers)),
      );
    }
  }

  void overrideTotalArea(double area) => _updateActive(
        (b) => b.copyWith(
            roofGeometry: b.roofGeometry.copyWith(totalAreaOverride: area)),
      );

  void clearAreaOverride() => _updateActive(
        (b) =>
            b.copyWith(roofGeometry: b.roofGeometry.clearAreaOverride()),
      );

  void updateWindZones(WindZones zones) => _updateActive(
        (b) => b.copyWith(
            roofGeometry: b.roofGeometry.copyWith(windZones: zones)),
      );

  void updateOutsideCorners(int count) => _updateActive(
        (b) => b.copyWith(
            roofGeometry: b.roofGeometry.copyWith(outsideCorners: count)),
      );

  void updateInsideCorners(int count) => _updateActive(
        (b) => b.copyWith(
            roofGeometry: b.roofGeometry.copyWith(insideCorners: count)),
      );

  void updateSprayFoamThickness(double thickness) => _updateActive(
        (b) => b.copyWith(
            systemSpecs: b.systemSpecs.copyWith(sprayFoamThickness: thickness)),
      );

  // ── System Specs (active building) ────────────────────────────────────────

  void updateSystemSpecs(SystemSpecs specs) =>
      _updateActive((b) => b.copyWith(systemSpecs: specs));

  void updateProjectType(String type) => _updateActive(
        (b) => b.copyWith(systemSpecs: b.systemSpecs.withProjectType(type)),
      );

  void updateDeckType(String deckType) => _updateActive(
        (b) => b.copyWith(
            systemSpecs: b.systemSpecs.copyWith(deckType: deckType)),
      );

  void updateVaporRetarder(String value) => _updateActive(
        (b) => b.copyWith(
            systemSpecs: b.systemSpecs.copyWith(vaporRetarder: value)),
      );

  void updateExistingRoofType(String type) => _updateActive(
        (b) => b.copyWith(
            systemSpecs: b.systemSpecs.copyWith(existingRoofType: type)),
      );

  void updateExistingLayers(int count) => _updateActive(
        (b) => b.copyWith(
            systemSpecs: b.systemSpecs.copyWith(existingLayers: count)),
      );

  // ── Insulation (active building) ──────────────────────────────────────────

  void updateInsulationSystem(InsulationSystem system) =>
      _updateActive((b) => b.copyWith(insulationSystem: system));

  void updateLayer1(InsulationLayer layer) => _updateActive(
        (b) => b.copyWith(
            insulationSystem: b.insulationSystem.copyWith(layer1: layer)),
      );

  void updateLayer2(InsulationLayer layer) => _updateActive(
        (b) => b.copyWith(
            insulationSystem: b.insulationSystem.copyWith(layer2: layer)),
      );

  void setNumberOfLayers(int count) => _updateActive(
        (b) => b.copyWith(
          insulationSystem: count == 2
              ? b.insulationSystem.withTwoLayers()
              : count == 0
                  ? b.insulationSystem.withNoLayers()
                  : b.insulationSystem.withOneLayer(),
        ),
      );

  void setTaperedEnabled(bool enabled) => _updateActive(
        (b) => b.copyWith(
          insulationSystem: enabled
              ? b.insulationSystem.withTaperEnabled()
              : b.insulationSystem.withTaperDisabled(),
        ),
      );

  void updateTaperDefaults(TaperDefaults taperDefaults) => _updateActive(
        (b) => b.copyWith(
            insulationSystem: b.insulationSystem.copyWith(taperDefaults: taperDefaults)),
      );

  void setCoverBoardEnabled(bool enabled) => _updateActive(
        (b) => b.copyWith(
          insulationSystem: enabled
              ? b.insulationSystem.withCoverBoardEnabled()
              : b.insulationSystem.withCoverBoardDisabled(),
        ),
      );

  void updateCoverBoard(CoverBoard coverBoard) => _updateActive(
        (b) => b.copyWith(
            insulationSystem:
                b.insulationSystem.copyWith(coverBoard: coverBoard)),
      );

  // ── Membrane (active building) ────────────────────────────────────────────

  void updateMembraneSystem(MembraneSystem membrane) =>
      _updateActive((b) => b.copyWith(membraneSystem: membrane));

  void updateFieldAttachment(String method) => _updateActive(
        (b) => b.copyWith(
            membraneSystem:
                b.membraneSystem.copyWith(fieldAttachment: method)),
      );

  void updateRollWidth(String width) => _updateActive(
        (b) => b.copyWith(
            membraneSystem: b.membraneSystem.copyWith(rollWidth: width)),
      );

  void updatePerimRollWidth(String width) => _updateActive(
        (b) => b.copyWith(
            membraneSystem: b.membraneSystem.copyWith(perimeterRollWidth: width)),
      );

  void updateSeamType(String seamType) => _updateActive(
        (b) => b.copyWith(
            membraneSystem: b.membraneSystem.copyWith(seamType: seamType)),
      );

  // ── Parapet Walls (active building) ───────────────────────────────────────

  void updateParapetWalls(ParapetWalls parapet) =>
      _updateActive((b) => b.copyWith(parapetWalls: parapet));

  void setParapetEnabled(bool enabled) => _updateActive(
        (b) => b.copyWith(
            parapetWalls: b.parapetWalls.copyWith(hasParapetWalls: enabled)),
      );

  void updateParapetHeight(double height) => _updateActive(
        (b) => b.copyWith(
            parapetWalls: b.parapetWalls.copyWith(parapetHeight: height)),
      );

  void updateParapetTotalLF(double lf) => _updateActive(
        (b) => b.copyWith(
            parapetWalls: b.parapetWalls
                .copyWith(parapetTotalLF: lf)
                .clearTerminationBarOverride()),
      );

  void overrideTerminationBarLF(double lf) => _updateActive(
        (b) => b.copyWith(
            parapetWalls:
                b.parapetWalls.copyWith(terminationBarLFOverride: lf)),
      );

  /// Clears the manual termination bar override, reverting to auto = parapetTotalLF.
  void clearTerminationBarLFOverride() => _updateActive(
        (b) => b.copyWith(
            parapetWalls: b.parapetWalls.clearTerminationBarOverride()),
      );

  void updateParapetWallType(String type) => _updateActive(
        (b) => b.copyWith(
            parapetWalls: b.parapetWalls.copyWith(wallType: type)),
      );

  void updateTerminationType(String type) => _updateActive(
        (b) => b.copyWith(
            parapetWalls: b.parapetWalls.copyWith(terminationType: type)),
      );

  // ── Penetrations (active building) ────────────────────────────────────────

  void updatePenetrations(Penetrations penetrations) =>
      _updateActive((b) => b.copyWith(penetrations: penetrations));

  void updateRtuTotalLF(double lf) => _updateActive(
        (b) => b.copyWith(
            penetrations: b.penetrations.copyWith(rtuTotalLF: lf)),
      );

  void updateDrainType(String type) => _updateActive(
        (b) => b.copyWith(
            penetrations: b.penetrations.copyWith(drainType: type)),
      );

  void updateSmallPipeCount(int count) => _updateActive(
        (b) => b.copyWith(
            penetrations: b.penetrations.copyWith(smallPipeCount: count)),
      );

  void updateLargePipeCount(int count) => _updateActive(
        (b) => b.copyWith(
            penetrations: b.penetrations.copyWith(largePipeCount: count)),
      );

  void updateSkylightCount(int count) => _updateActive(
        (b) => b.copyWith(
            penetrations: b.penetrations.copyWith(skylightCount: count)),
      );

  void updateScupperCount(int count) => _updateActive(
        (b) => b.copyWith(
            penetrations: b.penetrations.copyWith(scupperCount: count)),
      );

  void updateExpansionJointLF(double lf) => _updateActive(
        (b) => b.copyWith(
            penetrations: b.penetrations.copyWith(expansionJointLF: lf)),
      );

  void updatePitchPanCount(int count) => _updateActive(
        (b) => b.copyWith(
            penetrations: b.penetrations.copyWith(pitchPanCount: count)),
      );

  // ── Metal Scope (active building) ─────────────────────────────────────────

  void updateMetalScope(MetalScope metal) =>
      _updateActive((b) => b.copyWith(metalScope: metal));

  void updateCopingWidth(String width) => _updateActive(
        (b) => b.copyWith(
            metalScope: b.metalScope.copyWith(copingWidth: width)),
      );

  void updateCopingLF(double lf) => _updateActive(
        (b) =>
            b.copyWith(metalScope: b.metalScope.copyWith(copingLF: lf)),
      );

  void updateEdgeMetalType(String type) => _updateActive(
        (b) => b.copyWith(
            metalScope: b.metalScope.copyWith(edgeMetalType: type)),
      );

  void updateWallFlashingLF(double lf) => _updateActive(
        (b) => b.copyWith(metalScope: b.metalScope.copyWith(wallFlashingLF: lf)));

  void updateDripEdgeLF(double lf) => _updateActive(
        (b) => b.copyWith(metalScope: b.metalScope.copyWith(dripEdgeLF: lf)));

  void updateOtherEdgeMetalLF(double lf) => _updateActive(
        (b) => b.copyWith(metalScope: b.metalScope.copyWith(otherEdgeMetalLF: lf)));

  // Legacy — kept to avoid compile errors in any code still calling it
  void updateEdgeMetalLF(double lf) => updateDripEdgeLF(lf);

  void updateGutterSize(String size) => _updateActive(
        (b) => b.copyWith(
            metalScope: b.metalScope.copyWith(gutterSize: size)),
      );

  void updateGutterLF(double lf) => _updateActive(
        (b) =>
            b.copyWith(metalScope: b.metalScope.copyWith(gutterLF: lf)),
      );


  // ── SOW overrides ────────────────────────────────────────────────────────────

  /// Set an AI or user-edited override for a specific SOW section.
  void updateSowSection(String key, String text) => _updateActive(
        (b) => b.copyWith(
            sowOverrides: Map<String, String>.from(b.sowOverrides)..[key] = text));

  /// Remove the override for a specific section (reverts to auto-generated).
  void clearSowSection(String key) => _updateActive((b) {
        final updated = Map<String, String>.from(b.sowOverrides)..remove(key);
        return b.copyWith(sowOverrides: updated);
      });

  /// Remove all SOW overrides (revert entire SOW to auto-generated).
  void clearAllSowOverrides() =>
      _updateActive((b) => b.copyWith(sowOverrides: const {}));

  void updateDownspoutCount(int count) => _updateActive(
        (b) => b.copyWith(
            metalScope: b.metalScope.copyWith(downspoutCount: count)),
      );

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Resets the entire project to blank defaults.
  void reset() => state = EstimatorState.initial();

  /// Resets only the active building, preserving other buildings.
  void resetActiveBuilding() {
    final index = state.activeBuildingIndex;
    _updateActive((_) =>
        BuildingState.initial(buildingNumber: index + 1));
  }

  // ── Firebase persistence ───────────────────────────────────────────────────

  /// Replaces the entire estimator state with [loaded].
  /// Used after loading a project from Firestore.
  void loadState(EstimatorState loaded) => state = loaded;
}

// ─── BOM PROVIDER ─────────────────────────────────────────────────────────────
// Imported separately to avoid circular deps. Add this import at the top of the file:
//   import '../services/bom_calculator.dart';

// NOTE: Add the following import line to the TOP of estimator_providers.dart:
//   import '../services/bom_calculator.dart';

/// Live BOM result for the active building.
/// Recalculates automatically whenever any input changes.
final bomProvider = Provider<BomResult>((ref) {
  final projectInfo = ref.watch(projectInfoProvider);
  final geometry    = ref.watch(roofGeometryProvider);
  final specs       = ref.watch(systemSpecsProvider);
  final insulation  = ref.watch(insulationSystemProvider);
  final membrane    = ref.watch(membraneSystemProvider);
  final parapet     = ref.watch(parapetWallsProvider);
  final penetrations = ref.watch(penetrationsProvider);
  final metal       = ref.watch(metalScopeProvider);
  final boardSchedule = ref.watch(boardScheduleProvider);

  return BomCalculator.calculate(
    projectInfo:   projectInfo,
    geometry:      geometry,
    systemSpecs:   specs,
    insulation:    insulation,
    membrane:      membrane,
    parapet:       parapet,
    penetrations:  penetrations,
    metalScope:    metal,
    boardSchedule: boardSchedule,
  );
});

// ─── MULTI-BUILDING BOM PROVIDERS ─────────────────────────────────────────────

/// BOM calculated for every building individually, in buildings[] order.
final allBuildingBomsProvider = Provider<List<BomResult>>((ref) {
  final state       = ref.watch(estimatorProvider);
  final projectInfo = ref.watch(projectInfoProvider);
  return state.buildings.map((b) => BomCalculator.calculate(
    projectInfo:  projectInfo,
    geometry:     b.roofGeometry,
    systemSpecs:  b.systemSpecs,
    insulation:   b.insulationSystem,
    membrane:     b.membraneSystem,
    parapet:      b.parapetWalls,
    penetrations: b.penetrations,
    metalScope:   b.metalScope,
    boardSchedule: _computeBoardSchedule(b.roofGeometry, b.insulationSystem),
  )).toList();
});

/// Aggregate BOM across all buildings.
///
/// Aggregation logic:
///   1. Group items by (category + name + unit).
///   2. Sum pre-rounded withWaste quantities across buildings.
///   3. Re-apply ceiling(combinedWithWaste / packageSize) × packageSize.
///      This is always ≤ ordering each building separately.
///   4. BomTrace.breakdown lists the per-building contribution.
///   5. Warnings from all buildings are merged (prefixed with building name).
final aggregateBomProvider = Provider<BomResult>((ref) {
  final allBoms  = ref.watch(allBuildingBomsProvider);
  final state    = ref.watch(estimatorProvider);

  if (allBoms.isEmpty) {
    return BomResult(items: [], warnings: [], isComplete: false);
  }
  if (allBoms.length == 1) return allBoms.first;

  // Keyed by "category|name|unit"
  final Map<String, _AggEntry> agg = {};

  for (int i = 0; i < allBoms.length; i++) {
    final bName = state.buildings[i].buildingName;
    for (final item in allBoms[i].items) {
      if (!item.hasQuantity) continue;
      final key = '${item.category}|${item.name}|${item.unit}';
      agg.putIfAbsent(key, () => _AggEntry(
        category:     item.category,
        name:         item.name,
        unit:         item.unit,
        notes:        item.notes,
        packageSize:  item.trace.packageSize,
        wastePercent: item.trace.wastePercent,
      )).addBuilding(bName, item.trace.withWaste);
    }
  }

  final merged = agg.values.map((e) {
    final combined = e.buildingContribs.fold(0.0, (s, c) => s + c.withWaste);
    final pkg      = e.packageSize;
    final order    = pkg > 0
        ? (combined / pkg).ceil() * pkg
        : combined.ceil().toDouble();

    final parts    = e.buildingContribs
        .map((c) => '${c.building}: ${c.withWaste.toStringAsFixed(1)}')
        .join(' + ');
    final desc     = '$parts = ${combined.toStringAsFixed(1)} combined';

    return BomLineItem(
      category: e.category,
      name:     e.name,
      orderQty: order,
      unit:     e.unit,
      notes:    e.notes,
      trace: BomTrace(
        baseDescription: desc,
        baseQty:         combined / (1 + e.wastePercent),
        wastePercent:    e.wastePercent,
        withWaste:       combined,
        packageSize:     pkg,
        orderQty:        order,
        breakdown: [
          'Project total (${e.buildingContribs.length} buildings):',
          ...e.buildingContribs.map((c) =>
              '  ${c.building}: ${c.withWaste.toStringAsFixed(2)} ${e.unit}'),
          'Combined: ${combined.toStringAsFixed(2)} ${e.unit}',
          'Package size: ${pkg == 1 ? "each" : pkg.toStringAsFixed(0)}',
          'Order qty: ${order.toStringAsFixed(0)} ${e.unit}',
        ],
      ),
    );
  }).toList();

  final warnings = <String>{};
  for (int i = 0; i < allBoms.length; i++) {
    for (final w in allBoms[i].warnings) {
      warnings.add('${state.buildings[i].buildingName}: $w');
    }
  }

  return BomResult(
    items:      merged,
    warnings:   warnings.toList(),
    isComplete: allBoms.every((b) => b.isComplete),
  );
});

/// True when the project has more than one building.
final isMultiBuildingProvider = Provider<bool>(
  (ref) => ref.watch(estimatorProvider).buildings.length > 1,
);

// ── Internal helpers ─────────────────────────────────────────────────────────

class _AggEntry {
  final String category, name, unit, notes;
  final double packageSize, wastePercent;
  final List<_Contrib> buildingContribs = [];
  _AggEntry({
    required this.category, required this.name,
    required this.unit,     required this.notes,
    required this.packageSize, required this.wastePercent,
  });
  void addBuilding(String b, double w) => buildingContribs.add(_Contrib(b, w));
}

class _Contrib {
  final String building;
  final double withWaste;
  const _Contrib(this.building, this.withWaste);
}

// ─── COMPANY PROFILE ──────────────────────────────────────────────────────────

class CompanyProfile {
  final String companyName;
  final String phone;
  final String email;
  final String address;
  final String website;
  final String tagline;        // e.g. "Commercial Roofing Specialists"
  final int brandColorValue;   // Color value (0xFFRRGGBB)
  final List<int>? logoBytes;  // Raw image bytes

  const CompanyProfile({
    this.companyName = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.website = '',
    this.tagline = '',
    this.brandColorValue = 0xFF1E3A5F, // default ProTPO blue
    this.logoBytes,
  });

  bool get hasLogo => logoBytes != null && logoBytes!.isNotEmpty;
  bool get hasName => companyName.isNotEmpty;

  CompanyProfile copyWith({
    String? companyName,
    String? phone,
    String? email,
    String? address,
    String? website,
    String? tagline,
    int? brandColorValue,
    List<int>? logoBytes,
    bool clearLogo = false,
  }) => CompanyProfile(
    companyName: companyName ?? this.companyName,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    address: address ?? this.address,
    website: website ?? this.website,
    tagline: tagline ?? this.tagline,
    brandColorValue: brandColorValue ?? this.brandColorValue,
    logoBytes: clearLogo ? null : (logoBytes ?? this.logoBytes),
  );

  Map<String, dynamic> toJson() => {
    'companyName': companyName,
    'phone': phone,
    'email': email,
    'address': address,
    'website': website,
    'tagline': tagline,
    'brandColorValue': brandColorValue,
    // logoBytes serialized separately
  };

  factory CompanyProfile.fromJson(Map<String, dynamic> json) => CompanyProfile(
    companyName: json['companyName'] ?? '',
    phone: json['phone'] ?? '',
    email: json['email'] ?? '',
    address: json['address'] ?? '',
    website: json['website'] ?? '',
    tagline: json['tagline'] ?? '',
    brandColorValue: json['brandColorValue'] ?? 0xFF1E3A5F,
  );
}

final companyProfileProvider =
    StateProvider<CompanyProfile>((ref) => const CompanyProfile());

// Legacy alias — reads logo from company profile
final companyLogoProvider = Provider<List<int>?>((ref) =>
    ref.watch(companyProfileProvider).logoBytes);

/// QXO pricing data fetched from center panel.
/// Stored here so the export service can access it.
final pricedItemsProvider =
    StateProvider<Map<String, QxoPricedItem>?>((ref) => null);

/// Global project margin % (0.0–1.0). Applied to all BOM items unless overridden.
final globalMarginProvider = StateProvider<double>((ref) => 0.30);

// ─── LABOR PROVIDERS ────────────────────────────────────────────────────────

/// Whether labor is included in the estimate.
final laborEnabledProvider = StateProvider<bool>((ref) => false);

/// All configured crews. Starts with one default crew.
final laborCrewsProvider = StateProvider<List<LaborCrew>>((ref) => [
  LaborCrew(name: 'Default Crew', rates: Map<String, double>.from(kDefaultLaborRates)),
]);

/// Index of the currently selected crew in the crews list.
final selectedCrewIndexProvider = StateProvider<int>((ref) => 0);

/// The active crew (derived).
final activeCrewProvider = Provider<LaborCrew>((ref) {
  final crews = ref.watch(laborCrewsProvider);
  final idx = ref.watch(selectedCrewIndexProvider);
  return crews[idx.clamp(0, crews.length - 1)];
});

/// Computed labor line items based on active crew rates and current BOM inputs.
final laborLineItemsProvider = Provider<List<LaborLineItem>>((ref) {
  final enabled = ref.watch(laborEnabledProvider);
  if (!enabled) return [];

  final crew = ref.watch(activeCrewProvider);
  final geo = ref.watch(roofGeometryProvider);
  final specs = ref.watch(systemSpecsProvider);
  final insulation = ref.watch(insulationSystemProvider);
  final parapet = ref.watch(parapetWallsProvider);
  final penetrations = ref.watch(penetrationsProvider);
  final metal = ref.watch(metalScopeProvider);

  final items = <LaborLineItem>[];
  final area = geo.totalArea;
  final squares = area / 100;
  final membrane = ref.watch(membraneSystemProvider);

  // ── TEAR-OFF ──
  if (specs.projectType == 'Tear-off & Replace' && area > 0) {
    final roofType = specs.existingRoofType;
    if (roofType == 'Spray Foam') {
      items.add(LaborLineItem(
        name: 'Remove Spray Foam (${specs.sprayFoamThickness.toStringAsFixed(0)}")', unit: 'SQ',
        rate: crew.rateFor('Remove Spray Foam'), quantity: squares,
      ));
      if (specs.sprayFoamThickness > 8) {
        final extraInches = specs.sprayFoamThickness - 8;
        final extraIncrements = (extraInches / 2).ceil();
        items.add(LaborLineItem(
          name: 'Spray Foam Extra Depth (${extraIncrements}x2" above 8")',
          unit: 'SQ',
          rate: crew.rateFor('Remove Spray Foam') * 0.5 * extraIncrements,
          quantity: squares,
        ));
      }
    } else {
      final removeMap = {
        'Modified Bitumen': 'Remove Torch Down',
        'Single-Ply': 'Remove TPO',
        'BUR': 'Remove Tar and Gravel',
        'Metal': 'Remove Tar and Gravel',
      };
      final removeItem = removeMap[roofType] ?? 'Remove TPO';
      items.add(LaborLineItem(
        name: removeItem, unit: 'SQ',
        rate: crew.rateFor(removeItem), quantity: squares,
      ));
    }
    items.add(LaborLineItem(
      name: 'Dump Fees', unit: 'each',
      rate: crew.rateFor('Dump Fees'), quantity: 1,
    ));
  }

  // ── DECKING ──
  if (specs.deckType == 'Wood' && area > 0) {
    items.add(LaborLineItem(
      name: 'Install Decking (per sheet)', unit: 'sheets',
      rate: crew.rateFor('Install Decking (per sheet)'),
      quantity: (area / 32).ceilToDouble(),
    ));
  }
  if (specs.deckType == 'Metal' && area > 0) {
    items.add(LaborLineItem(
      name: 'Flutes', unit: 'SQ',
      rate: crew.rateFor('Flutes'), quantity: squares,
    ));
  }

  // ── INSULATION ──
  if (insulation.layer1.thickness > 0 && area > 0) {
    items.add(LaborLineItem(
      name: 'Install ISO Board (Layer 1)', unit: 'SQ',
      rate: crew.rateFor('Install ISO Board'), quantity: squares,
    ));
  }
  if (insulation.numberOfLayers == 2 && (insulation.layer2?.thickness ?? 0) > 0 && area > 0) {
    items.add(LaborLineItem(
      name: 'Install ISO Board (Layer 2)', unit: 'SQ',
      rate: crew.rateFor('Install ISO Board'), quantity: squares,
    ));
  }
  if (insulation.hasCoverBoard && (insulation.coverBoard?.thickness ?? 0) > 0 && area > 0) {
    items.add(LaborLineItem(
      name: 'Install Cover Board', unit: 'SQ',
      rate: crew.rateFor('Install Cover Board'), quantity: squares,
    ));
  }
  if (insulation.hasTaper && area > 0) {
    items.add(LaborLineItem(
      name: 'Install Taper System', unit: 'SQ',
      rate: crew.rateFor('Install Taper System'), quantity: squares,
    ));
  }

  // ── MEMBRANE ──
  if (area > 0) {
    items.add(LaborLineItem(
      name: 'Install TPO Membrane (${membrane.fieldAttachment})', unit: 'SQ',
      rate: crew.rateFor('Install TPO Membrane'), quantity: squares,
    ));
  }

  // ── PARAPET WALLS ──
  if (parapet.hasParapetWalls && parapet.parapetTotalLF > 0) {
    final parapetSQ = ((parapet.parapetHeight / 12) * parapet.parapetTotalLF) / 100;
    items.add(LaborLineItem(
      name: 'Install Parapet Wall Flashings', unit: 'SQ',
      rate: crew.rateFor('Install Parapet Flashings'), quantity: parapetSQ,
    ));
  }
  if (parapet.hasParapetWalls && parapet.terminationBarLF > 0) {
    items.add(LaborLineItem(
      name: 'Install Termination Bar', unit: 'LF',
      rate: crew.rateFor('Install Termination Bar'),
      quantity: parapet.terminationBarLF,
    ));
  }

  // ── PENETRATIONS ──
  if (penetrations.smallPipeCount + penetrations.largePipeCount > 0) {
    items.add(LaborLineItem(
      name: 'Install Custom HVAC Pipes', unit: 'each',
      rate: crew.rateFor('Install Custom HVAC Pipes'),
      quantity: (penetrations.smallPipeCount + penetrations.largePipeCount).toDouble(),
    ));
  }
  if (penetrations.rtuDetails.isNotEmpty) {
    items.add(LaborLineItem(
      name: 'HVAC Curbs', unit: 'each',
      rate: crew.rateFor('HVAC Curbs'),
      quantity: penetrations.rtuDetails.length.toDouble(),
    ));
  }
  if (penetrations.skylightCount > 0) {
    items.add(LaborLineItem(
      name: 'Skylight Curbs', unit: 'each',
      rate: crew.rateFor('Skylight Curbs'),
      quantity: penetrations.skylightCount.toDouble(),
    ));
  }
  if (penetrations.scupperCount > 0) {
    items.add(LaborLineItem(
      name: 'Install Custom Scupper', unit: 'each',
      rate: crew.rateFor('Install Custom Scupper'),
      quantity: penetrations.scupperCount.toDouble(),
    ));
  }
  if (penetrations.pitchPanCount > 0) {
    items.add(LaborLineItem(
      name: 'Install Sealant Pockets', unit: 'each',
      rate: crew.rateFor('Install Custom Curb (exhaust fan)'),
      quantity: penetrations.pitchPanCount.toDouble(),
    ));
  }
  if (geo.numberOfDrains > 0) {
    items.add(LaborLineItem(
      name: 'Drains', unit: 'each',
      rate: crew.rateFor('Drains'),
      quantity: geo.numberOfDrains.toDouble(),
    ));
  }

  // ── EDGE METAL ──
  if (metal.dripEdgeLF > 0) {
    items.add(LaborLineItem(
      name: 'Install Drip Edge and Tape', unit: 'LF',
      rate: crew.rateFor('Install Drip Edge and Tape'),
      quantity: metal.dripEdgeLF,
    ));
  }
  if (metal.copingLF > 0) {
    items.add(LaborLineItem(
      name: 'Install Cap Metal (per foot)', unit: 'LF',
      rate: crew.rateFor('Install Cap Metal (per foot)'),
      quantity: metal.copingLF,
    ));
  }
  if (metal.wallFlashingLF > 0) {
    items.add(LaborLineItem(
      name: 'Install Wall Flashing', unit: 'LF',
      rate: crew.rateFor('Install Drip Edge and Tape'),
      quantity: metal.wallFlashingLF,
    ));
  }
  if (metal.gutterLF > 0) {
    items.add(LaborLineItem(
      name: 'Install Gutter', unit: 'LF',
      rate: crew.rateFor('Install Cap Metal (per foot)'),
      quantity: metal.gutterLF,
    ));
  }

  // ── WALKWAY PADS ──
  if (penetrations.rtuDetails.isNotEmpty && area > 0) {
    final walkLF = penetrations.rtuDetails.length * 20.0;
    items.add(LaborLineItem(
      name: 'Install Walkway Pads (p/f)', unit: 'LF',
      rate: crew.rateFor('Install Walkway Pads (p/f)'),
      quantity: walkLF,
    ));
  }

  return items;
});

/// Per-item margin overrides. Key = BOM item name, value = margin (0.0–1.0).
/// If an item is in this map, its margin overrides the global value.
final itemMarginOverridesProvider =
    StateProvider<Map<String, double>>((ref) => {});

// ─── BOM LINE ITEM OVERRIDES ──────────────────────────────────────────────────

/// Tracks user edits to BOM line items: field overrides, deletions, and additions.
class BomLineEdit {
  final String? description;  // overrides item.name
  final String? partNumber;   // manual QXO part #
  final double? qty;          // overrides orderQty
  final double? unitPrice;    // manual price override
  final String? unit;         // overrides item.unit (e.g. 'cans' vs 'cylinders')

  const BomLineEdit({this.description, this.partNumber, this.qty, this.unitPrice, this.unit});

  bool get hasOverrides =>
      description != null || partNumber != null || qty != null || unitPrice != null || unit != null;
}

/// A manually added BOM line item (not from the calculator).
class ManualBomItem {
  final String id;          // unique key
  final String category;
  final String description;
  final String partNumber;
  final double qty;
  final String unit;
  final double? unitPrice;

  const ManualBomItem({
    required this.id,
    required this.category,
    required this.description,
    this.partNumber = '',
    this.qty = 1.0,
    this.unit = 'each',
    this.unitPrice,
  });
}

/// Labor line item overrides (user edits to qty, rate, or description).
class LaborLineEdit {
  final String? description;
  final double? rate;
  final double? qty;
  const LaborLineEdit({this.description, this.rate, this.qty});
}

/// Manual labor line items added by user.
class ManualLaborItem {
  final String id;
  final String name;
  final String unit;
  final double rate;
  final double quantity;
  const ManualLaborItem({
    required this.id, required this.name, this.unit = 'each',
    this.rate = 0.0, this.quantity = 1.0,
  });
  double get total => rate * quantity;
}

/// Edits to auto-generated labor items. Key = item name.
final laborLineEditsProvider =
    StateProvider<Map<String, LaborLineEdit>>((ref) => {});

/// Deleted auto-generated labor items. Set of item names.
final laborDeletedItemsProvider =
    StateProvider<Set<String>>((ref) => {});

/// Manually added labor items.
final laborManualItemsProvider =
    StateProvider<List<ManualLaborItem>>((ref) => []);

/// Edits to calculated BOM items. Key = "category:name" (same key used for expand toggle).
final bomLineEditsProvider =
    StateProvider<Map<String, BomLineEdit>>((ref) => {});

/// Set of deleted calculated BOM item keys ("category:name").
final bomDeletedItemsProvider =
    StateProvider<Set<String>>((ref) => {});

/// Manually added BOM line items.
final bomManualItemsProvider =
    StateProvider<List<ManualBomItem>>((ref) => []);

// ─── POLYGON VERTEX BUILDER ──────────────────────────────────────────────────

/// Converts a ScupperLocation (edge index + position fraction) to world
/// coordinates using the provided polygon vertices.
Offset scupperWorldPosition(ScupperLocation scupper, List<Offset> vertices) {
  if (vertices.isEmpty || scupper.edgeIndex >= vertices.length) {
    return Offset.zero;
  }
  final a = vertices[scupper.edgeIndex];
  final b = vertices[(scupper.edgeIndex + 1) % vertices.length];
  return Offset(
    a.dx + (b.dx - a.dx) * scupper.position,
    a.dy + (b.dy - a.dy) * scupper.position,
  );
}

/// Computes a BoardScheduleResult for a given building's geometry and insulation.
///
/// Uses watershed geometry: divides the roof into drainage zones around each
/// drain/scupper, computes a board schedule per zone, and aggregates the
/// results. Falls back to single-zone worst-case when watershed fails or
/// only one low point exists.
///
/// Returns null if taper is disabled, no low points, or no valid polygon.
BoardScheduleResult? _computeBoardSchedule(RoofGeometry geo, InsulationSystem insulation) {
  if (!insulation.hasTaper || insulation.taperDefaults == null) return null;
  if (geo.drainLocations.isEmpty && geo.scupperLocations.isEmpty) return null;

  final primaryShape = geo.shapes.isNotEmpty ? geo.shapes.first : null;
  if (primaryShape == null) return null;
  final vertices = _buildPolygonVertices(primaryShape);
  if (vertices.isEmpty) return null;

  // Combine drain and scupper world positions as low points
  final lowPoints = <Offset>[
    ...geo.drainLocations.map((d) => Offset(d.x, d.y)),
    ...geo.scupperLocations.map((s) => scupperWorldPosition(s, vertices)),
  ];
  if (lowPoints.isEmpty) return null;

  final totalArea = geo.totalArea;
  if (totalArea <= 0) return null;

  final defaults = insulation.taperDefaults!;

  // Compute watershed zones
  final zones = WatershedCalculator.computeZones(
    polygonVertices: vertices,
    lowPoints: lowPoints,
    totalPolygonArea: totalArea,
  );

  if (zones.isEmpty || zones.every((z) => z.maxDistance <= 0)) {
    // Fall back to single-zone worst-case
    final distance = DrainDistanceCalculator.bestTaperDistance(
      polygonVertices: vertices,
      drainXs: lowPoints.map((p) => p.dx).toList(),
      drainYs: lowPoints.map((p) => p.dy).toList(),
    );
    if (distance <= 0) return null;
    final roofWidth = DrainDistanceCalculator.roofWidthPerpendicular(vertices);
    if (roofWidth <= 0) return null;
    return BoardScheduleCalculator.compute(BoardScheduleInput(
      distance: distance,
      taperRate: defaults.taperRate,
      minThickness: defaults.minThickness,
      manufacturer: defaults.manufacturer,
      profileType: defaults.profileType,
      roofWidthFt: roofWidth,
    ));
  }

  // Compute per-zone schedules and aggregate
  final zoneResults = <BoardScheduleResult>[];
  for (final zone in zones) {
    if (zone.maxDistance <= 0 || zone.effectiveWidth <= 0) continue;
    final result = BoardScheduleCalculator.compute(BoardScheduleInput(
      distance: zone.maxDistance,
      taperRate: defaults.taperRate,
      minThickness: defaults.minThickness,
      manufacturer: defaults.manufacturer,
      profileType: defaults.profileType,
      roofWidthFt: zone.effectiveWidth,
    ));
    zoneResults.add(result);
  }

  if (zoneResults.isEmpty) return null;
  if (zoneResults.length == 1) return zoneResults.first;

  return _aggregateZoneResults(zoneResults, zones);
}

/// Aggregates multiple per-zone BoardScheduleResults into one combined result.
BoardScheduleResult _aggregateZoneResults(
    List<BoardScheduleResult> zoneResults, List<ZoneWatershed> zones) {
  final taperedCounts = <String, int>{};
  final flatFillCounts = <double, int>{};
  int totalTapered = 0;
  int totalFlatFill = 0;
  double totalTaperedSF = 0;
  double totalFlatFillSF = 0;
  double maxThickness = 0;
  double minThickness = double.infinity;
  double weightedAvgThicknessSum = 0;
  double totalZoneArea = 0;
  final allWarnings = <String>{};

  for (int i = 0; i < zoneResults.length; i++) {
    final r = zoneResults[i];
    final zone = i < zones.length ? zones[i] : null;
    final zoneArea = zone?.area ?? 0;

    r.taperedPanelCounts.forEach((letter, count) {
      taperedCounts[letter] = (taperedCounts[letter] ?? 0) + count;
    });
    r.flatFillCounts.forEach((thickness, count) {
      flatFillCounts[thickness] = (flatFillCounts[thickness] ?? 0) + count;
    });
    totalTapered += r.totalTaperedPanels;
    totalFlatFill += r.totalFlatFillPanels;
    totalTaperedSF += r.totalTaperedSF;
    totalFlatFillSF += r.totalFlatFillSF;
    if (r.maxThicknessAtRidge > maxThickness) {
      maxThickness = r.maxThicknessAtRidge;
    }
    if (r.minThicknessAtDrain < minThickness) {
      minThickness = r.minThicknessAtDrain;
    }
    weightedAvgThicknessSum += r.avgTaperThickness * zoneArea;
    totalZoneArea += zoneArea;
    for (final w in r.warnings) {
      allWarnings.add(w);
    }
  }

  final totalPanels = totalTapered + totalFlatFill;
  // Use the waste factor from the first result (should be consistent)
  final totalWithWaste = (totalPanels * 1.10).ceil();

  final avgThickness = totalZoneArea > 0
      ? weightedAvgThicknessSum / totalZoneArea
      : 0.0;

  // Combine all rows (for display — ordering by zone)
  final allRows = zoneResults.expand((r) => r.rows).toList();

  return BoardScheduleResult(
    rows: allRows,
    maxThickness: maxThickness,
    taperedPanelCounts: taperedCounts,
    flatFillCounts: flatFillCounts,
    totalTaperedPanels: totalTapered,
    totalFlatFillPanels: totalFlatFill,
    totalPanels: totalPanels,
    totalPanelsWithWaste: totalWithWaste,
    totalTaperedSF: totalTaperedSF,
    totalFlatFillSF: totalFlatFillSF,
    minThicknessAtDrain: minThickness == double.infinity ? 0 : minThickness,
    avgTaperThickness: avgThickness,
    maxThicknessAtRidge: maxThickness,
    warnings: allWarnings.toList(),
  );
}

/// Builds polygon vertices from a RoofShape using the same turn-sequence
/// algorithm as the roof renderer. Returns world-coordinate Offsets in feet.
List<Offset> _buildPolygonVertices(RoofShape shape) {
  final edges = shape.edgeLengths;
  if (edges.length < 4 || edges.every((e) => e <= 0)) return [];
  final tmpl = kShapeTemplates[shape.shapeType];
  if (tmpl == null) return [];
  final turns = tmpl.turns;
  const ddx = [1.0, 0.0, -1.0, 0.0];
  const ddy = [0.0, -1.0, 0.0, 1.0];
  final pts = <Offset>[Offset.zero];
  var x = 0.0, y = 0.0, dir = 0;
  for (int i = 0; i < edges.length; i++) {
    x += ddx[dir % 4] * edges[i];
    y += ddy[dir % 4] * edges[i];
    pts.add(Offset(x, y));
    if (i < turns.length) dir = (dir + (turns[i] == 1 ? 1 : 3)) % 4;
  }
  pts.removeLast();
  return pts;
}
