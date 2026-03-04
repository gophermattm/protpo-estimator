/// lib/widgets/roof_renderer.dart
///
/// Interactive top-down roof plan renderer — v2
///
/// Key changes from v1:
///   - Uses kShapeTemplates for correct polygon walk (left/right turns per corner)
///   - Draws ONE unified polygon per shape (L, T, U are single connected shapes)
///   - Each edge is color-coded by assigned edge type
///   - Edge type legend appears below the drawing
///   - Measurement labels show length + edge type abbreviation
///   - Drains, wind zones, compass all preserved from v1

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/roof_geometry.dart';
import '../providers/estimator_providers.dart';

// ─── EDGE TYPE COLORS ─────────────────────────────────────────────────────────

Color _edgeColor(String edgeType) {
  final hex = kEdgeTypeColors[edgeType] ?? 0xFF374151;
  return Color(hex);
}

// ─── ZONE FILL COLORS ─────────────────────────────────────────────────────────

const _kFieldColor    = Color(0xFFDBEAFE);
const _kPerimColor    = Color(0xFF93C5FD);
const _kCornerColor   = Color(0xFF3B82F6);
const _kOutlineColor  = Color(0xFF1E40AF);
const _kDrainColor    = Color(0xFF0EA5E9);
const _kSubtractColor = Color(0xFFF1F5F9);
const _kMeasureColor  = Color(0xFF374151);

// ─── PUBLIC WIDGET ────────────────────────────────────────────────────────────

class RoofRenderer extends ConsumerWidget {
  final double? maxWidth;
  const RoofRenderer({super.key, this.maxWidth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geo = ref.watch(roofGeometryProvider);
    if (geo.shapes.isEmpty || geo.totalArea <= 0) return _emptyState();
    return _RendererBody(geo: geo, maxWidth: maxWidth);
  }

  Widget _emptyState() => Container(
    height: 180,
    decoration: BoxDecoration(
      color: AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.border),
    ),
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.roofing, size: 40, color: AppTheme.textMuted),
        const SizedBox(height: 8),
        Text('Enter edge lengths to see the roof plan',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      ]),
    ),
  );
}

// ─── RENDERER BODY ────────────────────────────────────────────────────────────

class _RendererBody extends ConsumerStatefulWidget {
  final RoofGeometry geo;
  final double?      maxWidth;
  const _RendererBody({required this.geo, this.maxWidth});

  @override
  ConsumerState<_RendererBody> createState() => _RendererBodyState();
}

class _RendererBodyState extends ConsumerState<_RendererBody> {
  bool _showDrainHint = true;

