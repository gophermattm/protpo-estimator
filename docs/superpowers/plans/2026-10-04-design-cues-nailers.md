# Design Cues, Headwalls, Edge Metal, Nailers, Nailbase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the BOM follow the design inputs: geometry-driven wall/edge LF, headwall flashing, adhesive only when called for (VersiWeld pails default, CAV-GRIP option), edge metal per edge type, perimeter wood nailers, nailbase cover board.

**Architecture:** Model changes first (`MetalScope`, `ParapetWalls`, `CoverBoard`, adhesive constants), then a pure `computeEdgeTotals` + notifier `applyEdgeTotals` that make Project Geometry the source of truth, then BOM sections (shared wall-flashing helper, per-edge metal, nailers, nailbase), then the left panel UI. Every behavior is unit-tested at the model/service/provider layer; UI is verified with `flutter analyze` and a live run.

**Tech Stack:** Flutter/Dart, Riverpod, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-04-design-cues-nailers-design.md`

## Global Constraints

- Adhesive options exactly: `VersiWeld TPO Bonding Adhesive — 5 Gal Pails` (default) and `CAV-GRIP 3V Spray`.
- VersiWeld coverage 60 sf/gal, 5-gal pails. CAV-GRIP ~2,000 sf/#40 cylinder + UN-TACK 1:1 (unchanged).
- Versico short-wall rule: no wall adhesive when height ≤ 12", or ≤ 18" with `Termination Bar`.
- Wall TPO strip = (height/12 + 0.33) × LF.
- Edge-metal buckets: Eave, Rake Edge, Flat Drip Edge. Hip/Valley/Ridge add to no metal bucket.
- Nailer default `2x6`; options `2x6`, `2x8`, `2x10`; plies = ceil(flat stack / 1.5), min 1; 16' boards; 2 rows @ 12" o.c.
- Nailbase thicknesses 1.5–4.0" with LTTR R 6.3/9.2/12.0/15.0/18.0/21.1 (Hunter H-Shield NB TDS).
- Needs Validation labels, verbatim: `Needs Validation for nailer fastener spacing`, `Needs Validation for nailer height at tapered high edges`.
- No commit, push, or deploy unless the user asks. Commit steps below are prepared but run only on approval.

## Review Focus

1. Saved jobs from before this change (legacy `dripEdgeLF`, `edgeMetalType`, `adhesiveType: 'VersiWeld TPO Bonding Adhesive'`, no cover board attachment) must load with the same scope, not zeros. → Task 1, 2, 4, 7 tests.
2. A job with no drawn edges (manual LF entry) must keep manually entered parapet/edge LF; geometry sync must not wipe it. → Task 3 test `no edges leaves manual values`.
3. Parapet with LF but height 0 must not emit adhesive (≤12" rule) and must not crash on 0 height. → Task 5 test.
4. Switching cover board type Nailbase ↔ HD Polyiso must leave a thickness valid for the new type. → Task 7 test on `coverBoardThicknessesFor` + Task 9 UI step.
5. Multi-building jobs: `applyEdgeTotals` must change only the active building. → Task 3 test.

---

### Task 1: MetalScope edge buckets + nailer fields

**Files:**
- Modify: `lib/models/section_models.dart` (MetalScope, ~lines 386–465)
- Modify: `lib/services/serialization.dart` (`_metalScopeToJson` / `_metalScopeFromJson`, ~506–529)
- Modify: `lib/providers/estimator_providers.dart` (~766–781)
- Test: `test/models/metal_scope_test.dart` (create)

**Interfaces:**
- Produces: `MetalScope` fields `eaveLF`, `rakeLF`, `flatDripLF`, `eaveMetalType`, `rakeMetalType`, `flatDripMetalType`, `hasNailers`, `nailerWidth`; getters `dripEdgeLF` (sum), `edgeMetalType` (= `eaveMetalType`), `nailerLF` (= `dripEdgeLF`); constants `kEdgeMetalEdgeTypes`, `kNailerWidths`; public `metalScopeToJson` / `metalScopeFromJson`; notifier `updateEdgeMetalType(String edgeType, String type)`, `updateEdgeMetalLF(String edgeType, double lf)`, `setNailersEnabled(bool)`, `updateNailerWidth(String)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/models/metal_scope_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/services/serialization.dart';

