// test/services/edge_totals_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/services/edge_totals.dart';

RoofShape _shape(List<String> types) => RoofShape(
    shapeIndex: 1, edgeLengths: const [100, 50, 100, 50], edgeTypes: types);

void main() {
  test('buckets by edge type; hip/valley/ridge excluded', () {
    final t = computeEdgeTotals([
      _shape(['Eave', 'Rake Edge', 'Flat Drip Edge', 'Hip']),
    ]);
    expect(t.eaveLF, 100);
    expect(t.rakeLF, 50);
    expect(t.flatDripLF, 100);
    expect(t.parapetLF, 0);
    expect(t.corners, 4);
    expect(t.hasEdges, true);
  });

  test('walls', () {
    final t = computeEdgeTotals([_shape(['Parapet', 'Headwall', 'Clerestory', 'Eave'])]);
    expect(t.parapetLF, 100);
    expect(t.headwallLF, 50);
    expect(t.wallFlashingLF, 150); // headwall + clerestory
  });

  test('no edges', () {
    expect(computeEdgeTotals(const []).hasEdges, false);
  });

  test('only zero-length edges (new job blank shape) → hasEdges false', () {
    final t = computeEdgeTotals([RoofShape.initial(1)]);
    expect(t.corners, 4);
    expect(t.totalLF, 0);
    expect(t.hasEdges, false);
  });

  group('applyEdgeTotals', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('zero-length edges are a no-op (manual LF kept)', () {
      final n = c.read(estimatorProvider.notifier);
      n.updateParapetTotalLF(80);
      n.updateEdgeMetalLF('Eave', 120);
      final before = c.read(estimatorProvider).activeBuilding;
      n.applyEdgeTotals(computeEdgeTotals([RoofShape.initial(1)]));
      final after = c.read(estimatorProvider).activeBuilding;
      expect(after.parapetWalls, before.parapetWalls);
      expect(after.metalScope, before.metalScope);
      expect(after.parapetWalls.parapetTotalLF, 80);
      expect(after.metalScope.eaveLF, 120);
    });

    test('Parapet edge switched back to Eave clears parapet scope', () {
      final n = c.read(estimatorProvider.notifier);
      n.updateParapetHeight(30);
      n.applyEdgeTotals(computeEdgeTotals([_shape(['Parapet', 'Eave', 'Eave', 'Eave'])]));
      var p = c.read(estimatorProvider).activeBuilding.parapetWalls;
      expect(p.parapetTotalLF, 100);
      expect(p.hasParapetWalls, true);

      n.applyEdgeTotals(computeEdgeTotals([_shape(['Eave', 'Eave', 'Eave', 'Eave'])]));
      p = c.read(estimatorProvider).activeBuilding.parapetWalls;
      expect(p.parapetTotalLF, 0);
      expect(p.hasParapetWalls, false);
      final m = c.read(estimatorProvider).activeBuilding.metalScope;
      expect(m.eaveLF, 300);
      expect(m.wallFlashingLF, 0);
    });

    test('headwall LF follows geometry, including back to 0', () {
      final n = c.read(estimatorProvider.notifier);
      n.applyEdgeTotals(computeEdgeTotals([_shape(['Eave', 'Rake Edge', 'Headwall', 'Rake Edge'])]));
      expect(c.read(estimatorProvider).activeBuilding.parapetWalls.headwallLF, 100);
      n.applyEdgeTotals(computeEdgeTotals([_shape(['Eave', 'Rake Edge', 'Eave', 'Rake Edge'])]));
      expect(c.read(estimatorProvider).activeBuilding.parapetWalls.headwallLF, 0);
    });

    test('no edges leaves manual values', () {
      final n = c.read(estimatorProvider.notifier);
      n.updateParapetHeight(30);
      n.updateParapetTotalLF(80);
      n.setParapetEnabled(true);
      n.applyEdgeTotals(computeEdgeTotals(const []));
      final p = c.read(estimatorProvider).activeBuilding.parapetWalls;
      expect(p.parapetTotalLF, 80);
      expect(p.hasParapetWalls, true);
    });

    test('only the active building changes', () {
      final n = c.read(estimatorProvider.notifier);
      n.addBuilding();
      final idx = c.read(estimatorProvider).activeBuildingIndex;
      n.applyEdgeTotals(computeEdgeTotals([_shape(['Eave', 'Eave', 'Eave', 'Eave'])]));
      final s = c.read(estimatorProvider);
      for (var i = 0; i < s.buildings.length; i++) {
        expect(s.buildings[i].metalScope.eaveLF, i == idx ? 300 : 0);
      }
    });
  });
}
