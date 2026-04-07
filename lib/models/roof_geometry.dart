import 'drainage_zone.dart';

/// lib/models/roof_geometry.dart
///
/// Immutable data classes for the Roof Geometry section.
/// Covers shapes, drain locations, and wind zone areas.
/// Matches INPUT_SPECIFICATIONS.md section 2.
///
/// v2 changes:
///   - Added edgeTypes to RoofShape (one per edge)
///   - Added kEdgeTypeOptions and kEdgeTypeColors
///   - Added kShapeTemplates: explicit per-shape turn sequences and
///     labeled diagram so the renderer can build a correct unified polygon

// ─── CONSTANTS ────────────────────────────────────────────────────────────────

/// Edge count by shape type. Matches spec table exactly.
const Map<String, int> kEdgeCountByShape = {
  'Rectangle': 4,
  'Square': 4,
  'L-Shape': 6,
  'T-Shape': 8,
  'U-Shape': 8,
};

const List<String> kShapeTypes = [
  'Rectangle',
  'Square',
  'L-Shape',
  'T-Shape',
  'U-Shape',
];

const List<String> kRoofSlopeOptions = [
  'Flat',
  '1/4:12',
  '1/2:12',
  '1:12',
  '2:12',
  'Custom',
];

/// Edge type options — matches the drawing key in the image.
/// Each edge of the roof gets one of these assigned.
const List<String> kEdgeTypeOptions = [
  'Eave',
  'Rake Edge',
  'Headwall',
  'Parapet',
  'Flat Drip Edge',
  'Hip',
  'Valley',
  'Ridge',
  'Clerestory',
];

/// Color coding for edge types in the renderer (matches industry drawing keys).
const Map<String, int> kEdgeTypeColors = {
  'Eave':           0xFFEF4444, // red
  'Rake Edge':      0xFF22C55E, // green
  'Headwall':       0xFF8B5CF6, // purple
  'Parapet':        0xFFF97316, // orange
  'Flat Drip Edge': 0xFF6366F1, // indigo (blue-purple like drawing key)
  'Hip':            0xFF0EA5E9, // sky
  'Valley':         0xFF8B5CF6, // purple
  'Ridge':          0xFFF59E0B, // amber
  'Clerestory':     0xFF10B981, // emerald
};

/// Alias kept for left_panel.dart compatibility.
const List<String> kEdgeTypes = kEdgeTypeOptions;

/// Default edge type when none is specified.
const String kDefaultEdgeType = 'Eave';

/// Default edge type per shape and edge position.
/// Used to pre-populate edge type dropdowns when a new shape is added.
const Map<String, List<String>> kShapeDefaultEdgeTypes = {
  'Rectangle': ['Eave', 'Rake Edge', 'Headwall', 'Rake Edge'],
  'Square':    ['Eave', 'Rake Edge', 'Headwall', 'Rake Edge'],
  'L-Shape':   ['Eave', 'Rake Edge', 'Headwall', 'Rake Edge', 'Headwall', 'Rake Edge'],
  'T-Shape':   ['Eave', 'Rake Edge', 'Headwall', 'Rake Edge',
                 'Headwall', 'Rake Edge', 'Headwall', 'Rake Edge'],
  'U-Shape':   ['Eave', 'Rake Edge', 'Headwall', 'Rake Edge',
                 'Eave', 'Rake Edge', 'Headwall', 'Rake Edge'],
};

/// Shape templates define:
///   - [turns]: +1 = turn left (CCW / outward corner),
///               -1 = turn right (CW / inward notch corner)
///     Starting direction: East (→). Applied after each edge.
///   - [edgeLabels]: diagram label for each edge (shown in input UI)
///   - [diagram]: ASCII diagram shown to user when picking a shape
///
/// All shapes walk the perimeter counter-clockwise (standard engineering),
/// starting at the bottom-left corner, first edge going East (→).
///
/// Rectangle / Square:
///   ┌──── E0 ────┐
///   E3           E1
///   └──── E2 ────┘  (4 edges, 4 left turns = closed)
///
/// L-Shape (standard, notch at top-right):
///   ┌── E2 ──┐
///   E3       E1
///   │    ┌── E0 ─────┐
///   │    E5           E1... (see diagram below)
///
///   Actual walk (start bottom-left → East):
///     E0: → (bottom, long)    turn L
///     E1: ↑ (right side)      turn L
///     E2: ← (top-right step)  turn R  ← inward notch
///     E3: ↓ (step down)       turn L
///     E4: ← (top-left span)   turn L
///     E5: ↓ (left side)       [closes back to start]
///
/// T-Shape (stem down, cross at top):
///   Walk: 8 edges, two inward notches (turns R at notch corners)
///
/// U-Shape (open at bottom):
///   Walk: 8 edges, two inward notches