void main() {
  test('dripEdgeLF sums the three buckets', () {
    const m = MetalScope(eaveLF: 100, rakeLF: 50, flatDripLF: 25);
    expect(m.dripEdgeLF, 175);
    expect(m.nailerLF, 175);
  });

  test('defaults', () {
    const m = MetalScope();
    expect(m.eaveMetalType, 'TPO-Coated Drip Edge');
    expect(m.hasNailers, false);
    expect(m.nailerWidth, '2x6');
  });

  test('legacy dripEdgeLF/edgeMetalType migrate to eave + all types', () {
    final m = metalScopeFromJson({'dripEdgeLF': 300.0, 'edgeMetalType': 'Gravel Stop'});
    expect(m.eaveLF, 300);
    expect(m.rakeLF, 0);
    expect(m.eaveMetalType, 'Gravel Stop');
    expect(m.rakeMetalType, 'Gravel Stop');
    expect(m.flatDripMetalType, 'Gravel Stop');
  });

  test('round trip', () {
    const m = MetalScope(eaveLF: 10, rakeLF: 20, flatDripLF: 30,
        rakeMetalType: 'ES-1 (Low Profile)', hasNailers: true, nailerWidth: '2x8');
    expect(metalScopeFromJson(metalScopeToJson(m)), m);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/metal_scope_test.dart`
Expected: FAIL — compile errors (`eaveLF` not defined, `metalScopeFromJson` not defined).

- [ ] **Step 3: Implement**

In `section_models.dart`, above `class MetalScope`:

```dart
/// Roof-edge types that carry edge metal (and perimeter nailers).
const List<String> kEdgeMetalEdgeTypes = ['Eave', 'Rake Edge', 'Flat Drip Edge'];
const List<String> kNailerWidths = ['2x6', '2x8', '2x10'];
```

Replace the `MetalScope` class body fields/ctor/copyWith/==/hashCode so it has:

```dart
class MetalScope {
  final String copingWidth;
  final double copingLF;
  final double wallFlashingLF;   // Headwall + Clerestory edges
  final double eaveLF;
  final double rakeLF;
  final double flatDripLF;
  final String eaveMetalType;
  final String rakeMetalType;
  final String flatDripMetalType;
  final double otherEdgeMetalLF;
  final String gutterSize;
  final double gutterLF;
  final int downspoutCount;
  final bool hasNailers;
  final String nailerWidth;      // from kNailerWidths

  /// Roof-edge metal LF (all three buckets).
  double get dripEdgeLF => eaveLF + rakeLF + flatDripLF;
  /// Primary edge metal type (eave) — kept for older readers.
  String get edgeMetalType => eaveMetalType;
  /// Perimeter nailers run along every roof edge that carries edge metal.
  double get nailerLF => dripEdgeLF;
  double get edgeMetalLF => wallFlashingLF + dripEdgeLF + otherEdgeMetalLF;

  const MetalScope({
    this.copingWidth = '12"',
    this.copingLF = 0.0,
    this.wallFlashingLF = 0.0,
    this.eaveLF = 0.0,
    this.rakeLF = 0.0,
    this.flatDripLF = 0.0,
    this.eaveMetalType = 'TPO-Coated Drip Edge',
    this.rakeMetalType = 'TPO-Coated Drip Edge',
    this.flatDripMetalType = 'TPO-Coated Drip Edge',
    this.otherEdgeMetalLF = 0.0,
    this.gutterSize = '6"',
    this.gutterLF = 0.0,
    this.downspoutCount = 0,
    this.hasNailers = false,
    this.nailerWidth = '2x6',
  });

  factory MetalScope.initial() => const MetalScope();

  MetalScope copyWith({
    String? copingWidth, double? copingLF, double? wallFlashingLF,
    double? eaveLF, double? rakeLF, double? flatDripLF,
    String? eaveMetalType, String? rakeMetalType, String? flatDripMetalType,
    double? otherEdgeMetalLF, String? gutterSize, double? gutterLF,
    int? downspoutCount, bool? hasNailers, String? nailerWidth,
  }) => MetalScope(
        copingWidth: copingWidth ?? this.copingWidth,
        copingLF: copingLF ?? this.copingLF,
        wallFlashingLF: wallFlashingLF ?? this.wallFlashingLF,
        eaveLF: eaveLF ?? this.eaveLF,
        rakeLF: rakeLF ?? this.rakeLF,
        flatDripLF: flatDripLF ?? this.flatDripLF,
        eaveMetalType: eaveMetalType ?? this.eaveMetalType,
        rakeMetalType: rakeMetalType ?? this.rakeMetalType,
        flatDripMetalType: flatDripMetalType ?? this.flatDripMetalType,
        otherEdgeMetalLF: otherEdgeMetalLF ?? this.otherEdgeMetalLF,
        gutterSize: gutterSize ?? this.gutterSize,
        gutterLF: gutterLF ?? this.gutterLF,
        downspoutCount: downspoutCount ?? this.downspoutCount,
        hasNailers: hasNailers ?? this.hasNailers,
        nailerWidth: nailerWidth ?? this.nailerWidth,
      );

  /// LF and metal type for one bucket in kEdgeMetalEdgeTypes.
  (double lf, String type) bucket(String edgeType) => switch (edgeType) {
        'Rake Edge' => (rakeLF, rakeMetalType),
        'Flat Drip Edge' => (flatDripLF, flatDripMetalType),
        _ => (eaveLF, eaveMetalType),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetalScope &&
          copingWidth == other.copingWidth && copingLF == other.copingLF &&
          wallFlashingLF == other.wallFlashingLF &&
          eaveLF == other.eaveLF && rakeLF == other.rakeLF && flatDripLF == other.flatDripLF &&
          eaveMetalType == other.eaveMetalType && rakeMetalType == other.rakeMetalType &&
          flatDripMetalType == other.flatDripMetalType &&
          otherEdgeMetalLF == other.otherEdgeMetalLF && gutterSize == other.gutterSize &&
          gutterLF == other.gutterLF && downspoutCount == other.downspoutCount &&
          hasNailers == other.hasNailers && nailerWidth == other.nailerWidth;

  @override
  int get hashCode => Object.hash(copingWidth, copingLF, wallFlashingLF, eaveLF, rakeLF,
      flatDripLF, eaveMetalType, rakeMetalType, flatDripMetalType, otherEdgeMetalLF,
      gutterSize, gutterLF, downspoutCount, hasNailers, nailerWidth);
}
```

In `serialization.dart` add public aliases next to the others and replace the metal functions:

```dart
Map<String, dynamic> metalScopeToJson(MetalScope m) => _metalScopeToJson(m);
MetalScope metalScopeFromJson(Map j) => _metalScopeFromJson(j);
```

```dart
Map<String, dynamic> _metalScopeToJson(MetalScope m) => {
  'copingWidth': m.copingWidth, 'copingLF': m.copingLF,
  'wallFlashingLF': m.wallFlashingLF,
  'eaveLF': m.eaveLF, 'rakeLF': m.rakeLF, 'flatDripLF': m.flatDripLF,
  'eaveMetalType': m.eaveMetalType, 'rakeMetalType': m.rakeMetalType,
  'flatDripMetalType': m.flatDripMetalType,
  'otherEdgeMetalLF': m.otherEdgeMetalLF,
  'gutterSize': m.gutterSize, 'gutterLF': m.gutterLF, 'downspoutCount': m.downspoutCount,
  'hasNailers': m.hasNailers, 'nailerWidth': m.nailerWidth,
};

MetalScope _metalScopeFromJson(Map j) {
  // Legacy: single dripEdgeLF (or older edgeMetalLF) + one edgeMetalType.
  final legacyType = _s(j['edgeMetalType'], 'TPO-Coated Drip Edge');
  return MetalScope(
    copingWidth: _s(j['copingWidth'], '12"'),
    copingLF: _d(j['copingLF'], 0.0),
    wallFlashingLF: _d(j['wallFlashingLF'], 0.0),
    eaveLF: _d(j['eaveLF'] ?? j['dripEdgeLF'] ?? j['edgeMetalLF'], 0.0),
    rakeLF: _d(j['rakeLF'], 0.0),
    flatDripLF: _d(j['flatDripLF'], 0.0),
    eaveMetalType: _s(j['eaveMetalType'], legacyType),
    rakeMetalType: _s(j['rakeMetalType'], legacyType),
    flatDripMetalType: _s(j['flatDripMetalType'], legacyType),
    otherEdgeMetalLF: _d(j['otherEdgeMetalLF'], 0.0),
    gutterSize: _s(j['gutterSize'], '6"'),
    gutterLF: _d(j['gutterLF'], 0.0),
    downspoutCount: _i(j['downspoutCount'], 0),
    hasNailers: j['hasNailers'] as bool? ?? false,
    nailerWidth: _s(j['nailerWidth'], '2x6'),
  );
}
```

In `estimator_providers.dart` replace `updateEdgeMetalType`, `updateDripEdgeLF`, `updateEdgeMetalLF` with:

```dart
  void updateEdgeMetalType(String edgeType, String type) => _updateActive((b) =>
      b.copyWith(metalScope: switch (edgeType) {
        'Rake Edge' => b.metalScope.copyWith(rakeMetalType: type),
        'Flat Drip Edge' => b.metalScope.copyWith(flatDripMetalType: type),
        _ => b.metalScope.copyWith(eaveMetalType: type),
      }));

  void updateEdgeMetalLF(String edgeType, double lf) => _updateActive((b) =>
      b.copyWith(metalScope: switch (edgeType) {
        'Rake Edge' => b.metalScope.copyWith(rakeLF: lf),
        'Flat Drip Edge' => b.metalScope.copyWith(flatDripLF: lf),
        _ => b.metalScope.copyWith(eaveLF: lf),
      }));

  void setNailersEnabled(bool enabled) => _updateActive(
      (b) => b.copyWith(metalScope: b.metalScope.copyWith(hasNailers: enabled)));

  void updateNailerWidth(String width) => _updateActive(
      (b) => b.copyWith(metalScope: b.metalScope.copyWith(nailerWidth: width)));
```

Fix remaining compile errors from removed `copyWith(dripEdgeLF:)` / `copyWith(edgeMetalType:)` callers (left_panel lines ~569, ~1953, ~1969 — temporary: `n.updateEdgeMetalLF('Eave', …)`, `n.updateEdgeMetalType('Eave', v!)`; Task 9 replaces the UI). Run `flutter analyze lib` until clean of errors.

- [ ] **Step 4: Run tests**

Run: `flutter test test/models/metal_scope_test.dart test/services/serialization_test.dart`
Expected: PASS

- [ ] **Step 5: Commit (only on user approval)**

```bash
git add lib/models/section_models.dart lib/services/serialization.dart lib/providers/estimator_providers.dart lib/widgets/left_panel.dart test/models/metal_scope_test.dart
git commit -m "feat(metal): edge metal per edge type and nailer fields on MetalScope"
```

---

### Task 2: ParapetWalls headwall fields

**Files:**
- Modify: `lib/models/section_models.dart` (ParapetWalls, ~153–252)
- Modify: `lib/services/serialization.dart` (`_parapetWallsToJson` / `_parapetWallsFromJson`)
- Modify: `lib/providers/estimator_providers.dart` (parapet section ~657–705)
- Test: `test/models/parapet_walls_test.dart` (create)

**Interfaces:**
- Produces: `ParapetWalls.headwallHeight`, `ParapetWalls.headwallLF`, getter `hasHeadwall` (height > 0 && LF > 0), getter `wallTermBarLF` (parapet term bar when enabled + headwall LF when `hasHeadwall`); public `parapetWallsToJson` / `parapetWallsFromJson`; notifier `updateHeadwallHeight(double)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/models/parapet_walls_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/services/serialization.dart';

void main() {
  test('hasHeadwall needs height and LF', () {
    expect(const ParapetWalls(headwallHeight: 24).hasHeadwall, false);
    expect(const ParapetWalls(headwallLF: 50).hasHeadwall, false);
    expect(const ParapetWalls(headwallHeight: 24, headwallLF: 50).hasHeadwall, true);
  });

  test('wallTermBarLF adds headwall to parapet term bar', () {
    const p = ParapetWalls(hasParapetWalls: true, parapetHeight: 30, parapetTotalLF: 100,
        headwallHeight: 24, headwallLF: 50);
    expect(p.wallTermBarLF, 150);
    expect(const ParapetWalls(headwallHeight: 24, headwallLF: 50).wallTermBarLF, 50);
  });

  test('copyWith keeps headwall fields', () {
    const p = ParapetWalls(headwallHeight: 24, headwallLF: 50);
    final q = p.copyWith(parapetHeight: 10);
    expect(q.headwallHeight, 24);
    expect(q.headwallLF, 50);
    expect(p.clearTerminationBarOverride().headwallLF, 50);
  });

  test('round trip and legacy default', () {
    const p = ParapetWalls(headwallHeight: 24, headwallLF: 50);
    expect(parapetWallsFromJson(parapetWallsToJson(p)), p);
    expect(parapetWallsFromJson({}).headwallLF, 0);
  });
}
```

- [ ] **Step 2: Run to verify fail**

Run: `flutter test test/models/parapet_walls_test.dart`
Expected: FAIL — `headwallHeight` not defined.

- [ ] **Step 3: Implement**

In `ParapetWalls` add fields `final double headwallHeight; // inches` and `final double headwallLF;`, ctor defaults `0.0`, include them in `copyWith` (params `double? headwallHeight, double? headwallLF`), in `clearTerminationBarOverride()` (pass through), `==`, and `hashCode`. Add getters:

```dart
  /// Headwall flashing is in scope only with both a height and LF.
  bool get hasHeadwall => headwallHeight > 0 && headwallLF > 0;

  /// Termination bar LF across parapet and headwall.
  double get wallTermBarLF =>
      (hasParapetWalls ? terminationBarLF : 0.0) + (hasHeadwall ? headwallLF : 0.0);
```

Serialization: add `'headwallHeight': p.headwallHeight, 'headwallLF': p.headwallLF` to JSON, and
`headwallHeight: _d(j['headwallHeight'], 0.0), headwallLF: _d(j['headwallLF'], 0.0),` to the reader; add public aliases
`parapetWallsToJson` / `parapetWallsFromJson` next to the other aliases.

Notifier:

```dart
  void updateHeadwallHeight(double inches) => _updateActive((b) =>
      b.copyWith(parapetWalls: b.parapetWalls.copyWith(headwallHeight: inches)));
```

- [ ] **Step 4: Run tests** — `flutter test test/models/parapet_walls_test.dart` → PASS

- [ ] **Step 5: Commit (on approval)** — `git commit -m "feat(walls): headwall height and LF on ParapetWalls"`

---

### Task 3: Geometry is the source of truth for wall and edge LF

**Files:**
- Create: `lib/services/edge_totals.dart`
- Modify: `lib/providers/estimator_providers.dart` (add `applyEdgeTotals`)
- Test: `test/services/edge_totals_test.dart` (create)

**Interfaces:**
- Consumes: `MetalScope.copyWith(eaveLF, rakeLF, flatDripLF, wallFlashingLF)` (Task 1), `ParapetWalls.copyWith(headwallLF)` (Task 2).
- Produces: `class EdgeTotals { eaveLF, rakeLF, flatDripLF, parapetLF, headwallLF, clerestoryLF, corners; bool get hasEdges; double get wallFlashingLF }`, `EdgeTotals computeEdgeTotals(List<RoofShape> shapes)`, notifier `void applyEdgeTotals(EdgeTotals t)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/services/edge_totals_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/services/edge_totals.dart';

RoofShape _shape(List<String> types) => RoofShape(
    shapeIndex: 1, edgeLengths: const [100, 50, 100, 50], edgeTypes: types);

void main() {
  test('buckets by edge type; hip/valley/ridge excluded', () {
    final t = computeEdgeTotals([
      _shape(['Eave', 'Rake Edge', 'Flat Drip Edge', 'Hip']),
    ]);
    expect(t.eaveLF, 100);
    expect(t.rakeLF, 50);
    expect(t.flatDripLF, 100);
    expect(t.parapetLF, 0);
    expect(t.corners, 4);
    expect(t.hasEdges, true);
  });

  test('walls', () {
    final t = computeEdgeTotals([_shape(['Parapet', 'Headwall', 'Clerestory', 'Eave'])]);
    expect(t.parapetLF, 100);
    expect(t.headwallLF, 50);
    expect(t.wallFlashingLF, 150); // headwall + clerestory
  });

  test('no edges', () {
    expect(computeEdgeTotals(const []).hasEdges, false);
  });

  group('applyEdgeTotals', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('Parapet edge switched back to Eave clears parapet scope', () {
      final n = c.read(estimatorProvider.notifier);
      n.updateParapetHeight(30);
      n.applyEdgeTotals(computeEdgeTotals([_shape(['Parapet', 'Eave', 'Eave', 'Eave'])]));
      var p = c.read(estimatorProvider).activeBuilding.parapetWalls;
      expect(p.parapetTotalLF, 100);
      expect(p.hasParapetWalls, true);

      n.applyEdgeTotals(computeEdgeTotals([_shape(['Eave', 'Eave', 'Eave', 'Eave'])]));
      p = c.read(estimatorProvider).activeBuilding.parapetWalls;
      expect(p.parapetTotalLF, 0);
      expect(p.hasParapetWalls, false);
      final m = c.read(estimatorProvider).activeBuilding.metalScope;
      expect(m.eaveLF, 300);
      expect(m.wallFlashingLF, 0);
    });

    test('headwall LF follows geometry, including back to 0', () {
      final n = c.read(estimatorProvider.notifier);
      n.applyEdgeTotals(computeEdgeTotals([_shape(['Eave', 'Rake Edge', 'Headwall', 'Rake Edge'])]));
      expect(c.read(estimatorProvider).activeBuilding.parapetWalls.headwallLF, 100);
      n.applyEdgeTotals(computeEdgeTotals([_shape(['Eave', 'Rake Edge', 'Eave', 'Rake Edge'])]));
      expect(c.read(estimatorProvider).activeBuilding.parapetWalls.headwallLF, 0);
    });

    test('no edges leaves manual values', () {
      final n = c.read(estimatorProvider.notifier);
      n.updateParapetHeight(30);
      n.updateParapetTotalLF(80);
      n.setParapetEnabled(true);
      n.applyEdgeTotals(computeEdgeTotals(const []));
      final p = c.read(estimatorProvider).activeBuilding.parapetWalls;
      expect(p.parapetTotalLF, 80);
      expect(p.hasParapetWalls, true);
    });

    test('only the active building changes', () {
      final n = c.read(estimatorProvider.notifier);
      n.addBuilding();
      final idx = c.read(estimatorProvider).activeBuildingIndex;
      n.applyEdgeTotals(computeEdgeTotals([_shape(['Eave', 'Eave', 'Eave', 'Eave'])]));
      final s = c.read(estimatorProvider);
      for (var i = 0; i < s.buildings.length; i++) {
        expect(s.buildings[i].metalScope.eaveLF, i == idx ? 300 : 0);
      }
    });
  });
}
```

Before Step 2, confirm the notifier's add-building method name: `grep -n "void addBuilding\|void add.*Building" lib/providers/estimator_providers.dart` and use that exact name in the last test.

- [ ] **Step 2: Run to verify fail**

Run: `flutter test test/services/edge_totals_test.dart`
Expected: FAIL — `edge_totals.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/services/edge_totals.dart
import '../models/roof_geometry.dart';

/// LF per edge bucket, summed from the edge types drawn in Project Geometry.
/// Project Geometry is the source of truth: these values overwrite the
/// parapet, headwall, wall flashing and edge-metal LF on every sync.
class EdgeTotals {
  final double eaveLF, rakeLF, flatDripLF;
  final double parapetLF, headwallLF, clerestoryLF;
  final int corners;

  const EdgeTotals({
    this.eaveLF = 0, this.rakeLF = 0, this.flatDripLF = 0,
    this.parapetLF = 0, this.headwallLF = 0, this.clerestoryLF = 0,
    this.corners = 0,
  });

  /// False when no shape has edges — manual LF entry stays authoritative.
  bool get hasEdges => corners > 0;

  /// Wall flashing metal: headwall and clerestory edges (parapets get coping).
  double get wallFlashingLF => headwallLF + clerestoryLF;
}

EdgeTotals computeEdgeTotals(List<RoofShape> shapes) {
  double eave = 0, rake = 0, flat = 0, parapet = 0, headwall = 0, clerestory = 0;
  int corners = 0;
  for (final s in shapes) {
    corners += s.edgeLengths.length;
    for (var i = 0; i < s.edgeLengths.length; i++) {
      final len = s.edgeLengths[i].abs();
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
      corners: corners);
}
```

Notifier (import `../services/edge_totals.dart`):

```dart
  /// Writes geometry-derived LF into the active building. No-op when no
  /// edges are drawn, so manually entered LF is kept.
  void applyEdgeTotals(EdgeTotals t) {
    if (!t.hasEdges) return;
    _updateActive((b) {
      var parapet = b.parapetWalls.copyWith(
          headwallLF: t.headwallLF, hasParapetWalls: t.parapetLF > 0);
      if (parapet.parapetTotalLF != t.parapetLF) {
        parapet = parapet.copyWith(parapetTotalLF: t.parapetLF).clearTerminationBarOverride();
      }
      return b.copyWith(
        roofGeometry: b.roofGeometry.copyWith(outsideCorners: t.corners),
        parapetWalls: parapet,
        metalScope: b.metalScope.copyWith(
          eaveLF: t.eaveLF, rakeLF: t.rakeLF, flatDripLF: t.flatDripLF,
          wallFlashingLF: t.wallFlashingLF),
      );
    });
  }
```

- [ ] **Step 4: Run tests** — `flutter test test/services/edge_totals_test.dart` → PASS

- [ ] **Step 5: Commit (on approval)** — `git commit -m "fix(geometry): edge types overwrite parapet, headwall and edge LF"`

---

### Task 4: Adhesive options — VersiWeld pails default, CAV-GRIP option

**Files:**
- Modify: `lib/models/section_models.dart` (`kAdhesiveTypes` ~30–38, MembraneSystem default ~74, ParapetWalls default ~178)
- Modify: `lib/services/serialization.dart` (membrane `adhesiveType`, parapet `parapetAdhesiveType` readers)
- Modify: `lib/services/bom_calculator.dart` (field VersiWeld branch ~1158–1225)
- Modify: `lib/widgets/left_panel.dart` (`_adhesiveType` ~200, `_parapetAdhesiveType` ~224 initial values)
- Create: `test/services/bom_test_helpers.dart` (shared `calc`, `geo100`, `adhesives`)
- Test: `test/services/adhesive_test.dart` (create)

**Interfaces:**
- Produces: `const String kAdhesiveCavGrip = 'CAV-GRIP 3V Spray'`, `String normalizeAdhesiveType(Object? v)`, `kAdhesiveTypes == [kAdhesiveVersiWeldPails, kAdhesiveCavGrip]`.

- [ ] **Step 1: Write the failing test**

```dart
// test/services/bom_test_helpers.dart  (shared by Tasks 4–8; not a test file)
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/project_info.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/services/bom_calculator.dart';

RoofGeometry geo100() {
  final g = RoofGeometry(shapes: [
    RoofShape(shapeIndex: 1, edgeLengths: const [100, 100, 100, 100],
        edgeTypes: const ['Eave', 'Flat Drip Edge', 'Eave', 'Flat Drip Edge'])
  ], outsideCorners: 4);
  return g.copyWith(windZones: WindZones.fromDimensions(totalArea: g.totalArea,
      totalPerimeter: g.totalPerimeter, outsideCorners: 4, zoneWidth: 5));
}

BomResult calc({MembraneSystem membrane = const MembraneSystem(),
    ParapetWalls parapet = const ParapetWalls(),
    InsulationSystem insulation = const InsulationSystem(),
    MetalScope metal = const MetalScope(),
    String deck = 'Metal'}) =>
    BomCalculator.calculate(
      projectInfo: ProjectInfo.initial().copyWith(warrantyYears: 20, designWindSpeed: '115 mph'),
      geometry: geo100(), systemSpecs: SystemSpecs(deckType: deck),
      insulation: insulation, membrane: membrane, parapet: parapet,
      penetrations: const Penetrations(), metalScope: metal);

Iterable<BomLineItem> adhesives(BomResult r) =>
    r.items.where((i) => (i.skuKey ?? '').startsWith('adhesive_') && i.hasQuantity);
```

```dart
// test/services/adhesive_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'bom_test_helpers.dart';

void main() {
  test('options are VersiWeld pails (default) and CAV-GRIP', () {
    expect(kAdhesiveTypes, [kAdhesiveVersiWeldPails, kAdhesiveCavGrip]);
    expect(const MembraneSystem().adhesiveType, kAdhesiveVersiWeldPails);
    expect(const ParapetWalls().parapetAdhesiveType, kAdhesiveVersiWeldPails);
  });

  test('legacy and unknown values normalize to pails', () {
    expect(normalizeAdhesiveType('VersiWeld TPO Bonding Adhesive'), kAdhesiveVersiWeldPails);
    expect(normalizeAdhesiveType(null), kAdhesiveVersiWeldPails);
    expect(normalizeAdhesiveType('CAV-GRIP 3V Spray'), kAdhesiveCavGrip);
  });

  test('REGRESSION: MA, metal deck, eave/drip edges only, no cover board → no adhesive', () {
    expect(adhesives(calc()), isEmpty);
  });

  test('FA 10,000 sf orders VersiWeld 5-gal pails', () {
    final r = calc(membrane: const MembraneSystem(fieldAttachment: 'Fully Adhered'));
    final a = adhesives(r).single;
    expect(a.skuKey, 'adhesive_versiweld_bonding');
    expect(a.unit, 'pails');
    expect(a.trace.packageSize, 5);
    // 10,000 / 60 = 166.7 gal × 1.05 = 175 gal → 35 pails (same float path as BOM)
    expect(a.orderQty, ((10000 / 60) * 1.05 / 5).ceil());
    expect(a.orderQty, inInclusiveRange(35, 36));
  });

  test('FA with CAV-GRIP orders cylinders + UN-TACK', () {
    final r = calc(membrane: const MembraneSystem(
        fieldAttachment: 'Fully Adhered', adhesiveType: kAdhesiveCavGrip));
    expect(adhesives(r).single.skuKey, 'adhesive_cavgrip_3v_40lb');
    expect(r.items.any((i) => i.skuKey == 'cleaner_untack_8oz_aerosol'), true);
  });
}
```

- [ ] **Step 2: Run to verify fail** — `flutter test test/services/adhesive_test.dart` → FAIL (`kAdhesiveCavGrip` undefined).

- [ ] **Step 3: Implement**

`section_models.dart`:

```dart
/// VersiWeld bonding adhesive, ordered in 5-gal pails (brush/roller).
const String kAdhesiveVersiWeldPails = 'VersiWeld TPO Bonding Adhesive — 5 Gal Pails';
const String kAdhesiveCavGrip = 'CAV-GRIP 3V Spray';

/// Adhesive choices wherever adhesive is called for (field FA, parapet, headwall).
const List<String> kAdhesiveTypes = [kAdhesiveVersiWeldPails, kAdhesiveCavGrip];

/// Maps stored values (including the retired auto-package VersiWeld option)
/// onto [kAdhesiveTypes].
String normalizeAdhesiveType(Object? v) =>
    v == kAdhesiveCavGrip ? kAdhesiveCavGrip : kAdhesiveVersiWeldPails;
```

Change `MembraneSystem` default `this.adhesiveType = kAdhesiveVersiWeldPails` and `ParapetWalls` default `this.parapetAdhesiveType = kAdhesiveVersiWeldPails`.

Serialization readers: `adhesiveType: normalizeAdhesiveType(j['adhesiveType']),` and `parapetAdhesiveType: normalizeAdhesiveType(j['parapetAdhesiveType']),`.

BOM field VersiWeld branch: replace the whole `final String productName; … else { … 15 Gal … }` package-selection block with fixed pails:

```dart
        // VersiWeld bonding adhesive: 60 sf/gal, ordered in 5-gal pails.
        const coveragePerGal = 60.0;
        const packageGal = 5.0;
        final base  = adheredMembraneArea / coveragePerGal;
        final withW = base * (1 + wAcc);
        final orderQty = (withW / packageGal).ceil().toDouble();
        items.add(BomLineItem(
          category: 'Adhesives & Sealants',
          name: 'VersiWeld TPO Bonding Adhesive$vocSuffix — 5 Gal Pail',
          skuKey: 'adhesive_versiweld_bonding',
          attributes: {'voc': projectInfo.vocRegion, 'packageGal': 5, 'application': 'field'},
          orderQty: orderQty,
          unit: 'pails',
          notes: '5-gal pail, ~60 sf/gal — field membrane only',
          trace: BomTrace(
            baseDescription: '${_sf(adheredMembraneArea)} ÷ 60 sf/gal',
            baseQty: base, wastePercent: wAcc, withWaste: withW,
            packageSize: packageGal, orderQty: orderQty,
            breakdown: [
              'FA membrane area: ${_sf(adheredMembraneArea)}',
              'Coverage rate: 60 sf/gal',
              'Base gallons:  ${base.toStringAsFixed(1)}',
              'Waste:         ${_pct(wAcc)}%',
              'With waste:    ${withW.toStringAsFixed(1)} gal',
              'ORDER QTY:     ${orderQty.toInt()} pails (5-gal each)',
            ],
          ),
        ));
```

Replace `membrane.adhesiveType == 'CAV-GRIP 3V Spray'` and `parapet.parapetAdhesiveType == 'CAV-GRIP 3V Spray'` comparisons across `lib/` with `kAdhesiveCavGrip` (grep `'CAV-GRIP 3V Spray'`). Left panel initial values: `_adhesiveType = kAdhesiveVersiWeldPails`, `_parapetAdhesiveType = kAdhesiveVersiWeldPails`.

- [ ] **Step 4: Run tests** — `flutter test test/services/adhesive_test.dart test/services/` → PASS (update any existing assertion that expected `15 Gal`/`1 Gal` names; note each changed assertion in the task report).

- [ ] **Step 5: Commit (on approval)** — `git commit -m "feat(adhesive): VersiWeld pails default with CAV-GRIP option"`

---

### Task 5: Shared wall flashing — parapet and headwall

**Files:**
- Modify: `lib/services/bom_calculator.dart` (wall area ~180–186, membrane/flashing area ~251–305, parapet adhesive ~1258–1370, section 5 gate ~1546, primer ~2171, RUSS ~2328–2395)
- Test: `test/services/wall_flashing_test.dart` (create)

**Interfaces:**
- Consumes: `ParapetWalls.hasHeadwall`, `headwallHeight`, `headwallLF`, `wallTermBarLF` (Task 2); `kAdhesiveCavGrip` (Task 4).
- Produces: `static List<BomLineItem> _wallAdhesiveItems({required String wall, required double heightIn, required double lf, required String terminationType, required String adhesiveType, required String vocSuffix, required String voc, required double wAcc, required List<String> warnings})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/services/wall_flashing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'bom_test_helpers.dart';

void main() {
  test('headwall 24" × 50 LF: flashing, adhesive (Headwall), term bar, RUSS', () {
    final r = calc(parapet: const ParapetWalls(headwallHeight: 24, headwallLF: 50,
        terminationType: 'Termination Bar'));
    final adh = r.items.singleWhere((i) => i.name.contains('(Headwall)'));
    // (24/12 + 0.33) × 50 = 116.5 sf ÷ 60 × 1.05 = 2.04 gal → 1 pail
    expect(adh.orderQty, 1);
    expect(adh.trace.baseQty, closeTo(116.5 / 60, 0.01));
    final tb = r.items.firstWhere((i) => i.name.toLowerCase().contains('termination bar'));
    expect(tb.trace.baseQty, closeTo(5, 0.001)); // 50 LF ÷ 10'
    expect(r.items.any((i) => i.name.contains('RUSS')), true); // MA default
  });

  test('headwall 12" → adhesive omitted with warning', () {
    final r = calc(parapet: const ParapetWalls(headwallHeight: 12, headwallLF: 50));
    expect(r.items.where((i) => i.name.contains('(Headwall)') && i.category == 'Adhesives & Sealants'), isEmpty);
    expect(r.warnings.any((w) => w.contains('Headwall adhesive omitted')), true);
  });

  test('parapet with LF and 0 height: no adhesive, no crash', () {
    final r = calc(parapet: const ParapetWalls(hasParapetWalls: true, parapetTotalLF: 100));
    expect(r.items.where((i) => (i.skuKey ?? '').startsWith('adhesive_')), isEmpty);
  });

  test('parapet 30" keeps its own (Parapet) line', () {
    final r = calc(parapet: const ParapetWalls(hasParapetWalls: true, parapetHeight: 30,
        parapetTotalLF: 100));
    expect(r.items.where((i) => i.name.endsWith('(Parapet)')).length, 1);
  });

  test('no walls → no RUSS, no term bar', () {
    final r = calc();
    expect(r.items.any((i) => i.name.contains('RUSS')), false);
    expect(r.items.any((i) => i.name.toLowerCase().contains('termination bar')), false);
  });
}
```

Note: if the RUSS line name differs, grep `name:` in the RUSS block (~2337) and use its text.

- [ ] **Step 2: Run to verify fail** — `flutter test test/services/wall_flashing_test.dart` → FAIL (no `(Headwall)` line).

- [ ] **Step 3: Implement**

a) Wall areas (~180):

```dart
    final parapetHeightFt = parapet.hasParapetWalls ? parapet.parapetHeight / 12.0 : 0.0;
    final parapetStripWidthFt = parapetHeightFt + 0.33; // wall height + 4" base lap
    final parapetTpoArea = parapet.hasParapetWalls
        ? parapetStripWidthFt * parapet.parapetTotalLF : 0.0;
    final headwallTpoArea = parapet.hasHeadwall
        ? (parapet.headwallHeight / 12.0 + 0.33) * parapet.headwallLF : 0.0;
    final wallTpoArea = parapetTpoArea + headwallTpoArea;
    final termBarLF = parapet.wallTermBarLF;
```

b) Replace `parapetTpoArea` with `wallTpoArea` in the membrane total (~251) and `flashingArea` (~253). In the flashing breakdown (~305) add after the parapet part:
`if (headwallTpoArea > 0) parts.add('headwall ${_sf(headwallTpoArea)} (${(parapet.headwallHeight / 12).toStringAsFixed(1)}\' wall + 4" base lap)');`

c) Replace the whole `if (parapetTpoArea > 0) { … }` parapet adhesive block (~1261–1370) with:

```dart
    if (parapetTpoArea > 0) {
      items.addAll(_wallAdhesiveItems(wall: 'Parapet', heightIn: parapet.parapetHeight,
          lf: parapet.parapetTotalLF, terminationType: parapet.terminationType,
          adhesiveType: parapet.parapetAdhesiveType, vocSuffix: vocSuffix,
          voc: projectInfo.vocRegion, wAcc: wAcc, warnings: warnings));
    }
    if (headwallTpoArea > 0) {
      items.addAll(_wallAdhesiveItems(wall: 'Headwall', heightIn: parapet.headwallHeight,
          lf: parapet.headwallLF, terminationType: parapet.terminationType,
          adhesiveType: parapet.parapetAdhesiveType, vocSuffix: vocSuffix,
          voc: projectInfo.vocRegion, wAcc: wAcc, warnings: warnings));
    }
```

and add the static helper near `_eachItem`:

```dart
  /// Wall flashing adhesive (parapet or headwall). TPO strip runs up the wall
  /// face plus a 4" base lap. Versico: no adhesive on walls ≤ 12", or ≤ 18"
  /// with a termination bar.
  static List<BomLineItem> _wallAdhesiveItems({
    required String wall, required double heightIn, required double lf,
    required String terminationType, required String adhesiveType,
    required String vocSuffix, required String voc, required double wAcc,
    required List<String> warnings,
  }) {
    final stripFt = heightIn / 12.0 + 0.33;
    final area = stripFt * lf;
    if (area <= 0) return const [];
    final skip = heightIn <= 12 || (heightIn <= 18 && terminationType == 'Termination Bar');
    if (skip) {
      warnings.add('$wall adhesive omitted — wall height ${heightIn.toInt()}" per Versico spec '
          '(no adhesive required for short walls with ${terminationType.toLowerCase()}).');
      return const [];
    }
    final areaLines = [
      '$wall TPO area: ${_sf(area)}',
      '  Wall: ${(heightIn / 12).toStringAsFixed(1)}\' + 4" base lap = ${stripFt.toStringAsFixed(2)}\' x ${_lf(lf)}',
    ];
    final appl = wall.toLowerCase();
    if (adhesiveType == kAdhesiveCavGrip) {
      const cov = 2000.0; // [Unverified] ~2,000 sf per #40 cylinder
      final base = area / cov;
      final withW = base * (1 + wAcc);
      final order = withW.ceil().toDouble();
      final trace = BomTrace(
        baseDescription: '${_sf(area)} ÷ ${cov.toInt()} sf/cylinder',
        baseQty: base, wastePercent: wAcc, withWaste: withW, packageSize: 1, orderQty: order,
        breakdown: [...areaLines, 'Coverage rate: ${cov.toInt()} sf per #40 cylinder',
          'Base: ${base.toStringAsFixed(2)} cylinders', 'Waste: ${_pct(wAcc)}%',
          'ORDER QTY: ${order.toInt()} cylinders'],
      );
      return [
        BomLineItem(category: 'Adhesives & Sealants',
          name: 'Versico CAV-GRIP 3V Low-VOC Adhesive/Primer$vocSuffix — #40 Cylinder ($wall)',
          skuKey: 'adhesive_cavgrip_3v_40lb', attributes: {'voc': voc, 'application': appl},
          orderQty: order, unit: 'cylinders',
          notes: '#40 cylinder, ~${cov.toInt()} sf/cyl — $appl flashing', trace: trace),
        BomLineItem(category: 'Adhesives & Sealants',
          name: 'Versico UN-TACK Adhesive Remover & Cleaner — #8 Aerosol ($wall)',
          skuKey: 'cleaner_untack_8oz_aerosol', attributes: {'application': appl},
          orderQty: order, unit: 'aerosols', notes: '#8 aerosol — one per CAV-GRIP 3V cylinder',
          trace: trace),
      ];
    }
    const cov = 60.0, pail = 5.0;
    final base = area / cov;
    final withW = base * (1 + wAcc);
    final pails = (withW / pail).ceil().toDouble();
    return [
      BomLineItem(category: 'Adhesives & Sealants',
        name: 'VersiWeld TPO Bonding Adhesive$vocSuffix — 5 Gal Pail ($wall)',
        skuKey: 'adhesive_versiweld_bonding',
        attributes: {'voc': voc, 'packageGal': 5, 'application': appl},
        orderQty: pails, unit: 'pails', notes: '5-gal pail, ~60 sf/gal — $appl flashing',
        trace: BomTrace(
          baseDescription: '${_sf(area)} ÷ 60 sf/gal',
          baseQty: base, wastePercent: wAcc, withWaste: withW, packageSize: pail, orderQty: pails,
          breakdown: [...areaLines, 'Coverage rate: 60 sf/gal',
            'Base gallons:  ${base.toStringAsFixed(1)}', 'Waste:         ${_pct(wAcc)}%',
            'With waste:    ${withW.toStringAsFixed(1)} gal',
            'ORDER QTY:     ${pails.toInt()} pails (5-gal each)'],
        )),
    ];
  }
```

d) Section 5 gate (~1546): `if (parapet.hasParapetWalls || parapet.hasHeadwall) {` (inner blocks already use `termBarLF`).

