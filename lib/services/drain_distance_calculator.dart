import 'dart:math';
import 'dart:ui';

/// Computes taper run distances from drain locations and roof polygon geometry.
///
/// Used to determine the `distance` input for [BoardScheduleCalculator].
/// Phase 2 uses simple max-vertex distance; Phase 3 will add watershed geometry.
class DrainDistanceCalculator {
  DrainDistanceCalculator._();

  /// Returns the maximum distance (in feet) from a single drain to any vertex
  /// of the roof polygon. This is the taper run distance for that drain's zone.
  static double maxTaperDistance({
    required List<Offset> polygonVertices,
    required double drainX,
    required double drainY,
  }) {
    if (polygonVertices.isEmpty) return 0.0;
    double maxDist = 0.0;
    for (final v in polygonVertices) {
      final dist = sqrt(pow(v.dx - drainX, 2) + pow(v.dy - drainY, 2));
      if (dist > maxDist) maxDist = dist;
    }
    return maxDist;
  }

  /// Returns the best taper distance to use for the board schedule when
  /// multiple drains are placed. Returns the maximum of all individual drain
  /// max-distances.
  static double bestTaperDistance({
    required List<Offset> polygonVertices,
    required List<double> drainXs,
    required List<double> drainYs,
  }) {
    if (polygonVertices.isEmpty || drainXs.isEmpty) return 0.0;
    double best = 0.0;
    for (int i = 0; i < drainXs.length; i++) {
      final dist = maxTaperDistance(
        polygonVertices: polygonVertices,
        drainX: drainXs[i],
        drainY: drainYs[i],
      );
      if (dist > best) best = dist;
    }
    return best;
  }

  /// Returns the perpendicular roof width — the shorter dimension of the
  /// polygon's bounding box. Used as `roofWidthFt` in [BoardScheduleInput].
  static double roofWidthPerpendicular(List<Offset> polygonVertices) {
    if (polygonVertices.isEmpty) return 0.0;
    double minX = polygonVertices.first.dx, maxX = minX;
    double minY = polygonVertices.first.dy, maxY = minY;
    for (final v in polygonVertices) {
      if (v.dx < minX) minX = v.dx;
      if (v.dx > maxX) maxX = v.dx;
      if (v.dy < minY) minY = v.dy;
      if (v.dy > maxY) maxY = v.dy;
    }
    final w = maxX - minX;
    final h = maxY - minY;
    return min(w, h);
  }
}
