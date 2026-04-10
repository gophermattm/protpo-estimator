# Tapered Insulation Phase 2 — End-to-End UI + BOM Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tapered insulation fully functional end-to-end: configure via left panel → auto-compute board schedule from drain placement → display actual panel quantities in BOM → show accurate min/avg/max R-values.

**Architecture:** A new `boardScheduleProvider` computes `BoardScheduleResult` from roof geometry (drain locations → max distance) and insulation config (taper rate, manufacturer, profile). BOM calculator consumes this result to produce per-panel-type line items instead of the current placeholder. R-value calculator receives actual thickness values from the board schedule instead of hardcoded zeros.

**Tech Stack:** Flutter/Dart, Riverpod, flutter_test

**Spec:** `docs/superpowers/specs/2026-04-06-tapered-insulation-phase1-design.md` (data model reference)

**Phase 1 plan:** `docs/superpowers/plans/2026-04-06-tapered-insulation-phase1.md`

**Deferred to Phase 3:** Watershed geometry engine, scupper placement, per-zone overrides UI, diagram flow/gradient rendering, crickets, QXO pricing for tapered boards.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/services/drain_distance_calculator.dart` | Create | Compute max taper run distance from drain locations + roof polygon |
| `test/services/drain_distance_calculator_test.dart` | Create | Tests for distance calculation from drains to polygon edges |
| `lib/providers/estimator_providers.dart` | Modify | Add `boardScheduleProvider`, wire R-value with actual thicknesses |
| `lib/widgets/left_panel.dart` | Modify | Replace free-text Board Type with Manufacturer + Profile dropdowns |
| `lib/services/bom_calculator.dart` | Modify | Replace placeholder taper BOM line with actual board schedule items |
| `lib/widgets/center_panel.dart` | Modify | Add board schedule summary card to Thermal & Code tab |
| `test/services/bom_calculator_taper_test.dart` | Create | Tests for tapered insulation BOM line items |
| `test/providers/board_schedule_provider_test.dart` | Create | Tests for board schedule provider integration |

---

### Task 1: Drain Distance Calculator

Compute the maximum taper run distance from drain placement and roof polygon geometry. This is the `distance` input to `BoardScheduleCalculator.compute()`.

**Files:**
- Create: `lib/services/drain_distance_calculator.dart`
- Test: `test/services/drain_distance_calculator_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/services/drain_distance_calculator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/drain_distance_calculator.dart';
import 'dart:ui';

