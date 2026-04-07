import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/drain_distance_calculator.dart';
import 'dart:ui';

void main() {
  group('DrainDistanceCalculator', () {
    // 100x50 rectangle with vertices at (0,0), (100,0), (100,-50), (0,-50)
    final rectPoly = [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, -50),
      Offset(0, -50),
    ];

    test('single centered drain returns max distance to farthest vertex', () {
      final result = DrainDistanceCalculator.maxTaperDistance(
        polygonVertices: rectPoly,
        drainX: 50,
        drainY: -25,
      );
      expect(result, closeTo(55.9, 0.1));
    });

    test('drain at corner returns distance to opposite corner', () {
      final result = DrainDistanceCalculator.maxTaperDistance(
        polygonVertices: rectPoly,
        drainX: 0,
        drainY: 0,
      );
      expect(result, closeTo(111.8, 0.1));
    });

    test('drain offset from center returns correct max distance', () {
      final result = DrainDistanceCalculator.maxTaperDistance(
        polygonVertices: rectPoly,
        drainX: 50,
        drainY: -5,
      );
      expect(result, closeTo(67.3, 0.1));
    });

    test('returns 0 for empty polygon', () {
      final result = DrainDistanceCalculator.maxTaperDistance(
        polygonVertices: [],
        drainX: 50,
        drainY: -25,
      );
      expect(result, 0.0);
    });

    group('bestTaperDistance (multi-drain)', () {
      test('single drain uses its max distance', () {
        final result = DrainDistanceCalculator.bestTaperDistance(
          polygonVertices: rectPoly,
          drainXs: [50],
          drainYs: [-25],
        );
        expect(result, closeTo(55.9, 0.1));
      });

      test('two drains returns max of both max distances', () {
        final result = DrainDistanceCalculator.bestTaperDistance(
          polygonVertices: rectPoly,
          drainXs: [25, 75],
          drainYs: [-25, -25],
        );
        expect(result, closeTo(79.1, 0.1));
      });

      test('returns 0 for no drains', () {
        final result = DrainDistanceCalculator.bestTaperDistance(
          polygonVertices: rectPoly,
          drainXs: [],
          drainYs: [],
        );
        expect(result, 0.0);
      });
    });

    group('roofWidthPerpendicular', () {
      test('returns shorter dimension of bounding box', () {
        final result = DrainDistanceCalculator.roofWidthPerpendicular(rectPoly);
        expect(result, closeTo(50.0, 0.1));
      });

      test('returns 0 for empty polygon', () {
        expect(DrainDistanceCalculator.roofWidthPerpendicular([]), 0.0);
      });

      test('square polygon returns edge length', () {
        final square = [
          Offset(0, 0), Offset(40, 0), Offset(40, -40), Offset(0, -40),
        ];
        expect(DrainDistanceCalculator.roofWidthPerpendicular(square),
            closeTo(40.0, 0.1));
      });
    });
  });
}
