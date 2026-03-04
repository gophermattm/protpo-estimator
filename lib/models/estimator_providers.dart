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
import '../models/insulation_system.dart';
import '../models/section_models.dart';
import '../services/r_value_calculator.dart';

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

// ─── CALCULATION PROVIDERS ────────────────────────────────────────────────────

/// R-value result for the active building.
final rValueResultProvider = Provider<RValueResult?>((ref) {
  final insulation = ref.watch(insulationSystemProvider);
  final projectInfo = ref.watch(projectInfoProvider);

  if (insulation.layer1.thickness <= 0) return null;

  return RValueCalculator.calculate(
    layer1: InsulationLayerInput(
      materialType: insulation.layer1.type,
      thickness: insulation.layer1.thickness,
    ),
    layer2: insulation.numberOfLayers == 2 && insulation.layer2 != null
        ? InsulationLayerInput(
            materialType: insulation.layer2!.type,
            thickness: insulation.layer2!.thickness,
          )
        : null,
    tapered: insulation.hasTaperedInsulation && insulation.tapered != null
        ? TaperedInsulationInput(
            materialType: insulation.tapered!.boardType.isNotEmpty
                ? insulation.tapered!.boardType
                : 'Polyiso',
            minThicknessAtDrain: insulation.tapered!.minThicknessAtDrain,
            maxThickness: insulation.tapered!.maxThickness,
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

  return RValueCalculator.validate(
    layer1: InsulationLayerInput(
      materialType: insulation.layer1.type,
      thickness: insulation.layer1.thickness,
    ),
    layer2: insulation.numberOfLayers == 2 && insulation.layer2 != null
        ? InsulationLayerInput(
            materialType: insulation.layer2!.type,
            thickness: insulation.layer2!.thickness,
          )
        : null,
    tapered: insulation.hasTaperedInsulation && insulation.tapered != null
        ? TaperedInsulationInput(
            materialType: insulation.tapered!.boardType.isNotEmpty
                ? insulation.tapered!.boardType
                : 'Polyiso',
            minThicknessAtDrain: insulation.tapered!.minThicknessAtDrain,
            maxThickness: insulation.tapered!.maxThickness,
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
              : b.insulationSystem.withOneLayer(),
        ),
      );

  void setTaperedEnabled(bool enabled) => _updateActive(
        (b) => b.copyWith(
          insulationSystem: enabled
              ? b.insulationSystem.withTaperedEnabled()
              : b.insulationSystem.withTaperedDisabled(),
        ),
      );

  void updateTapered(TaperedInsulation tapered) => _updateActive(
        (b) => b.copyWith(
            insulationSystem: b.insulationSystem.copyWith(tapered: tapered)),
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

  void updateEdgeMetalLF(double lf) => _updateActive(
        (b) =>
            b.copyWith(metalScope: b.metalScope.copyWith(edgeMetalLF: lf)),
      );

  void updateGutterSize(String size) => _updateActive(
        (b) => b.copyWith(
            metalScope: b.metalScope.copyWith(gutterSize: size)),
      );

  void updateGutterLF(double lf) => _updateActive(
        (b) =>
            b.copyWith(metalScope: b.metalScope.copyWith(gutterLF: lf)),
      );

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
}
