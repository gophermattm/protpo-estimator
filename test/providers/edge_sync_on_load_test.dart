// Final fix wave: job load / building switch re-derive LF from drawn
// geometry; cover board attachment follows membrane attachment changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/models/building_state.dart';
import 'package:protpo_app/models/estimator_state.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/services/serialization.dart';

const _staleParapet = ParapetWalls(
    hasParapetWalls: true, parapetTotalLF: 100, parapetHeight: 30);

BuildingState _building(List<RoofShape> shapes, {int n = 1}) =>
    BuildingState.initial(buildingNumber: n).copyWith(
      roofGeometry: RoofGeometry(shapes: shapes),
      systemSpecs: const SystemSpecs(deckType: 'Metal'),
      membraneSystem: const MembraneSystem(fieldAttachment: 'Mechanically Attached'),
      parapetWalls: _staleParapet,
    );

RoofShape _eaves() => RoofShape(shapeIndex: 1,
    edgeLengths: const [100, 100, 100, 100],
    edgeTypes: const ['Eave', 'Eave', 'Eave', 'Eave']);

EstimatorState _stateWith(List<BuildingState> buildings, {int active = 0}) =>
    EstimatorState.initial().copyWith(buildings: buildings, activeBuildingIndex: active);

void main() {
  group('load re-derives LF from geometry', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('stale parapet LF on an all-Eave job is cleared on load (no wall adhesive)', () {
      final saved = stateToJson(_stateWith([_building([_eaves()])]), 'e1');
      final loaded = stateFromJson(saved)!;
      // Sanity: the saved job really carries the stale parapet scope.
      expect(loaded.activeBuilding.parapetWalls.parapetTotalLF, 100);

      c.read(estimatorProvider.notifier).loadState(loaded);
      final b = c.read(estimatorProvider).activeBuilding;
      expect(b.parapetWalls.parapetTotalLF, 0);
      expect(b.parapetWalls.hasParapetWalls, false);
      expect(b.metalScope.eaveLF, 400);
      final bom = c.read(bomProvider);
      expect(bom.items.where((i) => (i.skuKey ?? '').startsWith('adhesive_')), isEmpty);
    });

    test('every building is synced, not only the active one', () {
      c.read(estimatorProvider.notifier).loadState(_stateWith([
        _building([_eaves()], n: 1),
        _building([_eaves()], n: 2),
      ]));
      final s = c.read(estimatorProvider);
      for (final b in s.buildings) {
        expect(b.parapetWalls.parapetTotalLF, 0);
        expect(b.parapetWalls.hasParapetWalls, false);
      }
    });

    test('manual-entry job (no drawn edge length) is untouched on load', () {
      final manual = _building([RoofShape.initial(1)]).copyWith(
          metalScope: const MetalScope(eaveLF: 120));
      c.read(estimatorProvider.notifier).loadState(_stateWith([manual]));
      final b = c.read(estimatorProvider).activeBuilding;
      expect(b.parapetWalls, manual.parapetWalls);
      expect(b.metalScope, manual.metalScope);
      expect(b.parapetWalls.parapetTotalLF, 100);
      expect(b.parapetWalls.hasParapetWalls, true);
    });

    test('building switch re-syncs the newly active building', () {
      final n = c.read(estimatorProvider.notifier);
      n.loadState(_stateWith([_building([RoofShape.initial(1)], n: 1)]));
      // Simulate a stale second building arriving without a load pass.
      final s = c.read(estimatorProvider);
      n.state = s.copyWith(buildings: [...s.buildings, _building([_eaves()], n: 2)]);
      n.setActiveBuilding(1);
      final b = c.read(estimatorProvider).activeBuilding;
      expect(c.read(estimatorProvider).activeBuildingIndex, 1);
      expect(b.parapetWalls.parapetTotalLF, 0);
      expect(b.parapetWalls.hasParapetWalls, false);
    });
  });

  test('membrane FA -> MA switches the cover board to MA (no OlyBond)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(estimatorProvider.notifier);
    n.loadState(_stateWith([BuildingState.initial().copyWith(
        roofGeometry: RoofGeometry(shapes: [_eaves()]),
        systemSpecs: const SystemSpecs(deckType: 'Metal'))]));
    n.updateFieldAttachment('Fully Adhered');
    n.setCoverBoardEnabled(true);
    expect(c.read(estimatorProvider).activeBuilding.insulationSystem.coverBoard!.attachmentMethod,
        'Adhered');
    bool olyBond() => c.read(bomProvider).items
        .any((i) => i.skuKey == 'adhesive_olybond_500_set' && i.hasQuantity);
    expect(olyBond(), isTrue);

    n.updateFieldAttachment('Mechanically Attached');
    final ins = c.read(estimatorProvider).activeBuilding.insulationSystem;
    expect(ins.coverBoard!.attachmentMethod, 'Mechanically Attached');
    expect(olyBond(), isFalse);

    n.updateFieldAttachment('Fully Adhered');
    expect(c.read(estimatorProvider).activeBuilding.insulationSystem.coverBoard!.attachmentMethod,
        'Adhered');
  });

  test('membrane change without cover board leaves insulation alone', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(estimatorProvider.notifier);
    final before = c.read(estimatorProvider).activeBuilding.insulationSystem;
    n.updateFieldAttachment('Fully Adhered');
    expect(c.read(estimatorProvider).activeBuilding.insulationSystem, before);
  });
}