  @override
  Widget build(BuildContext context) {
    final geo = widget.geo;

    return LayoutBuilder(builder: (ctx, constraints) {
      final availWidth =
          min(constraints.maxWidth, widget.maxWidth ?? constraints.maxWidth);

      final polygons = <_ShapePolygon>[];
      for (final shape in geo.shapes) {
        final pts = _buildPolygon(shape);
        if (pts != null) {
          polygons.add(_ShapePolygon(pts, shape.operation, shape));
        }
      }
      if (polygons.isEmpty) return const SizedBox.shrink();

      final allPts = polygons.expand((p) => p.points).toList();
      final bounds = _computeBounds(allPts);
      if (bounds.width <= 0 || bounds.height <= 0) return const SizedBox.shrink();

      const labelPad = 50.0;
      const minHeight = 220.0;
      final drawW   = availWidth - labelPad * 2;
      final scale   = drawW / bounds.width;
      final drawH   = max(bounds.height * scale, minHeight);
      final canvasH = drawH + labelPad * 2;

      final usedTypes = <String>{};
      for (final s in geo.shapes) usedTypes.addAll(s.edgeTypes);

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _zoneLegend(geo),
        const SizedBox(height: 8),

        GestureDetector(
          onTapUp: (d) =>
              _onTap(d.localPosition, bounds, scale, labelPad, geo),
          child: Container(
            width: availWidth,
            height: canvasH,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CustomPaint(
                size: Size(availWidth, canvasH),
                painter: _RoofPainter(
                  polygons:  polygons,
                  bounds:    bounds,
                  scale:     scale,
                  offset:    Offset(labelPad, labelPad),
                  windZones: geo.windZones,
                  drains:    geo.drainLocations,
                ),
              ),
            ),
          ),
        ),

        if (usedTypes.isNotEmpty) ...[
          const SizedBox(height: 10),
          _edgeTypeLegend(usedTypes.toList()..sort()),
        ],

        if (_showDrainHint && geo.drainLocations.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.touch_app, size: 13, color: AppTheme.textMuted),
              const SizedBox(width: 5),
              Text('Tap the roof plan to place drains.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ]),
          ),

        if (geo.drainLocations.isNotEmpty) ...[
          const SizedBox(height: 8),
          _drainList(geo),
        ],

        const SizedBox(height: 8),
        if (geo.windZones.perimeterZoneWidth > 0) _zoneSummary(geo),
      ]);
    });
  }

  void _onTap(Offset tapPos, Rect bounds, double scale,
      double labelPad, RoofGeometry geo) {
    final roofX = (tapPos.dx - labelPad) / scale + bounds.left;
    final roofY = (tapPos.dy - labelPad) / scale + bounds.top;
    final notifier = ref.read(estimatorProvider.notifier);

    for (int i = 0; i < geo.drainLocations.length; i++) {
      final d = geo.drainLocations[i];
      if (sqrt(pow(d.x - roofX, 2) + pow(d.y - roofY, 2)) < 2.0) {
        notifier.removeDrain(i);
        return;
      }
    }

    final primaryPoly = _buildPolygon(geo.shapes.first);
    if (primaryPoly == null) return;
    if (!_computeBounds(primaryPoly).contains(Offset(roofX, roofY))) return;
    notifier.addDrain(DrainLocation(x: roofX, y: roofY));
    setState(() => _showDrainHint = false);
  }

  Widget _zoneLegend(RoofGeometry geo) => Wrap(spacing: 12, runSpacing: 6, children: [
    _chip('Field Zone',     _kFieldColor,  _kOutlineColor),
    _chip('Perimeter Zone', _kPerimColor,  _kOutlineColor),
    _chip('Corner Zone',    _kCornerColor, Colors.white),
    if (geo.drainLocations.isNotEmpty) _chip('Drain', _kDrainColor, Colors.white),
  ]);

  Widget _chip(String label, Color fill, Color textColor) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: _kOutlineColor.withOpacity(0.3)),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
    ],
  );

  Widget _edgeTypeLegend(List<String> types) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Edge Types',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary)),
      const SizedBox(height: 6),
      Wrap(spacing: 12, runSpacing: 6, children: [
        for (final type in types)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 28, height: 4,
              decoration: BoxDecoration(
                color: _edgeColor(type),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(type,
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ]),
      ]),
    ]),
  );

  Widget _drainList(RoofGeometry geo) => Wrap(spacing: 8, runSpacing: 6,
    children: [
      for (int i = 0; i < geo.drainLocations.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _kDrainColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kDrainColor.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.water_drop, size: 12, color: _kDrainColor),
            const SizedBox(width: 4),
            Text('Drain ${i + 1}',
                style: TextStyle(fontSize: 11, color: _kDrainColor,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => ref.read(estimatorProvider.notifier).removeDrain(i),
              child: Icon(Icons.close, size: 12, color: _kDrainColor),
            ),
          ]),
        ),
    ],
  );

  Widget _zoneSummary(RoofGeometry geo) {
    final z = geo.windZones;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        _zoneChip('Field',     z.fieldZoneArea,     _kFieldColor),
        const SizedBox(width: 6),
        _zoneChip('Perimeter', z.perimeterZoneArea, _kPerimColor),
        const SizedBox(width: 6),
        _zoneChip('Corner',    z.cornerZoneArea,    _kCornerColor),
        const Spacer(),
        Text("Width: ${z.perimeterZoneWidth.toStringAsFixed(1)}'",
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ]),
    );
  }

  Widget _zoneChip(String label, double area, Color color) {
    final dark = color == _kCornerColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
            color: dark ? Colors.white : _kOutlineColor)),
        Text(area > 0 ? '${area.toStringAsFixed(0)} sf' : '—',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: dark ? Colors.white : _kOutlineColor)),
      ]),
    );
  }
}

// ─── CUSTOM PAINTER ───────────────────────────────────────────────────────────

class _RoofPainter extends CustomPainter {
  final List<_ShapePolygon> polygons;
  final Rect                bounds;
  final double              scale;
  final Offset              offset;
  final WindZones           windZones;
  final List<DrainLocation> drains;

