import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/models/drainage_zone.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/services/serialization.dart';
import 'package:protpo_app/services/watershed_calculator.dart';

/// Gutters as a tapered-insulation low feature (line drain along an edge).
void main() {
  // 100×50 rectangle in provider coordinates: edge 0 = (0,0)→(100,0).
  final rect = [
    const Offset(0, 0),
    const Offset(100, 0),
    const Offset(100, -50),
    const Offset(0, -50),
  ];
  const rectArea = 100.0 * 50.0;

  RoofGeometry rectGeo({
    List<DrainLocation> drains = const [],
    List<GutterLocation> gutters = const [],
  }) =>
      RoofGeometry(
        shapes: const [
          RoofShape(
            shapeIndex: 1,
            shapeType: 'Rectangle',
            edgeLengths: [100, 50, 100, 50],
            edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'],
          ),
        ],
        drainLocations: drains,
        gutterLocations: gutters,
      );

  group('LowFeature', () {
    test('segment distance is perpendicular inside the run', () {
      const f = LowFeature.segment(Offset(0, 0), Offset(100, 0));
      expect(f.distanceTo(30, -20), closeTo(20, 1e-9));
      expect(f.closestPoint(30, -20), const Offset(30, 0));
    });

    test('segment distance clamps to endpoints past the run', () {
      const f = LowFeature.segment(Offset(0, 0), Offset(50, 0));
      expect(f.distanceTo(80, -40), closeTo(50, 1e-9)); // 3-4-5 from (50,0)
    });

    test('point feature matches plain distance', () {
      const f = LowFeature.point(Offset(10, 10));
      expect(f.isPoint, isTrue);
      expect(f.distanceTo(13, 14), closeTo(5, 1e-9));
    });
  });

  group('WatershedCalculator with gutters', () {
    test('full-edge gutter: run = building depth, width = edge length', () {
      final zones = WatershedCalculator.computeZones(
        polygonVertices: rect,
        lowFeatures: const [LowFeature.segment(Offset(0, 0), Offset(100, 0))],
        totalPolygonArea: rectArea,
      );
      expect(zones.length, 1);
      expect(zones[0].maxDistance, closeTo(50, 0.01));
      expect(zones[0].area, closeTo(rectArea, 1e-6));
      expect(zones[0].effectiveWidth, closeTo(100, 0.1));
    });

    test('gutters on opposite long edges split the roof at the ridge', () {
      final zones = WatershedCalculator.computeZones(
        polygonVertices: rect,
        lowFeatures: const [
          LowFeature.segment(Offset(0, 0), Offset(100, 0)),
          LowFeature.segment(Offset(100, -50), Offset(0, -50)),
        ],
        totalPolygonArea: rectArea,
      );
      expect(zones.length, 2);
      expect(zones[0].maxDistance, closeTo(25, 1.0));
      expect(zones[1].maxDistance, closeTo(25, 1.0));
      expect(zones[0].area, closeTo(rectArea / 2, rectArea * 0.05));
    });

    test('lowPoints API still works (backward compatible)', () {
      final zones = WatershedCalculator.computeZones(
        polygonVertices: rect,
        lowPoints: const [Offset(50, -25)],
        totalPolygonArea: rectArea,
      );
      expect(zones.single.maxDistance, closeTo(55.9, 0.5));
    });
  });

  group('drainageLowFeatures', () {
    test('orders drains, scuppers, gutters and maps gutter to edge segment', () {
      final geo = rectGeo(
        drains: const [DrainLocation(x: 50, y: -25)],
        gutters: const [GutterLocation(edgeIndex: 1, start: 0.2, end: 0.8)],
      ).copyWith(scupperLocations: const [
        ScupperLocation(edgeIndex: 2, position: 0.5),
      ]);
      final f = drainageLowFeatures(geo, rect);
      expect(f.length, 3);
      expect(f[0].isPoint, isTrue);
      expect(f[1].start, const Offset(50, -50));
      expect(f[2].start.dx, closeTo(100, 1e-9));
      expect(f[2].start.dy, closeTo(-10, 1e-9));
      expect(f[2].end.dy, closeTo(-40, 1e-9));
    });

    test('skips gutters on edges that no longer exist', () {
      final geo = rectGeo(gutters: const [GutterLocation(edgeIndex: 9)]);
      expect(drainageLowFeatures(geo, rect), isEmpty);
    });
  });

  group('board schedule with gutters', () {
    test('gutter alone produces a tapered board schedule', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(estimatorProvider.notifier);
      n.updateRoofGeometry(rectGeo());
      n.setTaperedEnabled(true);
      expect(c.read(boardScheduleProvider), isNull);

      n.addGutter(const GutterLocation(edgeIndex: 0));
      final result = c.read(boardScheduleProvider);
      expect(result, isNotNull);
      expect(result!.totalTaperedPanels, greaterThan(0));
      expect(c.read(watershedZonesProvider).single.maxDistance,
          closeTo(50, 0.01));
    });

    test('adding a gutter updates taper counts automatically', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(estimatorProvider.notifier);
      n.updateRoofGeometry(rectGeo(gutters: const [GutterLocation(edgeIndex: 0)]));
      n.setTaperedEnabled(true);
      final one = c.read(boardScheduleProvider)!;

      // Second gutter on the opposite eave halves the run → thinner ridge.
      n.addGutter(const GutterLocation(edgeIndex: 2));
      final two = c.read(boardScheduleProvider)!;
      expect(c.read(watershedZonesProvider).length, 2);
      expect(two.maxThicknessAtRidge, lessThan(one.maxThicknessAtRidge));
      expect(two.totalPanels, isNot(equals(one.totalPanels)));

      n.removeGutter(1);
      expect(c.read(boardScheduleProvider)!.totalPanels, one.totalPanels);
    });

    test('one gutter per edge', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(estimatorProvider.notifier);
      n.updateRoofGeometry(rectGeo());
      n.addGutter(const GutterLocation(edgeIndex: 0));
      n.addGutter(const GutterLocation(edgeIndex: 0));
      expect(c.read(roofGeometryProvider).gutterLocations.length, 1);
    });
  });

  group('Metal Scope gutter LF follows drawn gutters', () {
    ProviderContainer setup() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(estimatorProvider.notifier).updateRoofGeometry(rectGeo());
      return c;
    }

    double gutterLF(ProviderContainer c) =>
        c.read(estimatorProvider).activeBuilding.metalScope.gutterLF;

    test('empty field fills from drawn runs and tracks edits', () {
      final c = setup();
      final n = c.read(estimatorProvider.notifier);
      n.addGutter(const GutterLocation(edgeIndex: 0)); // 100 ft
      expect(gutterLF(c), 100);
      n.addGutter(const GutterLocation(edgeIndex: 1)); // + 50 ft
      expect(gutterLF(c), 150);
      n.updateGutter(0, const GutterLocation(edgeIndex: 0, start: 0.25, end: 0.75));
      expect(gutterLF(c), 100); // 50 + 50
      n.removeGutter(1);
      n.removeGutter(0);
      expect(gutterLF(c), 0);
    });

    test('a typed-in gutter LF is never overwritten', () {
      final c = setup();
      final n = c.read(estimatorProvider.notifier);
      n.updateGutterLF(240);
      n.addGutter(const GutterLocation(edgeIndex: 0));
      expect(gutterLF(c), 240);
      n.removeGutter(0);
      expect(gutterLF(c), 240);
    });

    test('user edit after auto-fill stops syncing', () {
      final c = setup();
      final n = c.read(estimatorProvider.notifier);
      n.addGutter(const GutterLocation(edgeIndex: 0));
      n.updateGutterLF(120);
      n.addGutter(const GutterLocation(edgeIndex: 2));
      expect(gutterLF(c), 120);
    });
  });

  test('partial gutter run shortens the drainage feature', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(estimatorProvider.notifier);
    n.updateRoofGeometry(rectGeo(gutters: const [GutterLocation(edgeIndex: 0)]));
    n.setTaperedEnabled(true);
    final full = c.read(watershedZonesProvider).single.maxDistance;
    n.updateGutter(0, const GutterLocation(edgeIndex: 0, start: 0.4, end: 0.6));
    final partial = c.read(watershedZonesProvider).single.maxDistance;
    expect(full, closeTo(50, 0.01));
    // Far corner (0,-50) to run end (40,0): sqrt(40² + 50²) ≈ 64.0
    expect(partial, closeTo(64.03, 0.1));
  });

  test('RoofGeometry gutter round-trip; old JSON loads with none', () {
    final geo = rectGeo(
        gutters: const [GutterLocation(edgeIndex: 2, start: 0.1, end: 0.9)]);
    final restored = roofGeometryFromJson(roofGeometryToJson(geo));
    expect(restored.gutterLocations,
        const [GutterLocation(edgeIndex: 2, start: 0.1, end: 0.9)]);

    final legacy = roofGeometryToJson(rectGeo())..remove('gutterLocations');
    expect(roofGeometryFromJson(legacy).gutterLocations, isEmpty);
  });
}