class ShapeTemplate {
  final List<int>    turns;       // +1 = left, -1 = right (applied after each edge except last)
  final List<String> edgeLabels;  // shown next to each input field
  final String       diagram;     // ASCII art shown in UI tooltip

  const ShapeTemplate({
    required this.turns,
    required this.edgeLabels,
    required this.diagram,
  });
}

const Map<String, ShapeTemplate> kShapeTemplates = {
  'Rectangle': ShapeTemplate(
    turns: [1, 1, 1, 1],
    edgeLabels: [
      'Bottom (ft)',
      'Right side (ft)',
      'Top (ft)',
      'Left side (ft)',
    ],
    diagram: '┌──Top──┐\n│       │\nL       R\n│       │\n└─Bot───┘',
  ),
  'Square': ShapeTemplate(
    turns: [1, 1, 1, 1],
    edgeLabels: [
      'Bottom (ft)',
      'Right side (ft)',
      'Top (ft)',
      'Left side (ft)',
    ],
    diagram: '┌──Top──┐\n│       │\nL       R\n│       │\n└─Bot───┘',
  ),
  // L-Shape: notch cut from top-right corner
  // Start at bottom-left, walk clockwise exterior
  // Turns: L=outward corner (+1), R=inward notch (-1)
  //
  //  ┌──E4──┐
  //  E5     E3
  //  │   ┌──E2──┐
  //  │   │      E1
  //  └───E0─────┘
  //
  // Edges:  E0=bottom  E1=right  E2=top-right  E3=step-down  E4=top-left  E5=left
  // Turns after each edge:
  //   after E0 → turn L (outward bottom-right corner)
  //   after E1 → turn L (outward top-right corner) ... wait—this is the notch
  //
  // Correct walk for standard L (notch top-right):
  //   Start bottom-left facing →
  //   E0 → (bottom full width)   after: turn L (↑)
  //   E1 ↑ (right side short)    after: turn L (←)
  //   E2 ← (top-right overhang)  after: turn R (↓) ← inward notch
  //   E3 ↓ (step down)           after: turn L (←)
  //   E4 ← (top-left span)       after: turn L (↓)
  //   E5 ↓ (left full height)    [closes]
  'L-Shape': ShapeTemplate(
    turns: [1, 1, 1, -1, 1],   // 5 turns for 6 edges; R after E4 (inward notch)
    edgeLabels: [
      'E1 – Bottom (full width)',
      'E2 – Right side (tall, full height)',
      'E3 – Notch top (short segment, top-right)',
      'E4 – Notch wall down (E2 minus E6)',
      'E5 – Step left (horizontal)',
      'E6 – Left side (short, E2 minus E4)',
    ],
    diagram:
        '          ┌──E3──┐\n'
        '          │      E2\n'
        '  ┌──E5───┘      │\n'
        '  E6             │\n'
        '  └─────E1───────┘',
  ),
  // T-Shape: two notches — bottom-left and bottom-right
  // Stem projects down from center of top bar.
  //
  //  ┌────E6────┐
  //  E7         E5
  //  │   ┌─E4─┐ │
  //  │   E3   E1 │  ← wrong, fix:
  //
  // Correct T-Shape walk (stem down, bar across top):
  //   Start at bottom-left of stem, walk clockwise:
  //   E0 → stem bottom
  //   E1 ↑ right side of stem  turn L
  //   E2 → right step of bar   turn R (inward)
  //   E3 ↑ right side of bar   turn L
  //   E4 ← top of bar          turn L
  //   E5 ↓ left side of bar    turn L
  //   E6 → left step of bar    turn R (inward)
  //   E7 ↓ left side of stem   closes
  //
  // Turns: after E0=L, E1=R, E2=L, E3=L, E4=L, E5=R, E6=L, E7=(close)
  'T-Shape': ShapeTemplate(
    turns: [1, 1, -1, 1, 1, -1, 1], // 7 turns for 8 edges; R after E3 and E6 (notch corners)
    edgeLabels: [
      'E1 – Stem bottom width (ft)',
      'E2 – Stem right height (ft)',
      'E3 – Right bar extension (ft)',
      'E4 – Bar right side height (ft)',
      'E5 – Bar top full width (ft)',
      'E6 – Bar left side height (ft)',
      'E7 – Left bar extension (ft)',
      'E8 – Stem left height (ft)',
    ],
    diagram:
        '┌───────E5────────┐\n'
        'E6                E4\n'
        '└─E7─┐      ┌─E3─┘\n'
        '      E8    E2\n'
        '      └─E1─┘\n'
        '(stem projects down)',
  ),
  // U-Shape: open at bottom — two notches at bottom-left and bottom-right
  //   ┌─E6─┐     ┌─E4─┐
  //   E7   E5   E3    E3  ← fix
  //
  // Walk (start bottom-left of left arm, go East):
  //   E0 → bottom of left arm   turn L
  //   E1 ↑ outer right of left arm  turn L
  //   E2 → cross-bar top  ... actually U is complex.
  //
  // Simpler U walk (open bottom, arms go up):
  //   Start bottom-left facing →
  //   E0 → left arm bottom      turn L
  //   E1 ↑ left arm outer right turn R (inward: go back left into U)
  //   E2 ← inner top of left arm turn L ... 
  //
  // Standard U: two arms + connecting bar at top.
  // Walk CW from bottom-left of left arm:
  //   E0 → (left arm bottom)          turn L (↑)
  //   E1 ↑ (left arm outer height)    turn L (←)
  //   E2 ← (connecting top bar)       turn L (↓)
  //   E3 ↓ (right arm outer height)   turn L (→)
  //   E4 → (right arm bottom)         turn R (↑) ← inward
  //   E5 ↑ (right arm inner height)   turn L (←)
  //   E6 ← (inner gap / open span)    turn L (↓)  ← wait this isn't right either
  //
  // Let me define U differently — standard architectural U:
  //   Two arms of equal height, connected at top.
  //   Open gap at bottom.
  //   8 edges total.
  //
  //   ┌─E3─┐     ┌─E5─┐
  //   E2   E4   E6   ...
  //
  // Walk: start bottom-left of left arm facing →
  //   E0 → left arm bottom            after: L (↑)
  //   E1 ↑ left arm full height       after: L (←)
  //   E2 ← top bar (full width)       after: L (↓)
  //   E3 ↓ right arm full height      after: L (→)
  //   E4 → right arm bottom           after: R (↑) ← inward
  //   E5 ↑ right arm inner height     after: L (←)
  //   E6 ← inner gap (open at bottom) after: L (↓)
  //   E7 ↓ left arm inner height      closes back to start
  //
  //  Turns: L, L, L, L, R, L, L, L
  'U-Shape': ShapeTemplate(
    turns: [1, 1, 1, -1, -1, 1, 1], // 7 turns for 8 edges; R at both notch corners
    edgeLabels: [
      'E1 – Left arm bottom width (ft)',
      'E2 – Left arm outer height (ft)',
      'E3 – Top bar full width (ft)',
      'E4 – Right arm outer height (ft)',
      'E5 – Right arm bottom width (ft)',
      'E6 – Right arm inner height (ft)',
      'E7 – Inner gap width (ft)',
      'E8 – Left arm inner height (ft)',
    ],
    diagram:
        '┌─E2─┐   ┌─E4─┐\n'
        'E3   E1   E5   E3\n'
        '│    └─E8─┘    │\n'
        '└──────────────┘\n'
        '(open at bottom)',
  ),
};

