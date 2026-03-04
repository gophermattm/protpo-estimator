/// lib/models/building_state.dart
///
/// Holds all per-building estimator data for one roof on a multi-building bid.
///
/// Architecture note:
///   ProjectInfo (name, address, ZIP, warranty) lives at the project level
///   in EstimatorState and is shared across all buildings — it represents
///   the bid/project, not a specific roof.
///
///   Everything from geometry onward is per-building and lives here.
///
/// Usage:
///   ref.watch(activeBuildingProvider)            → current BuildingState
///   ref.read(estimatorProvider.notifier).updateActiveBuilding(...)

import 'package:uuid/uuid.dart';
import 'roof_geometry.dart';
import 'system_specs.dart';
import 'insulation_system.dart';
import 'section_models.dart';

class BuildingState {
  /// Stable unique ID — used as a key in lists, never changes.
  final String id;

  /// Display name shown on the building tab (e.g. "Building A", "North Wing").
  /// User-editable. Defaults to "Building 1", "Building 2", etc.
  final String buildingName;

  // ── Per-building sections ──────────────────────────────────────────────────

  final RoofGeometry roofGeometry;
  final SystemSpecs systemSpecs;
  final InsulationSystem insulationSystem;
  final MembraneSystem membraneSystem;
  final ParapetWalls parapetWalls;
  final Penetrations penetrations;
  final MetalScope metalScope;

  const BuildingState({
    required this.id,
    required this.buildingName,
    required this.roofGeometry,
    required this.systemSpecs,
    required this.insulationSystem,
    required this.membraneSystem,
    required this.parapetWalls,
    required this.penetrations,
    required this.metalScope,
  });

  /// Creates a blank building with a generated ID and a default display name.
  factory BuildingState.initial({int buildingNumber = 1}) => BuildingState(
        id: const Uuid().v4(),
        buildingName: 'Building $buildingNumber',
        roofGeometry: RoofGeometry.initial(),
        systemSpecs: SystemSpecs.initial(),
        insulationSystem: InsulationSystem.initial(),
        membraneSystem: MembraneSystem.initial(),
        parapetWalls: ParapetWalls.initial(),
        penetrations: Penetrations.initial(),
        metalScope: MetalScope.initial(),
      );

  BuildingState copyWith({
    String? id,
    String? buildingName,
    RoofGeometry? roofGeometry,
    SystemSpecs? systemSpecs,
    InsulationSystem? insulationSystem,
    MembraneSystem? membraneSystem,
    ParapetWalls? parapetWalls,
    Penetrations? penetrations,
    MetalScope? metalScope,
  }) {
    return BuildingState(
      id: id ?? this.id,
      buildingName: buildingName ?? this.buildingName,
      roofGeometry: roofGeometry ?? this.roofGeometry,
      systemSpecs: systemSpecs ?? this.systemSpecs,
      insulationSystem: insulationSystem ?? this.insulationSystem,
      membraneSystem: membraneSystem ?? this.membraneSystem,
      parapetWalls: parapetWalls ?? this.parapetWalls,
      penetrations: penetrations ?? this.penetrations,
      metalScope: metalScope ?? this.metalScope,
    );
  }

  // ── Cross-section derived values (per building) ────────────────────────────

  /// Total roof area including parapet wall flashing area.
  /// Parapet area ADDS to total for material calculations per spec.
  double get totalMaterialArea =>
      roofGeometry.totalArea + parapetWalls.parapetArea;

  /// Drain count is owned by geometry; penetrations section references it.
  int get drainCount => roofGeometry.numberOfDrains;

  /// True when MA membrane is selected but no deck type is set.
  bool get membraneNeedsDeckType =>
      membraneSystem.fieldAttachment == 'Mechanically Attached' &&
      systemSpecs.deckType.isEmpty;

  /// True when tapered insulation is enabled but no drains are placed.
  bool get taperedNeedsDrains =>
      insulationSystem.hasTaperedInsulation && drainCount == 0;

  /// True when parapet exists but termination bar LF is 0.
  bool get parapetNeedsTerminationBar =>
      parapetWalls.hasParapetWalls &&
      parapetWalls.terminationBarLF == 0.0 &&
      parapetWalls.parapetTotalLF > 0;

  /// True when this building has enough data to contribute to a BOM.
  bool get canGenerateBOM =>
      roofGeometry.totalArea > 0 && systemSpecs.deckTypeIsSet;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildingState &&
          id == other.id &&
          buildingName == other.buildingName &&
          roofGeometry == other.roofGeometry &&
          systemSpecs == other.systemSpecs &&
          insulationSystem == other.insulationSystem &&
          membraneSystem == other.membraneSystem &&
          parapetWalls == other.parapetWalls &&
          penetrations == other.penetrations &&
          metalScope == other.metalScope;

  @override
  int get hashCode => Object.hash(
        id,
        buildingName,
        roofGeometry,
        systemSpecs,
        insulationSystem,
        membraneSystem,
        parapetWalls,
        penetrations,
        metalScope,
      );
}