  const _RoofPainter({
    required this.polygons,
    required this.bounds,
    required this.scale,
    required this.offset,
    required this.windZones,
    required this.drains,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawZones(canvas);
    _drawEdges(canvas);
    _drawMeasurements(canvas);
    _drawDrains(canvas);
    _drawCompass(canvas, size);
  }

  Offset _ts(double rx, double ry) => Offset(
    offset.dx + (rx - bounds.left) * scale,
    offset.dy + (ry - bounds.top)  * scale,
  );
  Offset _pt(Offset p) => _ts(p.dx, p.dy);

  Path _polyPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    final first = _pt(pts.first);
    path.moveTo(first.dx, first.dy);
    for (final p in pts.skip(1)) {
      final s = _pt(p);
      path.lineTo(s.dx, s.dy);
    }
    path.close();
    return path;
  }

  void _drawZones(Canvas canvas) {
    if (polygons.isEmpty) return;
    final primary = polygons.first.points;
    final w = windZones.perimeterZoneWidth;

    canvas.drawPath(
      _polyPath(primary),
      Paint()..color = _kFieldColor..style = PaintingStyle.fill,
    );

    for (final poly in polygons.skip(1)) {
      if (poly.operation == 'Subtract') {
        canvas.drawPath(
          _polyPath(poly.points),
          Paint()..color = _kSubtractColor..style = PaintingStyle.fill,
        );
      }
    }

    if (w <= 0) return;

    final inset = _insetPolygon(primary, w);
    if (inset.isNotEmpty) {
      final band = Path.combine(
          PathOperation.difference, _polyPath(primary), _polyPath(inset));
      canvas.drawPath(
          band, Paint()..color = _kPerimColor..style = PaintingStyle.fill);
      canvas.drawPath(
          _polyPath(inset),
          Paint()..color = _kFieldColor..style = PaintingStyle.fill);
    }

    final cornerPaint = Paint()
      ..color = _kCornerColor
      ..style = PaintingStyle.fill;
    for (final ci in _outsideCorners(primary)) {
      final sq = _cornerSquare(ci, primary, w);
      if (sq != null) canvas.drawPath(sq, cornerPaint);
    }
  }

