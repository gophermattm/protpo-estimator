// lib/services/edge_totals.dart
import '../models/roof_geometry.dart';

/// LF per edge bucket, summed from the edge types drawn in Project Geometry.
/// Project Geometry is the source of truth: these values overwrite the
/// parapet, headwall, wall flashing and edge-metal LF on every sync.
class EdgeTotals {
  final double eaveLF, rakeLF, flatDripLF;
  final double parapetLF, headwallLF, clerestoryLF;
  final int corners;
  /// Sum of every edge length, including hip/valley/ridge.
  final double totalLF;

  const EdgeTotals({
    this.eaveLF = 0, this.rakeLF = 0, this.flatDripLF = 0,
    this.parapetLF = 0, this.headwallLF = 0, this.clerestoryLF = 0,
    this.corners = 0, this.totalLF = 0,
  });

  /// False until an edge length is drawn (a new job's blank shape has
  /// zero-length edges) — manual LF entry stays authoritative.
  bool get hasEdges => totalLF > 0;

  /// Wall flashing metal: headwall and clerestory edges (parapets get coping).
  double get wallFlashingLF => headwallLF + clerestoryLF;
}

EdgeTotals computeEdgeTotals(List<RoofShape> shapes) {
  double eave = 0, rake = 0, flat = 0, parapet = 0, headwall = 0, clerestory = 0;
  int corners = 0;
  double total = 0;
  for (final s in shapes) {
    corners += s.edgeLengths.length;
    for (var i = 0; i < s.edgeLengths.length; i++) {
      final len = s.edgeLengths[i].abs();
      total += len;
      final t = i < s.edgeTypes.length ? s.edgeTypes[i] : 'Eave';
      switch (t) {
        case 'Eave': eave += len;
        case 'Rake Edge': rake += len;
        case 'Flat Drip Edge': flat += len;
        case 'Parapet': parapet += len;
        case 'Headwall': headwall += len;
        case 'Clerestory': clerestory += len;
        default: break; // Hip, Valley, Ridge: interior lines, no edge metal
      }
    }
  }
  return EdgeTotals(eaveLF: eave, rakeLF: rake, flatDripLF: flat,
      parapetLF: parapet, headwallLF: headwall, clerestoryLF: clerestory,
      corners: corners, totalLF: total);
}