e) RUSS + primer: add near the RUSS block `final russLF = (parapet.hasParapetWalls ? parapet.parapetTotalLF : 0.0) + (parapet.hasHeadwall ? parapet.headwallLF : 0.0);` (declare once, before the primer block at ~2160 so both can use it). Primer: replace `(parapet.hasParapetWalls ? parapet.parapetTotalLF * 0.5 : 0.0)` with `russLF * 0.5` and its breakdown label `'  Wall RUSS base (${_lf(russLF)}): …'`. RUSS block: condition `if (isMA && russLF > 0)`; replace every `parapet.parapetTotalLF` inside it with `russLF`, and breakdown labels `'Parapet LF:'` → `'Wall LF (parapet + headwall):'`.

- [ ] **Step 4: Run tests** — `flutter test test/services/wall_flashing_test.dart test/services/` → PASS

- [ ] **Step 5: Commit (on approval)** — `git commit -m "feat(bom): headwall flashing via shared wall-flashing helper"`

---

### Task 6: Edge metal lines per edge type

**Files:**
- Modify: `lib/services/bom_calculator.dart` (edge metal ~1963–1977, edge fastener label ~1723, overlayment breakdown ~2019)
- Modify: `lib/services/validation_engine.dart` (~250–270)
- Modify: `lib/services/sub_instructions_builder.dart` (~230, ~381)
- Modify: `lib/services/export_service.dart` (~1272)
- Modify: `lib/data/sku_registry.dart` (`metal_drip_edge` variantAttributes)
- Test: `test/services/edge_metal_test.dart` (create)

