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
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/roof_geometry.dart';
import '../models/drainage_zone.dart';
import '../models/section_models.dart';
import '../providers/estimator_providers.dart';
import '../data/board_schedules.dart';

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
    final metalScope = ref.watch(metalScopeProvider);
    final parapet = ref.watch(parapetWallsProvider);
    // Coping is active when copingLF is populated AND parapet fields are filled
    final copingActive = metalScope.copingLF > 0 &&
        parapet.hasParapetWalls && parapet.parapetHeight > 0 && parapet.parapetTotalLF > 0;
    final copingWidthFt = copingActive
        ? (double.tryParse(metalScope.copingWidth.replaceAll('"', '')) ?? 12) / 12
        : 0.0;
    return _RendererBody(geo: geo, maxWidth: maxWidth,
        copingWidthFt: copingWidthFt, copingActive: copingActive);
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
  final double       copingWidthFt;
  final bool         copingActive;
  const _RendererBody({required this.geo, this.maxWidth,
      this.copingWidthFt = 0.0, this.copingActive = false});

  @override
  ConsumerState<_RendererBody> createState() => _RendererBodyState();
}

class _RendererBodyState extends ConsumerState<_RendererBody> {
  bool _showDrainHint = true;
  final TransformationController _xfCtrl = TransformationController();
  double _zoom = 1.0;

  @override
  void dispose() {
    _xfCtrl.dispose();
    super.dispose();
  }

  void _zoomIn()  => _setZoom((_zoom + 0.25).clamp(0.5, 4.0));
  void _zoomOut() => _setZoom((_zoom - 0.25).clamp(0.5, 4.0));
  void _zoomReset() => _setZoom(1.0);

  void _setZoom(double z) {
    setState(() => _zoom = z);
    _xfCtrl.value = Matrix4.identity()..scale(z);
  }