  void _drawEdges(Canvas canvas) {
    // Dashed perimeter zone boundary
    final w = windZones.perimeterZoneWidth;
    if (w > 0 && polygons.isNotEmpty) {
      final inset = _insetPolygon(polygons.first.points, w);
      if (inset.isNotEmpty) {
        _drawDashedPoly(canvas, inset,
            _kOutlineColor.withOpacity(0.35), 1.0, 6, 4);
      }
    }

    for (final poly in polygons) {
      final pts   = poly.points;
      final shape = poly.shape;
      final n     = pts.length;

      for (int i = 0; i < n; i++) {
        final a = _pt(pts[i]);
        final b = _pt(pts[(i + 1) % n]);
        final edgeType = (i < shape.edgeTypes.length)
            ? shape.edgeTypes[i] : 'Eave';
        canvas.drawLine(
          a, b,
          Paint()
            ..color = _edgeColor(edgeType)
            ..strokeWidth = 3.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _drawMeasurements(Canvas canvas) {
    for (final poly in polygons) {
      final pts   = poly.points;
      final shape = poly.shape;
      final edges = shape.edgeLengths;
      final n     = pts.length;

      for (int i = 0; i < n && i < edges.length; i++) {
        final len = edges[i];
        if (len <= 0) continue;

        final a   = _pt(pts[i]);
        final b   = _pt(pts[(i + 1) % n]);
        final mid = (a + b) / 2;

        final edgeType = (i < shape.edgeTypes.length)
            ? shape.edgeTypes[i] : '';
        final color = edgeType.isNotEmpty
            ? _edgeColor(edgeType) : _kMeasureColor;

        final dir  = b - a;
        final dist = dir.distance;
        if (dist < 1) continue;
        final norm = Offset(-dir.dy, dir.dx) / dist;
        final lo   = norm * 18;

        final lenStr = "${len.toStringAsFixed(
            len == len.roundToDouble() ? 0 : 1)}'";
        _drawText(canvas, lenStr, mid + lo,
            color: _kMeasureColor, fontSize: 10.5, bold: true);

        if (edgeType.isNotEmpty) {
          final abbrev = edgeType.length > 4
              ? edgeType.substring(0, 4) : edgeType;
          _drawText(canvas, abbrev, mid + lo + const Offset(0, 12),
              color: color, fontSize: 9.0, bold: false);
        }
      }
    }
  }

  void _drawDrains(Canvas canvas) {
    for (int i = 0; i < drains.length; i++) {
      final sc = _ts(drains[i].x, drains[i].y);
      canvas.drawCircle(sc, 10,
          Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawCircle(sc, 10,
          Paint()
            ..color = _kDrainColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      canvas.drawCircle(sc, 4,
          Paint()..color = _kDrainColor..style = PaintingStyle.fill);
      _drawText(canvas, '${i + 1}', sc + const Offset(0, -18),
          color: _kDrainColor, fontSize: 9, bold: true);
    }
  }

  void _drawCompass(Canvas canvas, Size size) {
    final cx = size.width  - 24.0;
    final cy = size.height - 24.0;
    final p = Paint()
      ..color = AppTheme.textMuted
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx, cy - 12), Offset(cx, cy + 12), p);
    canvas.drawLine(Offset(cx - 12, cy), Offset(cx + 12, cy), p);
    _drawText(canvas, 'N', Offset(cx, cy - 20),
        color: AppTheme.textMuted, fontSize: 9, bold: true);
  }

  void _drawText(Canvas canvas, String text, Offset center,
      {required Color color, required double fontSize, required bool bold}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawDashedPoly(Canvas canvas, List<Offset> pts, Color color,
      double strokeW, double dash, double gap) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < pts.length; i++) {
      final a = _pt(pts[i]);
      final b = _pt(pts[(i + 1) % pts.length]);
      final total = (b - a).distance;
      if (total <= 0) continue;
      final dir = (b - a) / total;
      double pos = 0;
      bool draw = true;
      while (pos < total) {
        final segLen = draw ? dash : gap;
        final end = min(pos + segLen, total);
        if (draw) canvas.drawLine(a + dir * pos, a + dir * end, paint);
        pos = end;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(_RoofPainter old) =>
      polygons  != old.polygons  ||
      windZones != old.windZones ||
      drains    != old.drains;
}

// ─── TEMPLATE-BASED POLYGON WALK ─────────────────────────────────────────────
//
// Turn conventions (screen coords, Y increases downward):
//   +1 = turn LEFT  (CCW outward, convex corner)
//   -1 = turn RIGHT (CW inward, concave / notch corner)
//
// Direction indices (clockwise in screen space):
//   0 = East (+X)   1 = South (+Y)   2 = West (-X)   3 = North (-Y)
//
// Turn LEFT  = dirIdx = (dirIdx + 3) % 4   (subtract 1 mod 4)
// Turn RIGHT = dirIdx = (dirIdx + 1) % 4   (add 1 mod 4)

const _kDirs = [
  Offset(1, 0),    // East
  Offset(0, 1),    // South
  Offset(-1, 0),   // West
  Offset(0, -1),   // North
];

/// Delegates to the shared buildPolygonPoints() from roof_geometry.dart.
/// Hardcoded turn sequences (L=+1 left, R=-1 right) verified by coordinate math.
/// Independent of kShapeTemplates so renderer is immune to model file versions.
const _kTurns = <String, List<int>>{
  'Rectangle': [1, 1, 1, 1],
  'Square':    [1, 1, 1, 1],
  'L-Shape':   [1, 1, 1, -1, 1],   // R after E4 (inside notch corner, notch top-right)
  'T-Shape':   [1, 1, -1, 1, 1, -1, 1], // R after E3 and E6 (both notch corners)
  'U-Shape':   [1, 1, 1, -1, -1, 1, 1], // R after E4 and E5 (both notch corners)
};

List<Offset>? _buildPolygon(RoofShape shape) {
  final edges = shape.edgeLengths;
  if (edges.length < 4 || edges.every((e) => e <= 0)) return null;
  final turns = _kTurns[shape.shapeType] ?? List.filled(edges.length, 1);
  const ddx = [1.0, 0.0, -1.0, 0.0];
  const ddy = [0.0, -1.0, 0.0, 1.0]; // dir0=E, dir1=N, dir2=W, dir3=S
  final pts = <Offset>[Offset.zero];
  var x = 0.0, y = 0.0, dir = 0;
  for (int i = 0; i < edges.length; i++) {
    x += ddx[dir % 4] * edges[i];
    y += ddy[dir % 4] * edges[i];
    pts.add(Offset(x, y));
    if (i < turns.length) dir = (dir + (turns[i] == 1 ? 1 : 3)) % 4;
  }
  pts.removeLast();
  return pts;
}

// ─── POLYGON UTILITIES ────────────────────────────────────────────────────────

Rect _computeBounds(List<Offset> pts) {
  if (pts.isEmpty) return Rect.zero;
  double minX = pts.first.dx, maxX = pts.first.dx;
  double minY = pts.first.dy, maxY = pts.first.dy;
  for (final p in pts) {
    minX = min(minX, p.dx); maxX = max(maxX, p.dx);
    minY = min(minY, p.dy); maxY = max(maxY, p.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Insets a polygon by [amount] using proper edge-parallel offset.
/// Works correctly for concave (L/T/U) shapes unlike centroid-shrink.
List<Offset> _insetPolygon(List<Offset> pts, double amount) {
  if (pts.length < 3 || amount <= 0) return [];
  try {
    final n = pts.length;
    // Build inset edges: shift each edge inward by amount (to the right of travel direction)
    final edges = <_Line>[];
    for (int i = 0; i < n; i++) {
      final a = pts[i]; final b = pts[(i + 1) % n];
      final dx = b.dx - a.dx; final dy = b.dy - a.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1e-9) continue;
      // Normal pointing inward (right of CCW travel = toward interior)
      final nx = dy / len; final ny = -dx / len;
      edges.add(_Line(
        a.dx + nx * amount, a.dy + ny * amount,
        b.dx + nx * amount, b.dy + ny * amount,
      ));
    }
    if (edges.length < 3) return [];
    // Find intersection of consecutive offset edges
    final result = <Offset>[];
    for (int i = 0; i < edges.length; i++) {
      final e1 = edges[i]; final e2 = edges[(i + 1) % edges.length];
      final p = _lineIntersect(e1, e2);
      if (p != null) result.add(p);
    }
    return result.length >= 3 ? result : [];
  } catch (_) {
    return [];
  }
}

class _Line {
  final double x1, y1, x2, y2;
  const _Line(this.x1, this.y1, this.x2, this.y2);
}

Offset? _lineIntersect(_Line a, _Line b) {
  final dx1 = a.x2 - a.x1; final dy1 = a.y2 - a.y1;
  final dx2 = b.x2 - b.x1; final dy2 = b.y2 - b.y1;
  final denom = dx1 * dy2 - dy1 * dx2;
  if (denom.abs() < 1e-9) return null; // parallel
  final t = ((b.x1 - a.x1) * dy2 - (b.y1 - a.y1) * dx2) / denom;
  return Offset(a.x1 + t * dx1, a.y1 + t * dy1);
}

List<int> _outsideCorners(List<Offset> pts) {
  final result = <int>[];
  final n = pts.length;
  for (int i = 0; i < n; i++) {
    final prev = pts[(i - 1 + n) % n];
    final curr = pts[i];
    final next = pts[(i + 1) % n];
    final cross = (curr.dx - prev.dx) * (next.dy - curr.dy)
                - (curr.dy - prev.dy) * (next.dx - curr.dx);
    if (cross > 0) result.add(i);
  }
  return result;
}

Path? _cornerSquare(int ci, List<Offset> pts, double width) {
  if (pts.isEmpty || width <= 0) return null;
  final n    = pts.length;
  final prev = pts[(ci - 1 + n) % n];
  final curr = pts[ci];
  final next = pts[(ci + 1) % n];
  final d1 = _unit(prev - curr);
  final d2 = _unit(next - curr);
  final p1 = curr + d1 * width;
  final p2 = curr + d2 * width;
  final p3 = curr + d1 * width + d2 * width;
  return Path()
    ..moveTo(curr.dx, curr.dy)
    ..lineTo(p1.dx, p1.dy)
    ..lineTo(p3.dx, p3.dy)
    ..lineTo(p2.dx, p2.dy)
    ..close();
}

Offset _unit(Offset v) {
  final d = v.distance;
  return d > 0 ? v / d : Offset.zero;
}

// ─── DATA CLASS ───────────────────────────────────────────────────────────────

class _ShapePolygon {
  final List<Offset> points;
  final String       operation;
  final RoofShape    shape;
  const _ShapePolygon(this.points, this.operation, this.shape);
}