**Interfaces:**
- Consumes: `MetalScope.bucket(edgeType)`, `kEdgeMetalEdgeTypes` (Task 1).

- [ ] **Step 1: Write the failing test**

```dart
// test/services/edge_metal_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'bom_test_helpers.dart';

void main() {
  test('one line per edge bucket with its own type', () {
    final r = calc(metal: const MetalScope(eaveLF: 200, rakeLF: 100,
        rakeMetalType: 'Gravel Stop', flatDripLF: 0));
    final lines = r.items.where((i) => i.skuKey == 'metal_drip_edge').toList();
    expect(lines.map((l) => l.name), [
      'Eave Edge Metal — TPO-Coated Drip Edge',
      'Rake Edge Metal — Gravel Stop',
    ]);
    expect(lines[1].attributes!['edgeType'], 'Rake Edge');
    expect(lines[0].trace.baseQty, closeTo(20, 0.001));
  });
}
```

- [ ] **Step 2: Run to verify fail** — FAIL (old single `Drip Edge — …` line).

- [ ] **Step 3: Implement**

Replace the `if (metalScope.dripEdgeLF > 0) { … }` metal line with:

```dart
    for (final edgeType in kEdgeMetalEdgeTypes) {
      final (lf, type) = metalScope.bucket(edgeType);
      if (lf <= 0) continue;
      final label = edgeType == 'Rake Edge' ? 'Rake' : edgeType;
      items.add(_linearItem('Metal Scope', '$label Edge Metal — $type',
          lf, wMet, "10' sections",
          skuKey: 'metal_drip_edge',
          attributes: {'edgeMetalType': type, 'edgeType': edgeType}));
    }
```