// ─── DRAIN LOCATION ───────────────────────────────────────────────────────────

class DrainLocation {
  final double x;
  final double y;

  const DrainLocation({required this.x, required this.y});

  DrainLocation copyWith({double? x, double? y}) =>
      DrainLocation(x: x ?? this.x, y: y ?? this.y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrainLocation && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

// ─── ROOF SHAPE ───────────────────────────────────────────────────────────────

class RoofShape {
  final int          shapeIndex;   // 1-based
  final String       shapeType;    // From kShapeTypes
  final String       operation;    // "Add" or "Subtract"
  final List<double> edgeLengths;  // One entry per edge, feet
  final List<String> edgeTypes;    // One entry per edge, from kEdgeTypeOptions

  const RoofShape({
    required this.shapeIndex,
    this.shapeType = 'Rectangle',
    this.operation = 'Add',
    this.edgeLengths = const [],
    this.edgeTypes = const [],
  });

  factory RoofShape.initial(int index) {
    const type = 'Rectangle';
    final count = kEdgeCountByShape[type]!;
    return RoofShape(
      shapeIndex: index,
      shapeType: type,
      operation: 'Add',
      edgeLengths: List.filled(count, 0.0),
      edgeTypes: List.filled(count, 'Eave'),
    );
  }

  int get edgeCount => kEdgeCountByShape[shapeType] ?? 4;

  /// Shoelace (Gauss) formula — exact for any rectilinear polygon.
  /// Uses the same turn sequence as kShapeTemplates so it always matches
  /// the rendered shape and left_panel's local area display.
  double get calculatedArea {
    final e = edgeLengths;
    if (e.length < 4 || e.every((v) => v <= 0)) return 0.0;
    final tmpl = kShapeTemplates[shapeType];
    if (tmpl == null) return 0.0;
    final turns = tmpl.turns;
    const ddx = [1.0, 0.0, -1.0, 0.0];
    const ddy = [0.0, -1.0, 0.0, 1.0];
    final xs = <double>[0.0];
    final ys = <double>[0.0];
    var px = 0.0, py = 0.0, dir = 0;
    for (int i = 0; i < e.length; i++) {
      px += ddx[dir % 4] * e[i];
      py += ddy[dir % 4] * e[i];
      xs.add(px); ys.add(py);
      if (i < turns.length) dir = (dir + (turns[i] == 1 ? 1 : 3)) % 4;
    }
    xs.removeLast(); ys.removeLast();
    double a = 0.0;
    final n = xs.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      a += xs[i] * ys[j] - xs[j] * ys[i];
    }
    return (a / 2).abs();
  }

  double get calculatedPerimeter =>
      edgeLengths.fold(0.0, (sum, e) => sum + e);

  RoofShape copyWith({
    int?          shapeIndex,
    String?       shapeType,
    String?       operation,
    List<double>? edgeLengths,
    List<String>? edgeTypes,
  }) => RoofShape(
    shapeIndex:  shapeIndex  ?? this.shapeIndex,
    shapeType:   shapeType   ?? this.shapeType,
    operation:   operation   ?? this.operation,
    edgeLengths: edgeLengths ?? List.from(this.edgeLengths),
    edgeTypes:   edgeTypes   ?? List.from(this.edgeTypes),
  );

  RoofShape withShapeType(String newType) {
    final count = kEdgeCountByShape[newType] ?? 4;
    return RoofShape(
      shapeIndex:  shapeIndex,
      shapeType:   newType,
      operation:   operation,
      edgeLengths: List.filled(count, 0.0),
      edgeTypes:   List.filled(count, 'Eave'),
    );
  }

  RoofShape withEdgeLength(int index, double value) {
    final updated = List<double>.from(edgeLengths);
    if (index >= 0 && index < updated.length) updated[index] = value;
    return copyWith(edgeLengths: updated);
  }

  RoofShape withEdgeType(int index, String type) {
    final updated = List<String>.from(edgeTypes);
    if (index >= 0 && index < updated.length) updated[index] = type;
    return copyWith(edgeTypes: updated);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoofShape &&
          shapeIndex == other.shapeIndex &&
          shapeType  == other.shapeType &&
          operation  == other.operation &&
          _listEquals(edgeLengths, other.edgeLengths) &&
          _listEquals(edgeTypes,   other.edgeTypes);

  @override
  int get hashCode => Object.hash(
      shapeIndex, shapeType, operation,
      Object.hashAll(edgeLengths), Object.hashAll(edgeTypes));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; }
  return true;
}

// ─── WIND ZONES ───────────────────────────────────────────────────────────────

class WindZones {
  final double cornerZoneWidth;
  final double perimeterZoneWidth;
  final double cornerZoneArea;
  final double perimeterZoneArea;
  final double fieldZoneArea;

