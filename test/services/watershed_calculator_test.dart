import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/watershed_calculator.dart';

void main() {
  group('WatershedCalculator', () {
    // 100×50 rectangle
    final rect = [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, -50),
      Offset(0, -50),
    ];
    const rectArea = 100.0 * 50.0;

    test('single drain returns one zone with full area', () {
      final zones = WatershedCalculator.computeZones(
        polygonVertices: rect,
        lowPoints: [Offset(50, -25)],
        totalPolygonArea: rectArea,
      );
      expect(zones.length, 1);
      expect(zones[0].area, closeTo(rectArea, rectArea * 0.05));
      // Max distance from center is ~55.9 (to corner)
      expect(zones[0].maxDistance, closeTo(55.9, 0.5));
    });

    test('two symmetric drains split area roughly in half', () {
      final zones = WatershedCalculator.computeZones(
        polygonVertices: rect,
        lowPoints: [Offset(25, -25), Offset(75, -25)],
        totalPolygonArea: rectArea,
      );
      expect(zones.length, 2);
      // Each zone should be ~half the area
      expect(zones[0].area, closeTo(rectArea / 2, rectArea * 0.1));
      expect(zones[1].area, closeTo(rectArea / 2, rectArea * 0.1));
      // Max distance from each drain to farthest point in its half
      // Drain at (25,-25): farthest point in left half = (0,0) or (0,-50)
      // Distance = sqrt(25^2 + 25^2) = 35.4
      expect(zones[0].maxDistance, closeTo(35.4, 1.0));
      expect(zones[1].maxDistance, closeTo(35.4, 1.0));
    });

    test('effective width is area / distance', () {
      final zones = WatershedCalculator.computeZones(
        polygonVertices: rect,
        lowPoints: [Offset(50, -25)],
        totalPolygonArea: rectArea,
      );
      expect(zones[0].effectiveWidth,
          closeTo(rectArea / zones[0].maxDistance, 1.0));
    });

    test('two drains produce shorter max distance than one worst-case', () {
      final single = WatershedCalculator.computeZones(
        polygonVertices: rect,
        lowPoints: [Offset(50, -25)],
        totalPolygonArea: rectArea,
      );
      final multi = WatershedCalculator.computeZones(
        polygonVertices: rect,
        lowPoints: [Offset(25, -25), Offset(75, -25)],
        totalPolygonArea: rectArea,
      );
      // Multiple drains should reduce per-zone max distance vs single drain
      expect(multi[0].maxDistance, lessThan(single[0].maxDistance));
      expect(multi[1].maxDistance, lessThan(single[0].maxDistance));
    });

    test('returns empty for empty polygon', () {
      final zones = WatershedCalculator.computeZones(
        polygonVertices: [],
        lowPoints: [Offset(0, 0)],
        totalPolygonArea: 100,
      );
      expect(zones, isEmpty);
    });

    test('returns empty for no low points', () {
      final zones = WatershedCalculator.computeZones(
        polygonVertices: rect,
        lowPoints: [],
        totalPolygonArea: rectArea,
      );
      expect(zones, isEmpty);
    });

    test('scupper at edge center produces correct zone', () {
      // Scupper at back edge center (50, 0)
      final zones = WatershedCalculator.computeZones(
        polygonVertices: rect,
        lowPoints: [Offset(50, 0)],
        totalPolygonArea: rectArea,
      );
      expect(zones.length, 1);
      // Farthest point from (50, 0) is (0, -50) or (100, -50)
      // Distance = sqrt(50^2 + 50^2) = 70.7
      expect(zones[0].maxDistance, closeTo(70.7, 0.5));
    });
  });
}
