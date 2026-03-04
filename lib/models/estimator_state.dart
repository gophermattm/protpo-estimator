/// lib/models/estimator_state.dart
///
/// Root state object for the entire estimator.
///
/// Multi-building architecture:
///   - ProjectInfo (name, address, ZIP, warranty) is project-level — shared
///     across all buildings on the same bid.
///   - All roof data (geometry, specs, insulation, membrane, etc.) is
///     per-building, held in List<BuildingState>.
///   - activeBuilidngIndex tracks which building the left panel is editing.
///
/// The rest of the app (section providers, BOM, validation) always reads
/// from activeBuilding — they don't need to know about the list.

import 'project_info.dart';
import 'building_state.dart';

class EstimatorState {
  final ProjectInfo projectInfo;
  final List<BuildingState> buildings;
  final int activeBuildingIndex;

  const EstimatorState({
    required this.projectInfo,
    required this.buildings,
    required this.activeBuildingIndex,
  });

  factory EstimatorState.initial() => EstimatorState(
        projectInfo: ProjectInfo.initial(),
        buildings: [BuildingState.initial(buildingNumber: 1)],
        activeBuildingIndex: 0,
      );

  // ── Active building convenience accessor ───────────────────────────────────

  /// The building currently being edited in the left panel.
  BuildingState get activeBuilding => buildings[activeBuildingIndex];

  // ── copyWith ───────────────────────────────────────────────────────────────

  EstimatorState copyWith({
    ProjectInfo? projectInfo,
    List<BuildingState>? buildings,
    int? activeBuildingIndex,
  }) {
    return EstimatorState(
      projectInfo: projectInfo ?? this.projectInfo,
      buildings: buildings ?? this.buildings,
      activeBuildingIndex: activeBuildingIndex ?? this.activeBuildingIndex,
    );
  }

  /// Convenience: returns a new EstimatorState with the active building replaced.
  EstimatorState withActiveBuilding(BuildingState updated) {
    final list = List<BuildingState>.from(buildings);
    list[activeBuildingIndex] = updated;
    return copyWith(buildings: list);
  }

  // ── Project-level derived values ───────────────────────────────────────────

  /// Sum of totalMaterialArea across all buildings.
  /// Used by the project summary in the right panel.
  double get projectTotalMaterialArea =>
      buildings.fold(0.0, (sum, b) => sum + b.totalMaterialArea);

  /// True when the project has a valid ZIP lookup AND at least one building
  /// has enough data to generate a BOM.
  bool get canGenerateBOM =>
      projectInfo.zipLookupComplete &&
      buildings.any((b) => b.canGenerateBOM);

  /// Validation messages for the active building's cross-section rules.
  List<String> get activeBuildingValidation {
    final b = activeBuilding;
    final messages = <String>[];

    if (!projectInfo.zipLookupComplete) {
      messages.add('[BLOCKER] Missing ZIP Code — cannot determine climate zone');
    }
    if (!b.systemSpecs.deckTypeIsSet) {
      messages.add('[BLOCKER] Missing Deck Type — cannot select fasteners');
    }
    if (b.membraneNeedsDeckType) {
      messages.add('[BLOCKER] MA membrane selected but no deck type specified');
    }
    if (b.taperedNeedsDrains) {
      messages.add('[WARNING] Tapered insulation selected but no drains placed');
    }
    if (b.parapetNeedsTerminationBar) {
      messages.add(
          '[AUTO-CORRECT] Parapet exists but termination bar LF is 0 — auto-filled from parapet LF');
    }

    return messages;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EstimatorState &&
          projectInfo == other.projectInfo &&
          activeBuildingIndex == other.activeBuildingIndex &&
          _listEquals(buildings, other.buildings);

  static bool _listEquals(List<BuildingState> a, List<BuildingState> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        projectInfo,
        activeBuildingIndex,
        Object.hashAll(buildings),
      );
}