  const WindZones({
    this.cornerZoneWidth    = 0.0,
    this.perimeterZoneWidth = 0.0,
    this.cornerZoneArea     = 0.0,
    this.perimeterZoneArea  = 0.0,
    this.fieldZoneArea      = 0.0,
  });

  WindZones copyWith({
    double? cornerZoneWidth,
    double? perimeterZoneWidth,
    double? cornerZoneArea,
    double? perimeterZoneArea,
    double? fieldZoneArea,
  }) => WindZones(
    cornerZoneWidth:    cornerZoneWidth    ?? this.cornerZoneWidth,
    perimeterZoneWidth: perimeterZoneWidth ?? this.perimeterZoneWidth,
    cornerZoneArea:     cornerZoneArea     ?? this.cornerZoneArea,
    perimeterZoneArea:  perimeterZoneArea  ?? this.perimeterZoneArea,
    fieldZoneArea:      fieldZoneArea      ?? this.fieldZoneArea,
  );

  double get totalArea => cornerZoneArea + perimeterZoneArea + fieldZoneArea;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindZones &&
          cornerZoneWidth    == other.cornerZoneWidth &&
          perimeterZoneWidth == other.perimeterZoneWidth &&
          cornerZoneArea     == other.cornerZoneArea &&
          perimeterZoneArea  == other.perimeterZoneArea &&
          fieldZoneArea      == other.fieldZoneArea;