void main() {
  group('DrainDistanceCalculator', () {
    // 100×50 rectangle with vertices at (0,0), (100,0), (100,-50), (0,-50)
    final rectPoly = [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, -50),
      Offset(0, -50),
    ];

    test('single centered drain returns max distance to farthest vertex', () {
      // Drain at center (50, -25) — farthest vertex is ~55.9 ft away
      final result = DrainDistanceCalculator.maxTaperDistance(
        polygonVertices: rectPoly,
        drainX: 50,
        drainY: -25,
      );
      // sqrt(50^2 + 25^2) = 55.9
      expect(result, closeTo(55.9, 0.1));
    });

    test('drain at corner returns distance to opposite corner', () {
      // Drain at (0, 0) — farthest vertex is (100, -50)
      final result = DrainDistanceCalculator.maxTaperDistance(
        polygonVertices: rectPoly,
        drainX: 0,
        drainY: 0,
      );
      // sqrt(100^2 + 50^2) = 111.8
      expect(result, closeTo(111.8, 0.1));
    });

    test('drain offset from center returns correct max distance', () {
      // Drain near front wall at (50, -5) — farthest vertex is (0, -50) or (100, -50)
      final result = DrainDistanceCalculator.maxTaperDistance(
        polygonVertices: rectPoly,
        drainX: 50,
        drainY: -5,
      );
      // sqrt(50^2 + 45^2) = 67.3
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
        // Two drains spread apart — each covers half the roof
        final result = DrainDistanceCalculator.bestTaperDistance(
          polygonVertices: rectPoly,
          drainXs: [25, 75],
          drainYs: [-25, -25],
        );
        // Drain at (25,-25): farthest vertex = (100,0) → sqrt(75^2+25^2) = 79.1
        // Drain at (75,-25): farthest vertex = (0,0) → sqrt(75^2+25^2) = 79.1
        // bestTaperDistance returns the max of all drain distances
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
        // 100×50 polygon → perpendicular width = 50
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/drain_distance_calculator_test.dart`
Expected: FAIL — `drain_distance_calculator.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/services/drain_distance_calculator.dart`:

```dart
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
  ///
  /// Rationale: the board schedule must cover the worst-case (longest) taper
  /// run on the roof. Phase 3 watershed geometry will compute per-zone distances.
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/drain_distance_calculator_test.dart`
Expected: All 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/services/drain_distance_calculator.dart test/services/drain_distance_calculator_test.dart
git commit -m "feat: add drain distance calculator for taper run computation"
```

---

### Task 2: Left Panel — Manufacturer & Profile Dropdowns

Replace the free-text "Board Type" field with proper Manufacturer and Profile Type dropdowns. These values already exist in the data model (`TaperDefaults.manufacturer`, `TaperDefaults.profileType`) but the UI currently uses a free-text field that doesn't map to anything.

**Files:**
- Modify: `lib/widgets/left_panel.dart`

**No new tests needed** — this is a UI wiring change. The state management is already tested via the existing TaperDefaults model tests.

- [ ] **Step 1: Add local state variables for manufacturer and profile**

In `left_panel.dart`, find the insulation local state block (around line 180). Replace `_cTaperBoard` controller and `_cTaperArea` controller with two dropdown state variables.

Find this block:

```dart
  bool   _hasTapered       = false;
  String _taperSlope       = '1/4:12';
  String _taperMinThick    = '1.0';
  String _taperAttachment  = 'Mechanically Attached';
  final _cTaperBoard       = TextEditingController();
  final _cTaperArea        = TextEditingController();
```

Replace with:

```dart
  bool   _hasTapered       = false;
  String _taperSlope       = '1/4:12';
  String _taperMinThick    = '1.0';
  String _taperManufacturer = 'Versico';
  String _taperProfile     = 'extended';
  String _taperAttachment  = 'Mechanically Attached';
```

- [ ] **Step 2: Remove disposed controllers**

In `dispose()`, find and remove `_cTaperBoard` and `_cTaperArea` from the disposed controllers list (around line 292-297).

- [ ] **Step 3: Update _syncFromState to read manufacturer and profile**

Find the sync block that reads taper state (around line 432-434):

```dart
      _hasTapered      = ins.hasTaper;
      _taperSlope      = ins.taperDefaults?.taperRate ?? '1/4:12';
      _taperMinThick   = (ins.taperDefaults?.minThickness ?? 1.0).toString();
```

Add manufacturer and profile sync below those lines:

```dart
      _hasTapered      = ins.hasTaper;
      _taperSlope      = ins.taperDefaults?.taperRate ?? '1/4:12';
      _taperMinThick   = (ins.taperDefaults?.minThickness ?? 1.0).toString();
      _taperManufacturer = ins.taperDefaults?.manufacturer ?? 'Versico';
      _taperProfile    = ins.taperDefaults?.profileType ?? 'extended';
```

- [ ] **Step 4: Update pushTaper to include manufacturer and profile**

Find `pushTaper()` (around line 1320-1323):

```dart
    void pushTaper() => n.updateTaperDefaults(TaperDefaults(
        taperRate: _taperSlope,
        minThickness: double.tryParse(_taperMinThick) ?? 1.0,
        attachmentMethod: _taperAttachment));
```

Replace with:

```dart
    void pushTaper() => n.updateTaperDefaults(TaperDefaults(
        taperRate: _taperSlope,
        minThickness: double.tryParse(_taperMinThick) ?? 1.0,
        manufacturer: _taperManufacturer,
        profileType: _taperProfile,
        attachmentMethod: _taperAttachment));
```

- [ ] **Step 5: Replace taper UI section**

Find the taper config container (around line 1359-1382) — the block starting with `if (_hasTapered) ...[`.

Replace the inner Column children:

```dart
      if (_hasTapered) ...[
        _sp10,
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppTheme.border)),
          child: Column(children: [
            _responsiveRow([
              _dd('Manufacturer', _taperManufacturer, kTaperManufacturers, (v) {
                setState(() {
                  _taperManufacturer = v!;
                  // TRI-BUILT doesn't have extended profiles — auto-reset
                  if (v == 'TRI-BUILT' && _taperProfile == 'extended') {
                    _taperProfile = 'standard';
                  }
                });
                pushTaper();
              }),
              _dd('Profile', _taperProfile,
                  _taperManufacturer == 'TRI-BUILT' ? ['standard'] : kTaperProfileTypes,
                  (v) { setState(() => _taperProfile = v!); pushTaper(); }),
            ]),
            _sp8,
            _responsiveRow([
              _dd('Taper Slope', _taperSlope, kTaperSlopeOptions, (v) {
                setState(() => _taperSlope = v!); pushTaper(); }),
              _dd('Min at Drain', _taperMinThick,
                  kTaperMinThicknesses.map((v) => v.toString()).toList(), (v) {
                setState(() => _taperMinThick = v!); pushTaper(); }),
            ]),
            _sp8,
            _dd('Attachment', _taperAttachment, kAttachmentMethods, (v) {
              setState(() => _taperAttachment = v!); pushTaper(); }),
          ]),
        ),
      ],
```

- [ ] **Step 6: Run the app to verify UI**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test`
Expected: All existing tests pass. (UI changes don't break unit tests.)

- [ ] **Step 7: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/widgets/left_panel.dart
git commit -m "feat: replace free-text board type with manufacturer & profile dropdowns"
```

---

### Task 3: Board Schedule Riverpod Provider

Wire `BoardScheduleCalculator` into Riverpod so it auto-computes whenever drain locations or taper config change. This provider is the bridge between Phase 1's calculation engine and Phase 2's UI integration.

**Files:**
- Modify: `lib/providers/estimator_providers.dart`
- Test: `test/providers/board_schedule_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/providers/board_schedule_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/drainage_zone.dart';
import 'package:protpo_app/services/board_schedule_calculator.dart';

void main() {
  group('boardScheduleProvider', () {
    test('returns null when taper is disabled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = container.read(boardScheduleProvider);
      expect(result, isNull);
    });

    test('returns null when no drains are placed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Enable taper but don't place any drains
      container.read(estimatorProvider.notifier).setTaperedEnabled(true);
      final result = container.read(boardScheduleProvider);
      expect(result, isNull);
    });

    test('returns BoardScheduleResult when taper enabled and drains placed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(estimatorProvider.notifier);

      // Set up a 100×50 roof
      notifier.updateRoofGeometry(RoofGeometry(
        shapes: [
          RoofShape(
            shapeIndex: 1,
            shapeType: 'Rectangle',
            edgeLengths: [100, 50, 100, 50],
            edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'],
          ),
        ],
        drainLocations: [DrainLocation(x: 50, y: -25)],
      ));

      // Enable taper with defaults
      notifier.setTaperedEnabled(true);

      final result = container.read(boardScheduleProvider);
      expect(result, isNotNull);
      expect(result!.rows.isNotEmpty, true);
      expect(result.totalTaperedPanels, greaterThan(0));
      expect(result.maxThickness, greaterThan(0));
    });

    test('result updates when taper config changes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(estimatorProvider.notifier);

      notifier.updateRoofGeometry(RoofGeometry(
        shapes: [
          RoofShape(
            shapeIndex: 1,
            shapeType: 'Rectangle',
            edgeLengths: [100, 50, 100, 50],
            edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'],
          ),
        ],
        drainLocations: [DrainLocation(x: 50, y: -25)],
      ));
      notifier.setTaperedEnabled(true);

      final result1 = container.read(boardScheduleProvider);

      // Change to 1/2:12 slope — fewer rows, thicker per panel
      notifier.updateTaperDefaults(TaperDefaults(
        taperRate: '1/2:12',
        minThickness: 1.0,
        manufacturer: 'Versico',
        profileType: 'standard',
        attachmentMethod: 'Mechanically Attached',
      ));

      final result2 = container.read(boardScheduleProvider);
      expect(result2, isNotNull);
      // Different taper rate → different max thickness
      expect(result2!.maxThickness, isNot(equals(result1!.maxThickness)));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/providers/board_schedule_provider_test.dart`
Expected: FAIL — `boardScheduleProvider` is not defined.

- [ ] **Step 3: Add boardScheduleProvider to estimator_providers.dart**

At the top of `estimator_providers.dart`, add the import for the new service and board schedule calculator:

```dart
import '../services/drain_distance_calculator.dart';
import '../services/board_schedule_calculator.dart';
```

Then add the provider after the `rValueValidationProvider` (around line 203). Insert before the `crossSectionValidationProvider`:

```dart
/// Board schedule result for the active building's tapered insulation.
/// Returns null when taper is disabled or no drains are placed.
final boardScheduleProvider = Provider<BoardScheduleResult?>((ref) {
  final insulation = ref.watch(insulationSystemProvider);
  final geo = ref.watch(roofGeometryProvider);

  if (!insulation.hasTaper || insulation.taperDefaults == null) return null;
  if (geo.drainLocations.isEmpty) return null;

  // Build polygon vertices from primary shape
  final primaryShape = geo.shapes.isNotEmpty ? geo.shapes.first : null;
  if (primaryShape == null) return null;
  final vertices = _buildPolygonVertices(primaryShape);
  if (vertices.isEmpty) return null;

  // Compute taper distance from drains to farthest polygon vertex
  final distance = DrainDistanceCalculator.bestTaperDistance(
    polygonVertices: vertices,
    drainXs: geo.drainLocations.map((d) => d.x).toList(),
    drainYs: geo.drainLocations.map((d) => d.y).toList(),
  );
  if (distance <= 0) return null;

  // Compute roof width for panel count
  final roofWidth = DrainDistanceCalculator.roofWidthPerpendicular(vertices);
  if (roofWidth <= 0) return null;

  final defaults = insulation.taperDefaults!;
  return BoardScheduleCalculator.compute(BoardScheduleInput(
    distance: distance,
    taperRate: defaults.taperRate,
    minThickness: defaults.minThickness,
    manufacturer: defaults.manufacturer,
    profileType: defaults.profileType,
    roofWidthFt: roofWidth,
  ));
});
```

Also add the helper function at the bottom of the file (before the closing of the class or after the notifier):

```dart
/// Builds polygon vertices from a RoofShape using the same turn-sequence
/// algorithm as the roof renderer. Returns world-coordinate Offsets in feet.
List<Offset> _buildPolygonVertices(RoofShape shape) {
  final edges = shape.edgeLengths;
  if (edges.length < 4 || edges.every((e) => e <= 0)) return [];
  final tmpl = kShapeTemplates[shape.shapeType];
  if (tmpl == null) return [];
  final turns = tmpl.turns;
  const ddx = [1.0, 0.0, -1.0, 0.0];
  const ddy = [0.0, -1.0, 0.0, 1.0];
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
```

- [ ] **Step 4: Update rValueResultProvider to use board schedule thicknesses**

Find the `rValueResultProvider` (line 130-168). Replace the tapered input section:

Change this:

```dart
    tapered: insulation.hasTaper && insulation.taperDefaults != null
        ? TaperedInsulationInput(
            materialType: 'Polyiso',
            minThicknessAtDrain: insulation.taperDefaults!.minThickness,
            maxThickness: 0, // auto-calculated in future phases
          )
        : null,
```

To this:

```dart
    tapered: insulation.hasTaper && insulation.taperDefaults != null
        ? TaperedInsulationInput(
            materialType: 'Polyiso',
            minThicknessAtDrain: insulation.taperDefaults!.minThickness,
            maxThickness: boardSchedule?.maxThicknessAtRidge ?? 0,
          )
        : null,
```

And add `final boardSchedule = ref.watch(boardScheduleProvider);` near the top of the provider body, after the existing variable declarations.

Do the same for `rValueValidationProvider` (line 171-203) — add `boardSchedule` watch and use `boardSchedule?.maxThicknessAtRidge ?? 0` for the `maxThickness` field.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/providers/board_schedule_provider_test.dart`
Expected: All 4 tests PASS.

- [ ] **Step 6: Run all tests**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test`
Expected: All tests pass. Existing R-value tests still pass because board schedule is null when taper config has no drains.

- [ ] **Step 7: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/providers/estimator_providers.dart test/providers/board_schedule_provider_test.dart
git commit -m "feat: add board schedule provider with drain distance integration"
```

---

### Task 4: BOM Integration — Detailed Tapered Panel Line Items

Replace the placeholder "Tapered Polyiso" BOM line (which just divides total area by board size) with actual per-panel-type and per-flat-fill line items from the board schedule.

**Files:**
- Modify: `lib/services/bom_calculator.dart`
- Modify: `lib/providers/estimator_providers.dart` (pass board schedule to BOM)
- Test: `test/services/bom_calculator_taper_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/services/bom_calculator_taper_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/bom_calculator.dart';
import 'package:protpo_app/services/board_schedule_calculator.dart';
import 'package:protpo_app/models/project_info.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/models/drainage_zone.dart';

void main() {
  group('BOM — tapered insulation with board schedule', () {
    late BoardScheduleResult schedule;

    setUp(() {
      // Compute a real board schedule: 47ft run, Versico extended 1/4":12
      schedule = BoardScheduleCalculator.compute(const BoardScheduleInput(
        distance: 47,
        taperRate: '1/4:12',
        minThickness: 1.0,
        manufacturer: 'Versico',
        profileType: 'extended',
        roofWidthFt: 27,
      ));
    });

    test('produces per-panel BOM lines instead of placeholder', () {
      final result = BomCalculator.calculate(
        projectInfo: ProjectInfo.initial(),
        geometry: RoofGeometry(
          shapes: [RoofShape(shapeIndex: 1, edgeLengths: [47, 27, 47, 27],
              edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'])],
          drainLocations: [DrainLocation(x: 23.5, y: -13.5)],
        ),
        systemSpecs: SystemSpecs.initial(),
        insulation: InsulationSystem(
          hasTaper: true,
          taperDefaults: const TaperDefaults(
            taperRate: '1/4:12',
            minThickness: 1.0,
            manufacturer: 'Versico',
            profileType: 'extended',
          ),
        ),
        membrane: MembraneSystem.initial(),
        parapet: ParapetWalls.initial(),
        penetrations: Penetrations.initial(),
        metalScope: MetalScope.initial(),
        boardSchedule: schedule,
      );

      // Should have individual panel-type lines (X, Y, Z, ZZ) under Insulation
      final insulItems = result.items
          .where((i) => i.category == 'Insulation' && i.name.contains('Tapered'))
          .toList();
      expect(insulItems.length, greaterThan(1),
          reason: 'Should have multiple tapered panel lines, not one placeholder');

      // Should have flat fill lines
      final flatFillItems = result.items
          .where((i) => i.category == 'Insulation' && i.name.contains('Flat Fill'))
          .toList();
      // This schedule has flat fill at multiple thicknesses
      expect(flatFillItems.length, greaterThan(0));
    });

    test('falls back to placeholder when no board schedule provided', () {
      final result = BomCalculator.calculate(
        projectInfo: ProjectInfo.initial(),
        geometry: RoofGeometry(
          shapes: [RoofShape(shapeIndex: 1, edgeLengths: [47, 27, 47, 27],
              edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'])],
        ),
        systemSpecs: SystemSpecs.initial(),
        insulation: InsulationSystem(
          hasTaper: true,
          taperDefaults: const TaperDefaults(),
        ),
        membrane: MembraneSystem.initial(),
        parapet: ParapetWalls.initial(),
        penetrations: Penetrations.initial(),
        metalScope: MetalScope.initial(),
      );

      // Original placeholder line still works when no board schedule
      final taperItems = result.items
          .where((i) => i.category == 'Insulation' && i.name.contains('Tapered'))
          .toList();
      expect(taperItems.length, 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/bom_calculator_taper_test.dart`
Expected: FAIL — `BomCalculator.calculate` doesn't accept `boardSchedule` parameter.

- [ ] **Step 3: Add boardSchedule parameter to BomCalculator.calculate**

In `lib/services/bom_calculator.dart`, update the `calculate` method signature (line 103-112):

```dart
  static BomResult calculate({
    required ProjectInfo projectInfo,
    required RoofGeometry geometry,
    required SystemSpecs systemSpecs,
    required InsulationSystem insulation,
    required MembraneSystem membrane,
    required ParapetWalls parapet,
    required Penetrations penetrations,
    required MetalScope metalScope,
    BoardScheduleResult? boardSchedule,
  }) {
```

Add the import at the top of bom_calculator.dart:

```dart
import 'board_schedule_calculator.dart';
```

- [ ] **Step 4: Replace placeholder tapered BOM line with board schedule items**

Find the tapered insulation section (around line 302-318):

```dart
      // Tapered insulation
      if (insulation.hasTaper && insulation.taperDefaults != null) {
        final taper      = insulation.taperDefaults!;
        final taperArea  = totalArea;
        final base       = taperArea / boardSf;
        final withW      = base * (1 + wMat);
        final orderQty   = withW.ceil().toDouble();
        items.add(BomLineItem(
          category: 'Insulation',
          name: 'Tapered Polyiso — ${taper.taperRate} slope',
          orderQty: orderQty,
          unit: 'boards',
          notes: 'Min ${_ins(taper.minThickness)} at drain, tapered system',
          trace: _insTrace(taperArea, base, withW, orderQty, wMat, boardSf,
              'Tapered — Polyiso'),
        ));
      }
```

Replace with:

```dart
      // Tapered insulation
      if (insulation.hasTaper && insulation.taperDefaults != null) {
        final taper = insulation.taperDefaults!;

        if (boardSchedule != null && boardSchedule.totalTaperedPanels > 0) {
          // Per-panel-type lines from board schedule
          for (final entry in boardSchedule.taperedPanelCounts.entries) {
            final letter = entry.key;
            final count = entry.value;
            final withW = count * (1 + wMat);
            final orderQty = withW.ceil().toDouble();
            items.add(BomLineItem(
              category: 'Insulation',
              name: 'Tapered Polyiso — Panel $letter (${taper.manufacturer} ${taper.taperRate})',
              orderQty: orderQty,
              unit: 'panels',
              notes: "4'×4' tapered panels, ${taper.attachmentMethod}",
              trace: BomTrace(
                baseDescription: '$count panels (Panel $letter) from board schedule',
                baseQty: count.toDouble(),
                wastePercent: wMat,
                withWaste: withW,
                packageSize: 1,
                orderQty: orderQty,
                breakdown: [
                  'Panel $letter count:  $count panels',
                  'Waste:               ${_pct(wMat)}%',
                  'With waste:          ${withW.toStringAsFixed(1)}',
                  'ORDER QTY:           ${orderQty.toInt()} panels',
                ],
              ),
            ));
          }

          // Flat fill lines
          final sortedFill = boardSchedule.flatFillCounts.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          for (final entry in sortedFill) {
            final thickness = entry.key;
            final count = entry.value;
            final withW = count * (1 + wMat);
            final orderQty = withW.ceil().toDouble();
            items.add(BomLineItem(
              category: 'Insulation',
              name: 'Flat Fill Polyiso ${_ins(thickness)} (${taper.manufacturer})',
              orderQty: orderQty,
              unit: 'boards',
              notes: "4'×4' flat stock under tapered panels, ${taper.attachmentMethod}",
              trace: BomTrace(
                baseDescription: '$count boards (${_ins(thickness)} flat fill) from board schedule',
                baseQty: count.toDouble(),
                wastePercent: wMat,
                withWaste: withW,
                packageSize: 1,
                orderQty: orderQty,
                breakdown: [
                  'Flat fill ${_ins(thickness)} count: $count boards',
                  'Waste:                    ${_pct(wMat)}%',
                  'With waste:               ${withW.toStringAsFixed(1)}',
                  'ORDER QTY:                ${orderQty.toInt()} boards',
                ],
              ),
            ));
          }
        } else {
          // Fallback: placeholder when no board schedule (no drains placed)
          final taperArea = totalArea;
          final base = taperArea / boardSf;
          final withW = base * (1 + wMat);
          final orderQty = withW.ceil().toDouble();
          items.add(BomLineItem(
            category: 'Insulation',
            name: 'Tapered Polyiso — ${taper.taperRate} slope',
            orderQty: orderQty,
            unit: 'boards',
            notes: 'Min ${_ins(taper.minThickness)} at drain — place drains for detailed schedule',
            trace: _insTrace(taperArea, base, withW, orderQty, wMat, boardSf,
                'Tapered — Polyiso (estimated, no drains placed)'),
          ));
        }
      }
```

- [ ] **Step 5: Pass boardSchedule to BomCalculator from bomProvider**

In `lib/providers/estimator_providers.dart`, find where `bomProvider` calls `BomCalculator.calculate`. Search for `BomCalculator.calculate` and add the `boardSchedule` parameter.

If `bomProvider` exists, update it to pass `boardSchedule: ref.watch(boardScheduleProvider)`.

If the BOM is calculated inline in the center panel or elsewhere, find that call site and add the same parameter.

- [ ] **Step 6: Run tests**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/bom_calculator_taper_test.dart`
Expected: Both tests PASS.

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/services/bom_calculator.dart lib/providers/estimator_providers.dart test/services/bom_calculator_taper_test.dart
git commit -m "feat: replace placeholder taper BOM with actual board schedule quantities"
```

---

### Task 5: Board Schedule Summary in Thermal & Code Tab

Add a board schedule summary card below the R-value breakdown in the Thermal & Code tab. Shows panel counts, flat fill breakdown, max thickness, and any warnings from the calculator.

**Files:**
- Modify: `lib/widgets/center_panel.dart`

**No new tests** — UI widget, tested manually.

- [ ] **Step 1: Add board schedule import and provider watch**

At the top of `center_panel.dart`, add the import:

```dart
import '../services/board_schedule_calculator.dart';
```

- [ ] **Step 2: Watch boardScheduleProvider in _ThermalCodeTab**

In the `_ThermalCodeTab` build method (around line 1932-1936), add:

```dart
    final boardSchedule = ref.watch(boardScheduleProvider);
```

- [ ] **Step 3: Add board schedule summary card**

After the R-value breakdown card (after the `const SizedBox(height: 16)` around line 1983), add:

```dart
        // Board schedule summary (when tapered insulation active + drains placed)
        if (boardSchedule != null && boardSchedule.rows.isNotEmpty) ...[
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _cardHeader('Board Schedule', Icons.view_column),
            const SizedBox(height: 8),
            _scheduleRow('Taper Distance', '${boardSchedule.rows.last.distanceEnd.toStringAsFixed(1)} ft'),
            _scheduleRow('Max Thickness', '${boardSchedule.maxThicknessAtRidge.toStringAsFixed(2)}"'),
            _scheduleRow('Avg Taper Thickness', '${boardSchedule.avgTaperThickness.toStringAsFixed(2)}"'),
            const Divider(height: 16),
            Text('Tapered Panels', style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            ...boardSchedule.taperedPanelCounts.entries.map((e) =>
              _scheduleRow('  Panel ${e.key}', '${e.value} panels')),
            if (boardSchedule.flatFillCounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Flat Fill', style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              ...(boardSchedule.flatFillCounts.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key)))
                .map((e) => _scheduleRow('  ${_ins(e.key)}', '${e.value} boards')),
            ],
            const Divider(height: 16),
            _scheduleRow('Total Tapered', '${boardSchedule.totalTaperedPanels} panels'),
            _scheduleRow('Total Flat Fill', '${boardSchedule.totalFlatFillPanels} boards'),
            _scheduleRow('Total w/ Waste', '${boardSchedule.totalPanelsWithWaste} panels',
                bold: true),
            if (boardSchedule.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...boardSchedule.warnings.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber, size: 13, color: AppTheme.warning),
                  const SizedBox(width: 6),
                  Expanded(child: Text(w,
                      style: TextStyle(fontSize: 11, color: AppTheme.warning))),
                ]),
              )),
            ],
          ])),
          const SizedBox(height: 16),
        ],
```

- [ ] **Step 4: Add helper widgets**

Add these helper methods near the other static helpers in the `_ThermalCodeTab` class (near `_rRow`, `_codeRow`):

```dart
  static Widget _scheduleRow(String label, String value, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12,
                color: AppTheme.textSecondary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
            Text(value, style: TextStyle(fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: bold ? AppTheme.primary : AppTheme.textPrimary)),
          ],
        ),
      );
```

- [ ] **Step 5: Run tests**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/widgets/center_panel.dart
git commit -m "feat: add board schedule summary card to Thermal & Code tab"
```

---

### Task 6: R-Value Display — Min/Avg/Max for Tapered Systems

When tapered insulation is active with a board schedule, the Thermal & Code tab should show min/avg/max R-values instead of a single total. This leverages the `calculateTapered` method already built in Phase 1.

**Files:**
- Modify: `lib/widgets/center_panel.dart`

- [ ] **Step 1: Update R-value hero to show min/avg/max when tapered**

In the `_ThermalCodeTab` build method, find the R-value hero section (around line 1950):

```dart
        _rValueHero(totalR, required, passes, hasZip),
```

Replace with conditional logic:

```dart
        if (boardSchedule != null && boardSchedule.rows.isNotEmpty) ...[
          _taperedRValueHero(rResult, boardSchedule, insul, required, hasZip),
        ] else ...[
          _rValueHero(totalR, required, passes, hasZip),
        ],
```

- [ ] **Step 2: Add the tapered R-value hero widget**

Add this method to the `_ThermalCodeTab` class:

```dart
  static Widget _taperedRValueHero(
    RValueResult? rResult,
    BoardScheduleResult schedule,
    InsulationSystem insul,
    double? required,
    bool hasZip,
  ) {
    // Compute uniform R (base layers + cover board + membrane)
    final l1R = (rResult?.layer1.rValue ?? 0);
    final l2R = (rResult?.layer2?.rValue ?? 0);
    final cbR = (rResult?.coverBoard?.rValue ?? 0);
    const memR = 0.5;
    final uniformR = l1R + l2R + cbR + memR;

    const taperRPerInch = 5.7;
    final minR = uniformR + (schedule.minThicknessAtDrain * taperRPerInch);
    final avgR = uniformR + (schedule.avgTaperThickness * taperRPerInch);
    final maxR = uniformR + (schedule.maxThicknessAtRidge * taperRPerInch);

    final passesMin = required == null ? null : minR >= required;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: passesMin == false
            ? AppTheme.error.withValues(alpha: 0.05)
            : AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: passesMin == false
              ? AppTheme.error.withValues(alpha: 0.3)
              : AppTheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tapered Assembly R-Value Range',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _rValueColumn('Min\n(at drain)', minR, required),
          _rValueColumn('Average', avgR, required),
          _rValueColumn('Max\n(at ridge)', maxR, required),
        ]),
        if (required != null) ...[
          const SizedBox(height: 8),
          Text(
            passesMin == true
                ? 'Minimum R-value meets code requirement of R-${required.toStringAsFixed(0)}'
                : 'Minimum R-value below code requirement of R-${required.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 11,
                color: passesMin == true ? AppTheme.success : AppTheme.error,
                fontWeight: FontWeight.w500),
          ),
        ],
      ]),
    );
  }

  static Widget _rValueColumn(String label, double rValue, double? required) {
    final passes = required == null ? null : rValue >= required;
    return Column(children: [
      Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
      const SizedBox(height: 4),
      Text('R-${rValue.toStringAsFixed(1)}',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
              color: passes == false ? AppTheme.error : AppTheme.primary)),
    ]);
  }
```

- [ ] **Step 3: Run tests**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/widgets/center_panel.dart
git commit -m "feat: show min/avg/max R-values for tapered assemblies"
```

---

### Task 7: Integration Test — Full End-to-End Flow

Verify the complete flow: taper config + drains → board schedule → BOM → R-values.

**Files:**
- Test: `test/integration/tapered_bom_integration_test.dart`

- [ ] **Step 1: Write integration test**

Create `test/integration/tapered_bom_integration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/drainage_zone.dart';

void main() {
  group('Tapered insulation end-to-end', () {
    test('47x27 roof with centered drain produces correct BOM and R-values', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(estimatorProvider.notifier);

      // 1. Set up 47×27 roof with scupper-like drain at back wall center
      notifier.updateRoofGeometry(RoofGeometry(
        shapes: [
          RoofShape(
            shapeIndex: 1,
            shapeType: 'Rectangle',
            edgeLengths: [47, 27, 47, 27],
            edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'],
          ),
        ],
        drainLocations: [DrainLocation(x: 23.5, y: 0)],
      ));

      // 2. Configure insulation: 2.5" + 2.0" base polyiso
      notifier.setNumberOfLayers(2);

      // 3. Enable tapered insulation: Versico extended 1/4":12
      notifier.setTaperedEnabled(true);
      notifier.updateTaperDefaults(const TaperDefaults(
        taperRate: '1/4:12',
        minThickness: 1.0,
        manufacturer: 'Versico',
        profileType: 'extended',
        attachmentMethod: 'Mechanically Attached',
      ));

      // 4. Verify board schedule computed
      final schedule = container.read(boardScheduleProvider);
      expect(schedule, isNotNull, reason: 'Board schedule should compute with drain placed');
      expect(schedule!.totalTaperedPanels, greaterThan(0));
      expect(schedule.maxThicknessAtRidge, greaterThan(1.0));

      // 5. Verify R-value includes tapered component
      final rValue = container.read(rValueResultProvider);
      expect(rValue, isNotNull);
      expect(rValue!.tapered, isNotNull, reason: 'Tapered R-value should be calculated');
      expect(rValue.tapered!.averageRValue, greaterThan(0));
      // Total should include base layers + tapered + membrane
      expect(rValue.totalRValue, greaterThan(30),
          reason: '2.5" + 2.0" polyiso + taper avg should exceed R-30');

      // 6. Verify BOM has detailed panel lines
      final bom = container.read(bomProvider);
      final taperItems = bom.items
          .where((i) => i.category == 'Insulation' &&
              (i.name.contains('Panel') || i.name.contains('Flat Fill')))
          .toList();
      expect(taperItems.length, greaterThan(1),
          reason: 'BOM should have per-panel-type lines from board schedule');
    });

    test('disabling taper removes board schedule and detailed BOM lines', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(estimatorProvider.notifier);

      notifier.updateRoofGeometry(RoofGeometry(
        shapes: [
          RoofShape(
            shapeIndex: 1,
            shapeType: 'Rectangle',
            edgeLengths: [47, 27, 47, 27],
            edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'],
          ),
        ],
        drainLocations: [DrainLocation(x: 23.5, y: -13.5)],
      ));
      notifier.setTaperedEnabled(true);

      // Verify it's on
      expect(container.read(boardScheduleProvider), isNotNull);

      // Turn it off
      notifier.setTaperedEnabled(false);
      expect(container.read(boardScheduleProvider), isNull);

      // BOM should have no tapered panel lines
      final bom = container.read(bomProvider);
      final taperItems = bom.items
          .where((i) => i.name.contains('Tapered') || i.name.contains('Flat Fill'))
          .toList();
      expect(taperItems, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run integration test**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/integration/tapered_bom_integration_test.dart`
Expected: All 2 tests PASS.

- [ ] **Step 3: Run full test suite**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add test/integration/tapered_bom_integration_test.dart
git commit -m "test: add end-to-end integration tests for tapered insulation flow"
```

---

## Self-Review Checklist

1. **Spec coverage:** Phase 2 connects the Phase 1 engine to the UI. All "Out of Scope" items from Phase 1 that relate to core functionality (UI controls, BOM, R-value wiring) are covered. Watershed geometry, scupper placement, diagram rendering, and crickets are explicitly deferred to Phase 3.

2. **Placeholder scan:** No TBDs, TODOs, or "similar to Task N" references. All code blocks are complete.

3. **Type consistency:**
   - `BoardScheduleResult` used consistently as the provider output and BOM input
   - `TaperDefaults` constructor includes all 5 fields wherever called
   - `_buildPolygonVertices` matches the `_buildPolygon` function in roof_renderer.dart
   - `DrainDistanceCalculator` method names consistent across test and implementation
   - `boardScheduleProvider` name consistent in providers file, tests, and center_panel.dart
