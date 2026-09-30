import 'dart:math';
import 'dart:ui';

/// A drainage low feature in world coordinates (feet). Drains and scuppers are
/// points ([start] == [end]); a gutter is the segment it runs along. Water in
/// a zone flows to the nearest point on the feature, so a gutter produces
/// bands parallel to the edge instead of rings around a point.
class LowFeature {
  final Offset start;
  final Offset end;

  const LowFeature.point(Offset p)
      : start = p,
        end = p;
  const LowFeature.segment(this.start, this.end);

  bool get isPoint => start == end;

  /// Nearest point on this feature to (px, py).
  Offset closestPoint(double px, double py) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-12) return start;
    final t = (((px - start.dx) * dx + (py - start.dy) * dy) / lenSq)
        .clamp(0.0, 1.0);
    return Offset(start.dx + dx * t, start.dy + dy * t);
  }

  double distanceTo(double px, double py) {
    final c = closestPoint(px, py);
    final ddx = px - c.dx;
    final ddy = py - c.dy;
    return sqrt(ddx * ddx + ddy * ddy);
  }

  /// Index of the feature nearest (px, py) and its distance.
  static (int, double) nearest(List<LowFeature> features, double px, double py) {
    int idx = 0;
    double best = features[0].distanceTo(px, py);
    for (int i = 1; i < features.length; i++) {
      final d = features[i].distanceTo(px, py);
      if (d < best) {
        best = d;
        idx = i;
      }
    }
    return (idx, best);
  }
}

/// Result for a single drainage zone around one low point.
class ZoneWatershed {
  /// Index into the original lowPoints list.
  final int lowPointIndex;

  /// Max distance (feet) from the low point to any polygon interior point
  /// that belongs to this zone. This is the taper run distance.
  final double maxDistance;

  /// Approximate area of this zone in square feet.
  final double area;

  /// Effective perpendicular width for board-schedule panel count:
  /// area / maxDistance.
  double get effectiveWidth => maxDistance > 0 ? area / maxDistance : 0;

  const ZoneWatershed({
    required this.lowPointIndex,
    required this.maxDistance,
    required this.area,
  });
}

/// Computes per-zone watershed boundaries using grid sampling.
///
/// Algorithm:
///   1. Sample the polygon's bounding box with an NxN grid
///   2. For each grid point inside the polygon, assign it to the nearest
///      low point (Voronoi-style)
///   3. Track max distance and point count per zone
///   4. Convert point counts to area proportions
///
/// Phase 3 uses this to replace the worst-case single-zone approximation
/// with accurate per-zone taper distances for multi-drain/scupper jobs.
class WatershedCalculator {
  WatershedCalculator._();

  /// Returns one ZoneWatershed per low point. If a low point has no assigned
  /// grid samples (e.g. degenerate placement), its zone has area=0, distance=0.
  ///
  /// Pass either [lowPoints] (drains/scuppers only) or [lowFeatures] (which
  /// may include gutter segments). [lowFeatures] wins when both are given.
  static List<ZoneWatershed> computeZones({
    required List<Offset> polygonVertices,
    List<Offset> lowPoints = const [],
    List<LowFeature>? lowFeatures,
    required double totalPolygonArea,
    int gridResolution = 60,
  }) {
    final features =
        lowFeatures ?? lowPoints.map((p) => LowFeature.point(p)).toList();
    if (polygonVertices.isEmpty || features.isEmpty || totalPolygonArea <= 0) {
      return [];
    }

    // Compute bounding box
    double minX = polygonVertices.first.dx, maxX = minX;
    double minY = polygonVertices.first.dy, maxY = minY;
    for (final v in polygonVertices) {
      if (v.dx < minX) minX = v.dx;
      if (v.dx > maxX) maxX = v.dx;
      if (v.dy < minY) minY = v.dy;
      if (v.dy > maxY) maxY = v.dy;
    }
    final bboxW = maxX - minX;
    final bboxH = maxY - minY;
    if (bboxW <= 0 || bboxH <= 0) return [];

    // Grid sampling
    final zoneMaxDist = List.filled(features.length, 0.0);
    final zonePointCount = List.filled(features.length, 0);
    int totalInsideCount = 0;

    final stepX = bboxW / gridResolution;
    final stepY = bboxH / gridResolution;

    for (int ix = 0; ix <= gridResolution; ix++) {
      for (int iy = 0; iy <= gridResolution; iy++) {
        final px = minX + ix * stepX;
        final py = minY + iy * stepY;
        if (!_pointInPolygon(px, py, polygonVertices)) continue;
        totalInsideCount++;

        final (nearestIdx, nearestDist) = LowFeature.nearest(features, px, py);

        zonePointCount[nearestIdx]++;
        if (nearestDist > zoneMaxDist[nearestIdx]) {
          zoneMaxDist[nearestIdx] = nearestDist;
        }
      }
    }

    // Also sample polygon vertices — they often contain the true maximum
    // distance from a low point, which grid sampling may miss between cells.
    for (final v in polygonVertices) {
      final (nearestIdx, nearestDist) = LowFeature.nearest(features, v.dx, v.dy);
      if (nearestDist > zoneMaxDist[nearestIdx]) {
        zoneMaxDist[nearestIdx] = nearestDist;
      }
    }

    if (totalInsideCount == 0) return [];

    // Convert counts to area proportions
    return List.generate(features.length, (i) {
      final areaFraction = zonePointCount[i] / totalInsideCount;
      return ZoneWatershed(
        lowPointIndex: i,
        maxDistance: zoneMaxDist[i],
        area: totalPolygonArea * areaFraction,
      );
    });
  }

  /// Ray-casting point-in-polygon test.
  static bool _pointInPolygon(double px, double py, List<Offset> poly) {
    bool inside = false;
    final n = poly.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = poly[i].dx, yi = poly[i].dy;
      final xj = poly[j].dx, yj = poly[j].dy;
      final intersect = ((yi > py) != (yj > py)) &&
          (px < (xj - xi) * (py - yi) / ((yj - yi) + 1e-12) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