  @override
  int get hashCode => Object.hash(cornerZoneWidth, perimeterZoneWidth,
      cornerZoneArea, perimeterZoneArea, fieldZoneArea);
}

// ─── ROOF GEOMETRY ────────────────────────────────────────────────────────────

class RoofGeometry {
  final List<RoofShape>    shapes;
  final double             buildingHeight;
  final String             roofSlope;
  final double             customSlope;
  final List<DrainLocation> drainLocations;
  final double?            totalPerimeterOverride;
  final double?            totalAreaOverride;
  final int                perimeterCorners;
  final int                insideCorners;
  final int                outsideCorners;
  final WindZones          windZones;
  final List<ScupperLocation> scupperLocations;
  final List<DrainageZone> drainageZones;

  const RoofGeometry({
    this.shapes                = const [],
    this.buildingHeight        = 0.0,
    this.roofSlope             = 'Flat',
    this.customSlope           = 0.0,
    this.drainLocations        = const [],
    this.totalPerimeterOverride,
    this.totalAreaOverride,
    this.perimeterCorners      = 0,
    this.insideCorners         = 0,
    this.outsideCorners        = 0,
    this.windZones             = const WindZones(),
    this.scupperLocations      = const [],
    this.drainageZones         = const [],
  });

  factory RoofGeometry.initial() =>
      RoofGeometry(shapes: [RoofShape.initial(1)]);

  int get numberOfShapes => shapes.length;
  int get numberOfDrains => drainLocations.length;
  int get numberOfScuppers => scupperLocations.length;

  double get totalArea {
    if (totalAreaOverride != null) return totalAreaOverride!;
    double area = 0.0;
    for (final s in shapes) {
      area += s.operation == 'Subtract' ? -s.calculatedArea : s.calculatedArea;
    }
    return area.clamp(0.0, double.infinity);
  }

  double get totalPerimeter {
    if (totalPerimeterOverride != null) return totalPerimeterOverride!;
    if (shapes.isEmpty) return 0.0;
    return shapes.first.calculatedPerimeter;
  }