Edge fastener name (~1723): `'$edgeFastName $edgeFastLen — Edge Metal'`. Overlayment breakdown (~2019): `'Roof edges (eave/rake/flat drip): ${_lf(metalScope.dripEdgeLF)}'`.

Validation (~250): replace `isTPOCoated` with
`final nonCoated = kEdgeMetalEdgeTypes.map(metal.bucket).where((b) => b.$1 > 0 && !b.$2.toLowerCase().contains('tpo')).map((b) => b.$2).toSet();`
`final isTPOCoated = nonCoated.isEmpty;` and the second message's trigger `'Edge Metal (${nonCoated.join(', ')})'`.

Sub-instructions ~230 and ~381, export ~1272: list each non-zero bucket, e.g.
`for (final e in kEdgeMetalEdgeTypes) { final (lf, t) = metal.bucket(e); if (lf > 0) widgets.add(_bullet('$e ($t): ${lf.toStringAsFixed(0)} LF')); }`
(same pattern with `metalParts.add('${lf.toStringAsFixed(0)} LF $t at $e')` and a joined string in export).

SKU registry `metal_drip_edge`: `displayName: 'Edge Metal (Eave / Rake / Flat Drip)'`, `variantAttributes: ['edgeMetalType']` (unchanged — `edgeType` does not change the SKU).