  @override
  Widget build(BuildContext context) {
    final geo = widget.geo;
    final watershedZones = ref.watch(watershedZonesProvider);
    final insulation = ref.watch(insulationSystemProvider);
    final showWatershed = insulation.hasTaper && watershedZones.isNotEmpty;

    // Look up panel sequence for banding visualization
    PanelSequence? panelSequence;
    double minThickness = 1.0;
    if (showWatershed && insulation.taperDefaults != null) {
      final d = insulation.taperDefaults!;
      panelSequence = lookupPanelSequence(
        manufacturer: d.manufacturer,
        taperRate: d.taperRate,
        profileType: d.profileType,
      );
      minThickness = d.minThickness;
    }

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

      const labelPad = 70.0;
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

        // ── Zoom controls ──────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          _zoomBtn(Icons.zoom_out,   _zoomOut,  _zoom <= 0.5),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _zoomReset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text('${(_zoom * 100).round()}%',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 4),
          _zoomBtn(Icons.zoom_in,    _zoomIn,   _zoom >= 4.0),
          const SizedBox(width: 4),
          _zoomBtn(Icons.fit_screen, _zoomReset, false),
        ]),
        const SizedBox(height: 6),

        // ── Roof plan with pinch-zoom + pan ────────────────────────
        SizedBox(
          width: availWidth,
          height: canvasH,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              // Stack: InteractiveViewer for zoom/pan, transparent Listener
              // on top for tap-to-place drains. Listener bypasses gesture
              // disambiguation so taps always register on Flutter web.
              child: Stack(children: [
                InteractiveViewer(
                  transformationController: _xfCtrl,
                  minScale: 0.5,
                  maxScale: 4.0,
                  onInteractionEnd: (d) =>
                      setState(() => _zoom = _xfCtrl.value.getMaxScaleOnAxis()),
                  child: CustomPaint(
                    size: Size(availWidth, canvasH),
                    painter: _RoofPainter(
                      polygons:  polygons,
                      bounds:    bounds,
                      scale:     scale,
                      offset:    Offset(labelPad, labelPad),
                      windZones: geo.windZones,
                      drains:    geo.drainLocations,
                      scuppers:  geo.scupperLocations,
                      showWatershed: showWatershed,
                      lowPointCount: geo.drainLocations.length +
                          geo.scupperLocations.length,
                      panelSequence: panelSequence,
                      taperMinThickness: minThickness,
                      copingWidthFt: widget.copingWidthFt,
                      copingActive: widget.copingActive,
                    ),
                  ),
                ),
                // Transparent tap layer — captures single taps for drain placement
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerUp: (event) {
                      // Use pointer position directly in container coordinates,
                      // then apply inverse zoom/pan to get canvas coordinates.
                      final Matrix4 inv = Matrix4.inverted(_xfCtrl.value);
                      final canvasPos = MatrixUtils.transformPoint(
                          inv, event.localPosition);
                      _onTap(canvasPos, bounds, scale, labelPad, geo);
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),

        if (usedTypes.isNotEmpty) ...[
          const SizedBox(height: 10),
          _edgeTypeLegend(usedTypes.toList()..sort()),
        ],

        if (_showDrainHint && geo.drainLocations.isEmpty && geo.scupperLocations.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.touch_app, size: 13, color: AppTheme.textMuted),
              const SizedBox(width: 5),
              Expanded(child: Text(
                'Tap inside the roof for internal drains. Tap near an edge to place a scupper.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              )),
            ]),
          ),

        if (geo.drainLocations.isNotEmpty || geo.scupperLocations.isNotEmpty) ...[
          const SizedBox(height: 8),
          _drainList(geo),
        ],

        const SizedBox(height: 8),
        if (geo.windZones.perimeterZoneWidth > 0) _zoneSummary(geo),
      ]);
    });
  }

  Widget _zoomBtn(IconData icon, VoidCallback onPressed, bool disabled) {
    return InkWell(
      onTap: disabled ? null : onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: disabled ? AppTheme.surfaceAlt : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Icon(icon, size: 16,
            color: disabled ? AppTheme.textMuted : AppTheme.textSecondary),
      ),
    );
  }

  void _onTap(Offset tapPos, Rect bounds, double scale,
      double labelPad, RoofGeometry geo) {
    final roofX = (tapPos.dx - labelPad) / scale + bounds.left;
    final roofY = (tapPos.dy - labelPad) / scale + bounds.top;
    final notifier = ref.read(estimatorProvider.notifier);

    // Size removal/edge thresholds proportional to building dimensions
    final maxDim = max(bounds.width, bounds.height);
    final removeRadius = max(1.5, maxDim * 0.03); // 3% of max dim, min 1.5 ft
    final edgeThreshold = max(3.0, maxDim * 0.06); // 6% of max dim, min 3 ft

    // Check existing drains for removal
    for (int i = 0; i < geo.drainLocations.length; i++) {
      final d = geo.drainLocations[i];
      if (sqrt(pow(d.x - roofX, 2) + pow(d.y - roofY, 2)) < removeRadius) {
        notifier.removeDrain(i);
        return;
      }
    }

    final primaryPoly = _buildPolygon(geo.shapes.first);
    if (primaryPoly == null) return;

    // Check existing scuppers for removal
    for (int i = 0; i < geo.scupperLocations.length; i++) {
      final s = geo.scupperLocations[i];
      if (s.edgeIndex >= primaryPoly.length) continue;
      final a = primaryPoly[s.edgeIndex];
      final b = primaryPoly[(s.edgeIndex + 1) % primaryPoly.length];
      final sx = a.dx + (b.dx - a.dx) * s.position;
      final sy = a.dy + (b.dy - a.dy) * s.position;
      if (sqrt(pow(sx - roofX, 2) + pow(sy - roofY, 2)) < removeRadius) {
        notifier.removeScupper(i);
        return;
      }
    }

    // Find nearest polygon edge to tap position
    int nearestEdgeIdx = -1;
    double nearestEdgeDist = double.infinity;
    double nearestEdgePos = 0.0;
    for (int i = 0; i < primaryPoly.length; i++) {
      final a = primaryPoly[i];
      final b = primaryPoly[(i + 1) % primaryPoly.length];
      final (dist, pos) = _pointToSegment(Offset(roofX, roofY), a, b);
      if (dist < nearestEdgeDist) {
        nearestEdgeDist = dist;
        nearestEdgeIdx = i;
        nearestEdgePos = pos;
      }
    }

    // If tap is close to an edge, place a scupper there
    if (nearestEdgeIdx >= 0 && nearestEdgeDist < edgeThreshold) {
      notifier.addScupper(ScupperLocation(
        edgeIndex: nearestEdgeIdx,
        position: nearestEdgePos,
      ));
      setState(() => _showDrainHint = false);
      return;
    }

    // Otherwise place an internal drain (must be inside polygon bounds)
    if (!_computeBounds(primaryPoly).contains(Offset(roofX, roofY))) return;
    notifier.addDrain(DrainLocation(x: roofX, y: roofY));
    setState(() => _showDrainHint = false);
  }

  /// Returns (distance from point to segment, parameter t where 0=a, 1=b).
  (double, double) _pointToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return ((p - a).distance, 0.0);
    final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq).clamp(0.0, 1.0);
    final closestX = a.dx + dx * t;
    final closestY = a.dy + dy * t;
    final dist = sqrt(pow(p.dx - closestX, 2) + pow(p.dy - closestY, 2));
    return (dist, t);
  }

  Widget _zoneLegend(RoofGeometry geo) => Wrap(spacing: 12, runSpacing: 6, children: [
    _chip('Field Zone',     _kFieldColor,  _kOutlineColor),
    _chip('Perimeter Zone', _kPerimColor,  _kOutlineColor),
    _chip('Corner Zone',    _kCornerColor, Colors.white),
    if (geo.drainLocations.isNotEmpty) _chip('Drain', _kDrainColor, Colors.white),
    if (geo.scupperLocations.isNotEmpty) _chip('Scupper', const Color(0xFF8B5CF6), Colors.white),
  ]);

  Widget _chip(String label, Color fill, Color textColor) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: _kOutlineColor.withValues(alpha:0.3)),
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
            color: _kDrainColor.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kDrainColor.withValues(alpha:0.3)),
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
      for (int i = 0; i < geo.scupperLocations.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_outward, size: 12, color: const Color(0xFF8B5CF6)),
            const SizedBox(width: 4),
            Text('Scupper ${i + 1} (edge ${geo.scupperLocations[i].edgeIndex + 1})',
                style: TextStyle(fontSize: 11, color: const Color(0xFF8B5CF6),
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => ref.read(estimatorProvider.notifier).removeScupper(i),
              child: Icon(Icons.close, size: 12, color: const Color(0xFF8B5CF6)),
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
  final List<ScupperLocation> scuppers;
  final bool                showWatershed;
  final int                 lowPointCount;
  final PanelSequence?      panelSequence;
  final double              taperMinThickness;
  final double              copingWidthFt;
  final bool                copingActive;

  const _RoofPainter({
    required this.polygons,
    required this.bounds,
    required this.scale,
    required this.offset,
    required this.windZones,
    required this.drains,
    this.scuppers = const [],
    this.showWatershed = false,
    this.lowPointCount = 0,
    this.panelSequence,
    this.taperMinThickness = 1.0,
    this.copingWidthFt = 0.0,
    this.copingActive = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawZones(canvas);
    if (showWatershed && lowPointCount > 0) {
      _drawWatershedRegions(canvas);
    }
    _drawEdges(canvas);
    if (copingActive && copingWidthFt > 0) _drawCoping(canvas);
    _drawMeasurements(canvas);
    if (showWatershed && lowPointCount > 0) {
      _drawFlowArrows(canvas);
    }
    _drawDrains(canvas);
    _drawScuppers(canvas);
    _drawCompass(canvas, size);
  }

  /// Resolves all low points (drains + scuppers) to world coordinates.
  List<Offset> _lowPointsWorld() {
    final pts = <Offset>[];
    for (final d in drains) {
      pts.add(Offset(d.x, d.y));
    }
    if (polygons.isNotEmpty) {
      final primary = polygons.first.points;
      for (final s in scuppers) {
        if (s.edgeIndex >= primary.length) continue;
        final a = primary[s.edgeIndex];
        final b = primary[(s.edgeIndex + 1) % primary.length];
        pts.add(Offset(
          a.dx + (b.dx - a.dx) * s.position,
          a.dy + (b.dy - a.dy) * s.position,
        ));
      }
    }
    return pts;
  }

  /// Zone base colors (used at full taper thickness — farthest point).
  /// Drains: blue/green/orange; scuppers: purple/pink/cyan.
  static const _zoneColorsRGB = [
    [59, 130, 246],  // blue
    [139, 92, 246],  // purple
    [16, 185, 129],  // green
    [245, 158, 11],  // orange
    [236, 72, 153],  // pink
    [6, 182, 212],   // cyan
  ];

  /// Draws concentric row bands per zone. Each cell is colored by the panel
  /// letter that would be installed there (based on row = distance / 4 ft).
  /// Multiple zones get different base hues; within each zone the bands
  /// progress from light (near low point) to dark (ridge).
  void _drawWatershedRegions(Canvas canvas) {
    if (polygons.isEmpty) return;
    final primary = polygons.first.points;
    if (primary.length < 3) return;
    final lows = _lowPointsWorld();
    if (lows.isEmpty) return;

    canvas.save();
    canvas.clipPath(_polyPath(primary));

    double minX = primary.first.dx, maxX = minX;
    double minY = primary.first.dy, maxY = minY;
    for (final p in primary) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final w = maxX - minX;
    final h = maxY - minY;
    if (w <= 0 || h <= 0) {
      canvas.restore();
      return;
    }

    const panelWidthFt = 4.0;
    const gridN = 80;
    final stepX = w / gridN;
    final stepY = h / gridN;
    final cellW = stepX * scale + 2;
    final cellH = stepY * scale + 2;

    // First pass: determine per-zone max row to normalize band darkness
    final zoneMaxRow = List.filled(lows.length, 0);
    final nearestIdxGrid = List.generate(
        gridN, (_) => List.filled(gridN, 0));
    final rowGrid = List.generate(
        gridN, (_) => List.filled(gridN, 0));
    for (int ix = 0; ix < gridN; ix++) {
      for (int iy = 0; iy < gridN; iy++) {
        final cx = minX + (ix + 0.5) * stepX;
        final cy = minY + (iy + 0.5) * stepY;
        int nearestIdx = 0;
        double nearestDist = _dist(cx, cy, lows[0].dx, lows[0].dy);
        for (int i = 1; i < lows.length; i++) {
          final d = _dist(cx, cy, lows[i].dx, lows[i].dy);
          if (d < nearestDist) {
            nearestDist = d;
            nearestIdx = i;
          }
        }
        final row = (nearestDist / panelWidthFt).floor();
        nearestIdxGrid[ix][iy] = nearestIdx;
        rowGrid[ix][iy] = row;
        if (row > zoneMaxRow[nearestIdx]) {
          zoneMaxRow[nearestIdx] = row;
        }
      }
    }

    // Second pass: draw each cell with banded color
    for (int ix = 0; ix < gridN; ix++) {
      for (int iy = 0; iy < gridN; iy++) {
        final nearestIdx = nearestIdxGrid[ix][iy];
        final row = rowGrid[ix][iy];
        final maxRow = zoneMaxRow[nearestIdx];
        // Discrete band intensity: each row is a distinct step
        final rowFrac = maxRow > 0 ? (row / maxRow).clamp(0.0, 1.0) : 0.0;
        // 25 (nearest drain) → 130 (ridge), discrete per row
        final alpha = (25 + rowFrac * 105).round();
        final rgb = _zoneColorsRGB[nearestIdx % _zoneColorsRGB.length];
        final color = Color.fromARGB(alpha, rgb[0], rgb[1], rgb[2]);

        final cx = minX + (ix + 0.5) * stepX;
        final cy = minY + (iy + 0.5) * stepY;
        final sc = _ts(cx - stepX / 2, cy - stepY / 2);
        canvas.drawRect(
          Rect.fromLTWH(sc.dx - 1, sc.dy - 1, cellW, cellH),
          Paint()..color = color..style = PaintingStyle.fill,
        );
      }
    }

    // Third pass: draw band boundary lines between cells of different rows
    // in the same zone (concentric ring outlines)
    final ringPaint = Paint()
      ..color = const Color(0xFF1E40AF).withValues(alpha: 0.35)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (int ix = 0; ix < gridN; ix++) {
      for (int iy = 0; iy < gridN; iy++) {
        final row = rowGrid[ix][iy];
        final zone = nearestIdxGrid[ix][iy];
        final cx = minX + (ix + 0.5) * stepX;
        final cy = minY + (iy + 0.5) * stepY;
        final sc = _ts(cx - stepX / 2, cy - stepY / 2);
        // Check right neighbor
        if (ix + 1 < gridN &&
            nearestIdxGrid[ix + 1][iy] == zone &&
            rowGrid[ix + 1][iy] != row) {
          canvas.drawLine(
            Offset(sc.dx + cellW - 1, sc.dy),
            Offset(sc.dx + cellW - 1, sc.dy + cellH),
            ringPaint,
          );
        }
        // Check bottom neighbor
        if (iy + 1 < gridN &&
            nearestIdxGrid[ix][iy + 1] == zone &&
            rowGrid[ix][iy + 1] != row) {
          canvas.drawLine(
            Offset(sc.dx, sc.dy + cellH - 1),
            Offset(sc.dx + cellW, sc.dy + cellH - 1),
            ringPaint,
          );
        }
      }
    }

    canvas.restore();

    // Draw panel letter labels per band, along the line from low point to
    // farthest vertex in that zone. Labels drawn outside clip path so they
    // don't get clipped by the polygon edge at shallow bands.
    if (panelSequence != null) {
      _drawBandLabels(canvas, primary, lows);
    }
  }

  /// Labels each panel band with its panel letter, placed along the line from
  /// the low point to the farthest polygon vertex in that zone.
  void _drawBandLabels(Canvas canvas, List<Offset> primary, List<Offset> lows) {
    final seq = panelSequence!;
    const panelWidthFt = 4.0;

    for (int i = 0; i < lows.length; i++) {
      final lp = lows[i];

      // Find farthest vertex in this zone
      double farDist = 0;
      Offset farVertex = lp;
      for (final v in primary) {
        int nearestIdx = 0;
        double nearestDist = _dist(v.dx, v.dy, lows[0].dx, lows[0].dy);
        for (int j = 1; j < lows.length; j++) {
          final d = _dist(v.dx, v.dy, lows[j].dx, lows[j].dy);
          if (d < nearestDist) {
            nearestDist = d;
            nearestIdx = j;
          }
        }
        if (nearestIdx == i && nearestDist > farDist) {
          farDist = nearestDist;
          farVertex = v;
        }
      }

      if (farDist < panelWidthFt) continue;

      final numRows = (farDist / panelWidthFt).ceil();
      // Unit vector from low point toward farthest vertex
      final dx = farVertex.dx - lp.dx;
      final dy = farVertex.dy - lp.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1e-6) continue;
      final ux = dx / len;
      final uy = dy / len;

      for (int r = 0; r < numRows; r++) {
        final seqIdx = r % seq.panels.length;
        final cycle = r ~/ seq.panels.length;
        final panel = seq.panels[seqIdx];

        // Midpoint of this band along the primary axis
        final bandDist = (r + 0.5) * panelWidthFt;
        final lx = lp.dx + ux * bandDist;
        final ly = lp.dy + uy * bandDist;
        final screenPos = _ts(lx, ly);

        final label = cycle > 0
            ? '${panel.letter}${cycle > 0 ? '*' : ''}' // * = flat fill cycle
            : panel.letter;

        _drawText(
          canvas,
          label,
          screenPos,
          color: const Color(0xFF1E3A8A),
          fontSize: 10,
          bold: true,
        );
      }
    }
  }

  /// Draws flow arrows from far corners of each zone toward the low point.
  /// Simple heuristic: use polygon vertices; each vertex gets an arrow to its
  /// nearest low point.
  void _drawFlowArrows(Canvas canvas) {
    if (polygons.isEmpty) return;
    final primary = polygons.first.points;
    if (primary.length < 3) return;
    final lows = _lowPointsWorld();
    if (lows.isEmpty) return;

    final arrowPaint = Paint()
      ..color = const Color(0xFF1E40AF).withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final v in primary) {
      int nearestIdx = 0;
      double nearestDist = _dist(v.dx, v.dy, lows[0].dx, lows[0].dy);
      for (int i = 1; i < lows.length; i++) {
        final d = _dist(v.dx, v.dy, lows[i].dx, lows[i].dy);
        if (d < nearestDist) {
          nearestDist = d;
          nearestIdx = i;
        }
      }

      // Draw a short arrow from vertex-side toward the low point
      // Pull start a bit inward from vertex so it doesn't overlap edge
      final target = lows[nearestIdx];
      final dx = target.dx - v.dx;
      final dy = target.dy - v.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1e-6) continue;
      final ux = dx / len;
      final uy = dy / len;

      // Start at ~20% from vertex toward target; end at ~55% (short arrow)
      final startR = Offset(v.dx + ux * len * 0.20, v.dy + uy * len * 0.20);
      final endR = Offset(v.dx + ux * len * 0.55, v.dy + uy * len * 0.55);
      final s = _pt(startR);
      final e = _pt(endR);
      canvas.drawLine(s, e, arrowPaint);

      // Arrowhead at the end — two small lines at 30° angles
      final headLen = 5.0;
      final ang = atan2(e.dy - s.dy, e.dx - s.dx);
      final h1 = Offset(
        e.dx - headLen * cos(ang - 0.5),
        e.dy - headLen * sin(ang - 0.5),
      );
      final h2 = Offset(
        e.dx - headLen * cos(ang + 0.5),
        e.dy - headLen * sin(ang + 0.5),
      );
      canvas.drawLine(e, h1, arrowPaint);
      canvas.drawLine(e, h2, arrowPaint);
    }
  }

  double _dist(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return sqrt(dx * dx + dy * dy);
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
            _kOutlineColor.withValues(alpha:0.35), 1.0, 6, 4);
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

  /// Draw a shaded coping strip on the OUTSIDE of Parapet-tagged edges.
  void _drawCoping(Canvas canvas) {
    final copingPx = copingWidthFt * scale; // convert feet → screen pixels
    if (copingPx < 1) return;

    final fillPaint = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha:0.15) // parapet purple, light fill
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha:0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final poly in polygons) {
      final pts = poly.points;
      final shape = poly.shape;
      final n = pts.length;

      // Compute centroid for outward normal
      final screenPts = List.generate(n, (i) => _pt(pts[i]));
      final cx = screenPts.fold(0.0, (s, p) => s + p.dx) / n;
      final cy = screenPts.fold(0.0, (s, p) => s + p.dy) / n;

      for (int i = 0; i < n; i++) {
        final edgeType = (i < shape.edgeTypes.length) ? shape.edgeTypes[i] : 'Eave';
        if (edgeType != 'Parapet') continue;

        final a = screenPts[i];
        final b = screenPts[(i + 1) % n];
        final dir = b - a;
        final dist = dir.distance;
        if (dist < 1) continue;

        // Outward normal
        Offset norm = Offset(-dir.dy, dir.dx) / dist;
        final mid = (a + b) / 2;
        if ((norm.dx * (cx - mid.dx) + norm.dy * (cy - mid.dy)) > 0) {
          norm = -norm; // flip to point outward
        }

        // Draw coping strip as a quad: a→b on inside, offset outward by copingPx
        final ao = a + norm * copingPx;
        final bo = b + norm * copingPx;
        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(bo.dx, bo.dy)
          ..lineTo(ao.dx, ao.dy)
          ..close();
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
      }
    }
  }

  void _drawMeasurements(Canvas canvas) {
    for (final poly in polygons) {
      final pts   = poly.points;
      final shape = poly.shape;
      final edges = shape.edgeLengths;
      final n     = pts.length;

      // Compute polygon centroid in SCREEN coords for outward-normal check
      final screenPts = List.generate(n, (i) => _pt(pts[i]));
      final cx = screenPts.fold(0.0, (s, p) => s + p.dx) / n;
      final cy = screenPts.fold(0.0, (s, p) => s + p.dy) / n;
      final centroid = Offset(cx, cy);

      for (int i = 0; i < n && i < edges.length; i++) {
        final len = edges[i];
        if (len <= 0) continue;

        final a   = screenPts[i];
        final b   = screenPts[(i + 1) % n];
        final mid = (a + b) / 2;

        final edgeType = (i < shape.edgeTypes.length)
            ? shape.edgeTypes[i] : '';
        final color = edgeType.isNotEmpty
            ? _edgeColor(edgeType) : _kMeasureColor;

        final dir  = b - a;
        final dist = dir.distance;
        if (dist < 1) continue;

        // Left-of-travel normal
        Offset norm = Offset(-dir.dy, dir.dx) / dist;

        // If this normal points TOWARD the centroid (inward), flip it outward.
        // dot(norm, mid→centroid) > 0 means norm aims toward interior → flip.
        final toCentroid = centroid - mid;
        if ((norm.dx * toCentroid.dx + norm.dy * toCentroid.dy) > 0) {
          norm = -norm;
        }

        final lo = norm * 22;

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

  void _drawScuppers(Canvas canvas) {
    if (polygons.isEmpty) return;
    final primary = polygons.first.points;
    const scupperColor = Color(0xFF8B5CF6); // purple

    for (int i = 0; i < scuppers.length; i++) {
      final s = scuppers[i];
      if (s.edgeIndex >= primary.length) continue;
      final a = primary[s.edgeIndex];
      final b = primary[(s.edgeIndex + 1) % primary.length];

      // Compute scupper position on edge in roof coords
      final rx = a.dx + (b.dx - a.dx) * s.position;
      final ry = a.dy + (b.dy - a.dy) * s.position;
      final sc = _ts(rx, ry);

      // Compute outward normal to the edge (away from polygon centroid)
      final cx = primary.fold(0.0, (sum, p) => sum + p.dx) / primary.length;
      final cy = primary.fold(0.0, (sum, p) => sum + p.dy) / primary.length;
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final edgeLen = sqrt(dx * dx + dy * dy);
      if (edgeLen < 1e-6) continue;
      double nx = -dy / edgeLen;
      double ny = dx / edgeLen;
      // Flip if pointing toward centroid (we want outward)
      final midToCent = Offset(cx - rx, cy - ry);
      if (nx * midToCent.dx + ny * midToCent.dy > 0) {
        nx = -nx;
        ny = -ny;
      }

      // Edge direction in screen coords (perpendicular to normal)
      // Scupper rectangle: 18px wide along edge, 10px deep outward
      const halfW = 9.0;
      const depth = 10.0;
      final tx = -ny; // tangent along edge
      final ty = nx;
      final p1 = Offset(sc.dx + tx * halfW, sc.dy + ty * halfW);
      final p2 = Offset(sc.dx - tx * halfW, sc.dy - ty * halfW);
      final p3 = Offset(p2.dx + nx * depth, p2.dy + ny * depth);
      final p4 = Offset(p1.dx + nx * depth, p1.dy + ny * depth);

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy)
        ..close();

      canvas.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawPath(path,
          Paint()
            ..color = scupperColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);

      // Arrow pointing outward through the scupper (showing water flow out)
      final arrowStart = sc;
      final arrowEnd = Offset(sc.dx + nx * (depth + 4), sc.dy + ny * (depth + 4));
      canvas.drawLine(
        arrowStart,
        arrowEnd,
        Paint()
          ..color = scupperColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );

      // Label
      final labelPos = Offset(sc.dx + nx * (depth + 16), sc.dy + ny * (depth + 16));
      _drawText(canvas, 'S${i + 1}', labelPos,
          color: scupperColor, fontSize: 9, bold: true);
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
      polygons          != old.polygons  ||
      windZones         != old.windZones ||
      drains            != old.drains    ||
      scuppers          != old.scuppers  ||
      showWatershed     != old.showWatershed ||
      lowPointCount     != old.lowPointCount ||
      panelSequence     != old.panelSequence ||
      taperMinThickness != old.taperMinThickness;
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