  RoofGeometry copyWith({
    List<RoofShape>?    shapes,
    double?             buildingHeight,
    String?             roofSlope,
    double?             customSlope,
    List<DrainLocation>? drainLocations,
    double?             totalPerimeterOverride,
    double?             totalAreaOverride,
    int?                perimeterCorners,
    int?                insideCorners,
    int?                outsideCorners,
    WindZones?          windZones,
    List<ScupperLocation>? scupperLocations,
    List<DrainageZone>? drainageZones,
  }) => RoofGeometry(
    shapes:                 shapes                ?? List.from(this.shapes),
    buildingHeight:         buildingHeight         ?? this.buildingHeight,
    roofSlope:              roofSlope              ?? this.roofSlope,
    customSlope:            customSlope            ?? this.customSlope,
    drainLocations:         drainLocations         ?? List.from(this.drainLocations),
    totalPerimeterOverride: totalPerimeterOverride ?? this.totalPerimeterOverride,
    totalAreaOverride:      totalAreaOverride      ?? this.totalAreaOverride,
    perimeterCorners:       perimeterCorners       ?? this.perimeterCorners,
    insideCorners:          insideCorners          ?? this.insideCorners,
    outsideCorners:         outsideCorners         ?? this.outsideCorners,
    windZones:              windZones              ?? this.windZones,
    scupperLocations:       scupperLocations       ?? List.from(this.scupperLocations),
    drainageZones:          drainageZones          ?? List.from(this.drainageZones),
  );

  RoofGeometry clearAreaOverride() => copyWith(totalAreaOverride: null);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoofGeometry &&
          _listEquals(shapes, other.shapes) &&
          buildingHeight        == other.buildingHeight &&
          roofSlope             == other.roofSlope &&
          customSlope           == other.customSlope &&
          _listEquals(drainLocations, other.drainLocations) &&
          totalPerimeterOverride == other.totalPerimeterOverride &&
          totalAreaOverride      == other.totalAreaOverride &&
          perimeterCorners       == other.perimeterCorners &&
          insideCorners          == other.insideCorners &&
          outsideCorners         == other.outsideCorners &&
          windZones              == other.windZones &&
          _listEquals(scupperLocations, other.scupperLocations) &&
          _listEquals(drainageZones, other.drainageZones);

  @override
  int get hashCode => Object.hash(
      Object.hashAll(shapes), buildingHeight, roofSlope, customSlope,
      Object.hashAll(drainLocations), totalPerimeterOverride, totalAreaOverride,
      perimeterCorners, insideCorners, outsideCorners, windZones,
      Object.hashAll(scupperLocations), Object.hashAll(drainageZones));
}

// ─── POLYGON BUILDER (shared by left_panel.dart and roof_renderer.dart) ──────

/// Builds the polygon vertex list by walking the perimeter edge-by-edge.
/// Start at (0,0) facing East; turn left (CCW) at each corner.
/// Screen-Y convention: up = negative Y (matches Flutter canvas).
/// Returns null if edges are fewer than 4 or all zero.
List<PolygonPoint>? buildPolygonPoints(List<double> edges,
    {String shapeType = 'Rectangle'}) {
  if (edges.length < 4) return null;
  if (edges.every((e) => e <= 0)) return null;
  final template = kShapeTemplates[shapeType];
  final turns = template?.turns ?? List.filled(edges.length, 1);
  const ddx = [1.0, 0.0, -1.0, 0.0];
  const ddy = [0.0, -1.0, 0.0, 1.0];
  final pts = <PolygonPoint>[const PolygonPoint(0, 0)];
  var x = 0.0, y = 0.0, dir = 0;
  for (int i = 0; i < edges.length; i++) {
    x += ddx[dir % 4] * edges[i];
    y += ddy[dir % 4] * edges[i];
    pts.add(PolygonPoint(x, y));
    if (i < turns.length) dir = (dir + (turns[i] == 1 ? 1 : 3)) % 4;
  }
  pts.removeLast();
  return pts;
}

class PolygonPoint {
  final double x, y;
  const PolygonPoint(this.x, this.y);
}