- [ ] **Step 4: Run tests** — `flutter test test/services/` → PASS

- [ ] **Step 5: Commit (on approval)** — `git commit -m "feat(bom): edge metal line per edge type"`

---

### Task 7: Cover board defaults, nailbase, adhered-to-steel warning

**Files:**
- Modify: `lib/models/insulation_system.dart` (cover board constants ~27–40, `CoverBoard` default ~103, `withCoverBoardEnabled` ~203)
- Modify: `lib/services/serialization.dart` (`_coverBoardFromJson` ~414)
- Modify: `lib/providers/estimator_providers.dart` (`setCoverBoardEnabled` ~617)
- Modify: `lib/services/r_value_calculator.dart` (~282–295)
- Modify: `lib/services/bom_calculator.dart` (cover board line ~2806 block)
- Modify: `lib/services/validation_engine.dart` (`_validateCompatibility`)
- Modify: `lib/data/sku_registry.dart` (add `insulation_nailbase`)
- Test: `test/services/cover_board_test.dart` (create)

**Interfaces:**
- Produces: `const String kCoverBoardNailbase = 'Nailbase (Polyiso + 7/16" OSB)'`, `const List<double> kNailbaseThicknesses`, `const Map<double, double> kNailbaseRValues`, `List<double> coverBoardThicknessesFor(String type)`, `String coverBoardAttachmentFor(String membraneAttachment, String type)`, `InsulationSystem.withCoverBoardEnabled({String membraneAttachment})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/services/cover_board_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/services/r_value_calculator.dart';
import 'package:protpo_app/services/serialization.dart';
import 'package:protpo_app/services/validation_engine.dart';
import 'bom_test_helpers.dart';

void main() {
  test('cover board attachment follows membrane', () {
    expect(coverBoardAttachmentFor('Mechanically Attached', 'HD Polyiso'), 'Mechanically Attached');
    expect(coverBoardAttachmentFor('Rhinobond (Induction Welded)', 'Gypsum'), 'Mechanically Attached');
    expect(coverBoardAttachmentFor('Fully Adhered', 'HD Polyiso'), 'Adhered');
    expect(coverBoardAttachmentFor('Fully Adhered', kCoverBoardNailbase), 'Mechanically Attached');
  });

  test('enabling cover board on MA job gives MA cover board and no OlyBond', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(estimatorProvider.notifier).setCoverBoardEnabled(true);
    final ins = c.read(estimatorProvider).activeBuilding.insulationSystem;
    expect(ins.coverBoard!.attachmentMethod, 'Mechanically Attached');
    final r = calc(insulation: ins);
    expect(r.items.where((i) => i.skuKey == 'adhesive_olybond_500_set'), isEmpty);
  });

  test('missing stored attachment loads as MA', () {
    final ins = insulationSystemFromJson({'hasCoverBoard': true, 'coverBoard': {'type': 'HD Polyiso'}});
    expect(ins.coverBoard!.attachmentMethod, 'Mechanically Attached');
  });

  test('nailbase thicknesses and R lookup', () {
    expect(coverBoardThicknessesFor(kCoverBoardNailbase), [1.5, 2.0, 2.5, 3.0, 3.5, 4.0]);
    expect(coverBoardThicknessesFor('HD Polyiso'), kCoverBoardThicknesses);
    final r = RValueCalculator.calculate(
      layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.0),
      coverBoard: const CoverBoardInput(materialType: kCoverBoardNailbase, thickness: 2.5),
    );
    expect(r.coverBoard!.rValue, 12.0);
  });

  test('nailbase BOM line', () {
    final r = calc(insulation: const InsulationSystem(hasCoverBoard: true,
        coverBoard: CoverBoard(type: kCoverBoardNailbase, thickness: 2.5,
            attachmentMethod: 'Mechanically Attached')));
    final l = r.items.singleWhere((i) => i.skuKey == 'insulation_nailbase');
    expect(l.name, 'Nailbase (Polyiso + 7/16" OSB) 2.5" — Cover Board');
  });

  test('adhered layer 1 on metal deck warns', () {
    final v = ValidationEngine.validate(
      systemSpecs: const SystemSpecs(deckType: 'Metal'),
      insulation: const InsulationSystem(
          layer1: InsulationLayer(attachmentMethod: 'Adhered')),
    );
    expect(v.issues.any((i) => i.message.contains('steel deck')), true);
  });
}
```

Before Step 2, read the signatures of `RValueCalculator.calculate` and the `ValidationResult` field holding issues (`grep -n "static .* calculate" lib/services/r_value_calculator.dart`) and `ValidationEngine.validate` (line ~73) and fill every required named argument in the two calls above with the defaults used elsewhere in `test/services/` (e.g. `ProjectInfo.initial()`, `const MembraneSystem()`, `const ParapetWalls()`, an empty `RoofGeometry`). Keep the assertions unchanged.

- [ ] **Step 2: Run to verify fail** — FAIL (`coverBoardAttachmentFor` undefined).

- [ ] **Step 3: Implement**

`insulation_system.dart`:

```dart
const String kCoverBoardNailbase = 'Nailbase (Polyiso + 7/16" OSB)';

const List<String> kCoverBoardTypes = [
  'HD Polyiso', 'Gypsum', 'DensDeck', 'DensDeck Prime', kCoverBoardNailbase,
];

/// Nailbase total thickness incl. 7/16" OSB, and LTTR R-value
/// (Hunter H-Shield NB TDS).
const List<double> kNailbaseThicknesses = [1.5, 2.0, 2.5, 3.0, 3.5, 4.0];
const Map<double, double> kNailbaseRValues = {
  1.5: 6.3, 2.0: 9.2, 2.5: 12.0, 3.0: 15.0, 3.5: 18.0, 4.0: 21.1,
};

List<double> coverBoardThicknessesFor(String type) =>
    type == kCoverBoardNailbase ? kNailbaseThicknesses : kCoverBoardThicknesses;

/// Default cover board attachment for the membrane system. Nailbase is
/// always mechanically fastened.
String coverBoardAttachmentFor(String membraneAttachment, String type) =>
    type != kCoverBoardNailbase && membraneAttachment == 'Fully Adhered'
        ? 'Adhered'
        : 'Mechanically Attached';
```

`CoverBoard` default: `this.attachmentMethod = 'Mechanically Attached'`.

```dart
  /// Enables cover board; attachment defaults to match the membrane.
  InsulationSystem withCoverBoardEnabled(
      {String membraneAttachment = 'Mechanically Attached'}) {
    final cb = coverBoard ?? CoverBoard.initial();
    return copyWith(
      hasCoverBoard: true,
      coverBoard: cb.copyWith(
          attachmentMethod: coverBoardAttachmentFor(membraneAttachment, cb.type)),
    );
  }
```

Serialization: `attachmentMethod: _s(j['attachmentMethod'], 'Mechanically Attached'),`.

Notifier:

```dart
  void setCoverBoardEnabled(bool enabled) => _updateActive(
        (b) => b.copyWith(
          insulationSystem: enabled
              ? b.insulationSystem.withCoverBoardEnabled(
                  membraneAttachment: b.membraneSystem.fieldAttachment)
              : b.insulationSystem.withCoverBoardDisabled(),
        ),
      );
```

R-value (~284):

```dart
    if (coverBoard != null) {
      final isNailbase = coverBoard.materialType == kCoverBoardNailbase;
      rCover = isNailbase
          ? (kNailbaseRValues[coverBoard.thickness] ?? 0.0)
          : coverBoard.thickness * rValuePerInch(coverBoard.materialType);
      final rCoverPerInch = coverBoard.thickness > 0 ? rCover / coverBoard.thickness : 0.0;
      coverBoardResult = LayerRValueResult(
        materialType: coverBoard.materialType,
        thickness: coverBoard.thickness,
        rPerInch: rCoverPerInch,
        rValue: rCover,
      );
    }
```

(import `../models/insulation_system.dart` if not already imported.)

BOM cover board line: `skuKey: cb.type == kCoverBoardNailbase ? 'insulation_nailbase' : 'iso_coverboard',`.

Validation in `_validateCompatibility`:

```dart
    // Adhered insulation directly to steel deck — approval varies by assembly
    if (specs.deckType == 'Metal' && insul.numberOfLayers >= 1 &&
        insul.layer1.attachmentMethod == 'Adhered') {
      issues.add(const ValidationIssue(severity: IssueSeverity.warning,
          category: 'Compatibility',
          message: 'Adhered insulation directly to steel deck.',
          fix: 'Verify the adhesive and assembly are approved for steel deck (FM/Versico), or mechanically attach layer 1.'));
    }
```

SKU registry (after `iso_coverboard`):

```dart
  SkuRegistryEntry(
    skuKey: 'insulation_nailbase',
    displayName: 'Nailbase (Polyiso + 7/16" OSB)',
    category: 'Insulation',
    variantAttributes: ['thicknessIn'],
  ),
```

- [ ] **Step 4: Run tests** — `flutter test test/services/` → PASS

- [ ] **Step 5: Commit (on approval)** — `git commit -m "feat(insulation): nailbase cover board; cover board attachment follows membrane"`

---

### Task 8: Perimeter wood nailers in BOM

**Files:**
- Modify: `lib/services/bom_calculator.dart` (new block after edge metal lines, before overlayment strip)
- Modify: `lib/data/sku_registry.dart` (add `lumber_nailer`, `fastener_nailer`)
- Test: `test/services/nailer_test.dart` (create)

**Interfaces:**
- Consumes: `MetalScope.hasNailers`, `nailerWidth`, `nailerLF` (Task 1); `_stackThicknessIn`, `_selectFastener`, `_fastenerName`, `qxoFastenerPack`.

- [ ] **Step 1: Write the failing test**

```dart
// test/services/nailer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/section_models.dart';
import 'bom_test_helpers.dart';

void main() {
  const metal = MetalScope(eaveLF: 400, hasNailers: true);

  test('400 LF, 2.5" stack → 2 plies, 55 boards 2x6 × 16\'', () {
    final r = calc(metal: metal); // default layer 1: 2.5" polyiso
    final lum = r.items.singleWhere((i) => i.skuKey == 'lumber_nailer');
    expect(lum.name, 'Pressure-Treated Lumber 2x6 × 16\' — Perimeter Nailer');
    // ceil(400 × 2 / 16 × 1.10): 55 on paper; float gives 55.000…01 → same path as BOM
    expect(lum.orderQty, (400 * 2 / 16 * (1 + 0.10)).ceil());
    expect(lum.trace.breakdown.any((b) => b.contains('Plies: 2')), true);
  });

  test('fasteners: 2 rows @ 12" o.c. per ply, Needs Validation note', () {
    final r = calc(metal: metal);
    final f = r.items.singleWhere((i) => i.skuKey == 'fastener_nailer');
    expect(f.trace.baseQty, 1600); // 400 × 2 rows × 2 plies
    expect(f.unit, 'cartons');
    expect(f.notes, contains('Needs Validation for nailer fastener spacing'));
  });

  test('taper adds height Needs Validation warning', () {
    final r = calc(metal: metal, insulation: const InsulationSystem().withTaperEnabled());
    expect(r.warnings.any((w) => w.contains('Needs Validation for nailer height at tapered high edges')), true);
  });

  test('off by default', () {
    expect(calc(metal: const MetalScope(eaveLF: 400)).items.any((i) => i.skuKey == 'lumber_nailer'), false);
  });
}
```

- [ ] **Step 2: Run to verify fail** — FAIL (no `lumber_nailer`).

- [ ] **Step 3: Implement**

After the per-edge metal loop:

```dart
    // ── Perimeter wood nailers ──
    // FM DS 1-49: min 2x6 nominal; two staggered rows into steel deck.
    // Versico/Carlisle: nailer top flush with insulation; salt-preservative
    // treated lumber only.
    if (metalScope.hasNailers && metalScope.nailerLF > 0) {
      final lf = metalScope.nailerLF;
      final heightIn = _stackThicknessIn(insulation, 3); // flat stack, no taper
      final plies = heightIn <= 0 ? 1 : (heightIn / 1.5).ceil();
      const boardLF = 16.0;
      final lumBase = lf * plies / boardLF;
      final lumWithW = lumBase * (1 + wMat);
      final lumOrder = lumWithW.ceil().toDouble();
      items.add(BomLineItem(
        category: 'Wood Nailers',
        name: 'Pressure-Treated Lumber ${metalScope.nailerWidth} × 16\' — Perimeter Nailer',
        skuKey: 'lumber_nailer',
        attributes: {'width': metalScope.nailerWidth, 'length': "16'"},
        orderQty: lumOrder,
        unit: 'boards',
        notes: 'Salt-based preservative treatment only; creosote, penta and copper naphthenate damage the membrane (Carlisle)',
        trace: BomTrace(
          baseDescription: '${_lf(lf)} × $plies plies ÷ 16\'',
          baseQty: lumBase, wastePercent: wMat, withWaste: lumWithW,
          packageSize: 1, orderQty: lumOrder,
          breakdown: [
            'Nailer LF (eave + rake + flat drip): ${_lf(lf)}',
            'Insulation stack: ${_fmtIn(heightIn)} → Plies: $plies (1.5" each)',
            'Base: ${lumBase.toStringAsFixed(1)} boards',
            'Waste: ${_pct(wMat)}%',
            'ORDER QTY: ${lumOrder.toInt()} boards',
          ],
        ),
      ));

      const rows = 2, spacingIn = 12.0;
      final fBase = lf * rows * (12 / spacingIn) * plies;
      final fWithW = fBase * (1 + wAcc);
      final fName = _fastenerName(systemSpecs.deckType);
      final sel = _selectFastener(systemSpecs.deckType, plies * 1.5);
      final pack = qxoFastenerPack(fName, sel.lengthIn);
      final fOrder = (fWithW / pack).ceil().toDouble();
      items.add(BomLineItem(
        category: 'Wood Nailers',
        name: '$fName ${sel.label} — Nailer Fasteners',
        skuKey: 'fastener_nailer',
        attributes: {'fastener': fName, 'length': sel.label},
        orderQty: fOrder,
        unit: 'cartons',
        notes: '2 staggered rows @ 12" o.c. per ply — Needs Validation for nailer fastener spacing (FM 1-49 Table 2.2.2.3.4-1 by wind zone)',
        trace: BomTrace(
          baseDescription: '${_lf(lf)} × $rows rows × $plies plies',
          baseQty: fBase, wastePercent: wAcc, withWaste: fWithW,
          packageSize: pack.toDouble(), orderQty: fOrder,
          breakdown: [
            '${_lf(lf)} × $rows rows @ ${spacingIn.toInt()}" o.c. × $plies plies = ${fBase.toStringAsFixed(0)}',
            _fastenerBreakdown(systemSpecs.deckType, plies * 1.5, 'Nailer fastener'),
            'Waste: ${_pct(wAcc)}%',
            'ORDER QTY: ${fOrder.toInt()} cartons ($pack/carton)',
          ],
        ),
      ));

      if (insulation.hasTaper) {
        warnings.add('Needs Validation for nailer height at tapered high edges — nailers sized to the flat stack (${_fmtIn(heightIn)}).');
      }
    }
```

If `systemSpecs` / `qxoFastenerPack` are not in scope at that point, use the parameter names in `calculate(...)` and add `import '../data/qxo_pack_sizes.dart';`.

SKU registry, new section:

```dart
  // ─── WOOD NAILERS ─────────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'lumber_nailer',
    displayName: 'Pressure-Treated Lumber — Perimeter Nailer',
    category: 'Wood Nailers',
    variantAttributes: ['width', 'length'],
  ),
  SkuRegistryEntry(
    skuKey: 'fastener_nailer',
    displayName: 'Nailer Fasteners',
    category: 'Wood Nailers',
    variantAttributes: ['fastener', 'length'],
  ),
```

Add `'Wood Nailers': Icons.carpenter,` to the category icon map in `center_panel.dart` (~681).

- [ ] **Step 4: Run tests** — `flutter test test/services/` → PASS

- [ ] **Step 5: Commit (on approval)** — `git commit -m "feat(bom): perimeter wood nailers"`

---

### Task 9: Left panel UI

**Files:**
- Modify: `lib/widgets/left_panel.dart`

**Interfaces:**
- Consumes: `computeEdgeTotals`, `applyEdgeTotals` (Task 3); `updateEdgeMetalType/LF`, `setNailersEnabled`, `updateNailerWidth` (Task 1); `updateHeadwallHeight` (Task 2); `kAdhesiveTypes` (Task 4); `coverBoardThicknessesFor`, `kCoverBoardNailbase` (Task 7).

- [ ] **Step 1: Geometry sync** — replace `_syncEdgeTypeTotals()` body:

```dart
  void _syncEdgeTypeTotals() {
    final n = ref.read(estimatorProvider.notifier);
    final t = computeEdgeTotals(
        ref.read(estimatorProvider).activeBuilding.roofGeometry.shapes);
    if (!t.hasEdges) return;
    n.applyEdgeTotals(t);
    _set(_cCornerCount, '${t.corners}');
    _set(_cParapetLF, _nz(t.parapetLF));
    if (!_termBarOverride) _set(_cTermBarLF, _nz(t.parapetLF));
    _set(_cHeadwallLF, _nz(t.headwallLF));
    _set(_cWallFlashingLF, _nz(t.wallFlashingLF));
    _set(_cEaveLF, _nz(t.eaveLF));
    _set(_cRakeLF, _nz(t.rakeLF));
    _set(_cFlatDripLF, _nz(t.flatDripLF));
    setState(() => _hasParapet = t.parapetLF > 0);
  }

  bool get _edgesFromGeometry => computeEdgeTotals(
      ref.read(estimatorProvider).activeBuilding.roofGeometry.shapes).hasEdges;
```

Add controllers `_cHeadwallLF`, `_cHeadwallHeight`, `_cEaveLF`, `_cRakeLF`, `_cFlatDripLF` (dispose list ~302), remove `_cWallHeight`, `_cWallLF`, `_cDripEdgeLF`; in `_syncFromState` set them from `par.headwallLF`, `par.headwallHeight`, `met.eaveLF/rakeLF/flatDripLF`; add state `_eaveMetalType`, `_rakeMetalType`, `_flatDripMetalType`, `_hasNailers`, `_nailerWidth` synced from `met`.

- [ ] **Step 2: Walls section** — in `_buildParapet()`: when `_edgesFromGeometry`, render Parapet LF as `_calcBox('Parapet LF (from Project Geometry)', '${_cParapetLF.text} LF', Icons.straighten)` instead of the `Total LF` text field (both the compact and expanded branches). Add, after the parapet block, a headwall block shown when headwall LF > 0:

```dart
      if ((double.tryParse(_cHeadwallLF.text) ?? 0) > 0) ...[
        _sp16,
        _lbl('Headwall'), _sp4,
        _responsiveRow([
          _tf('Headwall Flashing Height', '0', _cHeadwallHeight, suffix: 'in',
              kb: TextInputType.number,
              onChange: (v) => n.updateHeadwallHeight(double.tryParse(v) ?? 0)),
          _calcBox('Headwall LF (from Project Geometry)', '${_cHeadwallLF.text} LF', Icons.straighten),
        ]),
      ],
```

Rename the section title to `Walls: Parapet & Headwall` and the adhesive dropdown label to `Wall Flashing Adhesive` (options `kAdhesiveTypes`). Show the parapet adhesive dropdown when parapet OR headwall is in scope. Remove the `Headwall Flashing Height` / `Total Headwall LF` fields from `_buildPenetrations()`. Fix `_parapetBOM()` "Bonding Adhesive" impact row to show `0` when height ≤ 12 (same rule as BOM).

- [ ] **Step 3: Cover board** — type dropdown onChange:

```dart
            _dd('Type', _cbType, kCoverBoardTypes, (v) {
              setState(() {
                _cbType = v!;
                final allowed = coverBoardThicknessesFor(_cbType);
                if (!allowed.contains(double.tryParse(_cbThickness))) {
                  _cbThickness = allowed.first.toString();
                }
                if (_cbType == kCoverBoardNailbase) _cbAttachment = 'Mechanically Attached';
              });
              pushCB();
            }),
```

Thickness dropdown items: `coverBoardThicknessesFor(_cbType).map((v) => v.toString()).toList()`. Toggle onChange: after `n.setCoverBoardEnabled(v)`, read back `ref.read(insulationSystemProvider).coverBoard` and `setState` `_cbType`, `_cbThickness`, `_cbAttachment` from it. Toggle subtitle: `'HD Polyiso, Gypsum, DensDeck, Nailbase'`. Initial `_cbAttachment = 'Mechanically Attached'` (~191, ~444).

- [ ] **Step 4: Metal scope** — replace the `Edge Metal Type` dropdown, `Drip Edge LF` block with one row per bucket:

```dart
      for (final e in kEdgeMetalEdgeTypes) ...[
        _sp8,
        _responsiveRow([
          _dd('$e Metal', _edgeTypeMetal(e), kEdgeMetalTypes, (v) {
            setState(() => _setEdgeTypeMetal(e, v!));
            n.updateEdgeMetalType(e, v!);
          }),
          _edgesFromGeometry
              ? _calcBox('$e LF', '${_edgeLFController(e).text} LF', Icons.straighten)
              : _tf('$e LF', '0', _edgeLFController(e), suffix: 'LF',
                  kb: TextInputType.number,
                  onChange: (v) => n.updateEdgeMetalLF(e, double.tryParse(v) ?? 0)),
        ]),
      ],
      _sp12,
      _toggle('Perimeter Wood Nailers', 'Eave, rake and drip edges; height = insulation stack',
          _hasNailers, (v) { setState(() => _hasNailers = v); n.setNailersEnabled(v); }),
      if (_hasNailers) ...[
        _sp8,
        _dd('Nailer Width', _nailerWidth, kNailerWidths, (v) {
          setState(() => _nailerWidth = v!); n.updateNailerWidth(v!); }),
        _sp8,
        _calcBox('Nailers', _nailerSummary(), Icons.carpenter),
      ],
```

with helpers:

```dart
  String _edgeTypeMetal(String e) => switch (e) {
        'Rake Edge' => _rakeMetalType, 'Flat Drip Edge' => _flatDripMetalType, _ => _eaveMetalType };
  void _setEdgeTypeMetal(String e, String v) => switch (e) {
        'Rake Edge' => _rakeMetalType = v, 'Flat Drip Edge' => _flatDripMetalType = v, _ => _eaveMetalType = v };
  TextEditingController _edgeLFController(String e) => switch (e) {
        'Rake Edge' => _cRakeLF, 'Flat Drip Edge' => _cFlatDripLF, _ => _cEaveLF };
  String _nailerSummary() {
    final m = ref.read(metalScopeProvider);
    final stack = BomCalculator.stackThicknessPublic(ref.read(insulationSystemProvider), 3);
    final plies = stack <= 0 ? 1 : (stack / 1.5).ceil();
    return '${m.nailerLF.toStringAsFixed(0)} LF · ${stack.toStringAsFixed(1)}" stack · $plies plies';
  }
```

Wall Flashing LF: read-only `_calcBox` when `_edgesFromGeometry`; helper text `'From Headwall/Clerestory edges in geometry.'`.

- [ ] **Step 5: Verify** — `flutter analyze lib test` → no errors (warnings listed in report). Then use the `run` skill to launch the web app locally and check, on a new job: rectangle with all edges Eave/Flat Drip Edge, MA, Metal deck → BOM has no adhesive lines; set one edge to Parapet then back to Eave → parapet LF returns to 0 and no `(Parapet)` lines; set an edge to Headwall + 24" height → `(Headwall)` adhesive line; toggle nailers → Wood Nailers lines; cover board Nailbase → thickness list 1.5–4.0. Screenshot each.

- [ ] **Step 6: Commit (on approval)** — `git commit -m "feat(ui): geometry-driven walls/edges, headwall, edge metal per type, nailers, nailbase"`

---

### Task 10: Full verification and cleanup

- [ ] **Step 1:** Delete `test/scratch/` (session repro; superseded by Task 4 regression test): `rm -r test/scratch`
- [ ] **Step 2:** `flutter test` → all pass. Paste the summary line.
- [ ] **Step 3:** `flutter analyze` → no errors.
- [ ] **Step 4:** Hand-check three line items by a second route: FA 10,000 sf pails (35 on paper), nailer boards (55 on paper), headwall adhesive base gal (1.94). If the app shows 36/56, report it as a float-rounding over-order (x.000…01 rounding up) — it is pre-existing across the BOM's `ceil()` calls; flag to user, do not silently change rounding.
- [ ] **Step 5:** Report to user; do not push or deploy.
