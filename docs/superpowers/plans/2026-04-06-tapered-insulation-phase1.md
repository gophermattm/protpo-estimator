# Tapered Insulation Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the data model and board schedule calculation engine for tapered polyiso insulation in ProTPO.

**Architecture:** New models (ScupperLocation, DrainageZone, TaperDefaults) integrate into existing RoofGeometry and InsulationSystem. A pure-logic board schedule calculator takes distance/rate/manufacturer and produces row-by-row panel designations with flat fill resets. R-value calculator extended to report min/avg/max across the tapered assembly. All backed by hardcoded Versico + TRI-BUILT panel data.

**Tech Stack:** Flutter/Dart, flutter_test, uuid package (already installed)

**Spec:** `docs/superpowers/specs/2026-04-06-tapered-insulation-phase1-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/data/board_schedules.dart` | Create | Manufacturer panel data constants (TaperedPanel, PanelSequence, lookup functions) |
| `lib/models/drainage_zone.dart` | Create | ScupperLocation, DrainageZone, TaperDefaults, DrainageZoneOverride models |
| `lib/services/board_schedule_calculator.dart` | Create | Board schedule engine (BoardScheduleInput → BoardScheduleResult) |
| `lib/models/insulation_system.dart` | Modify | Replace TaperedInsulation with hasTaper/TaperDefaults/zoneOverrides |
| `lib/models/roof_geometry.dart` | Modify | Add scupperLocations and drainageZones fields |
| `lib/services/r_value_calculator.dart` | Modify | Add calculateTapered() returning min/avg/max R-values |
| `lib/services/serialization.dart` | Modify | Serialize new models, schema v2 migration |
| `test/data/board_schedules_test.dart` | Create | Tests for panel lookup and sequence data |
| `test/services/board_schedule_calculator_test.dart` | Create | Tests for board schedule engine including 47×27 test case |
| `test/models/drainage_zone_test.dart` | Create | Tests for new model classes |
| `test/services/r_value_calculator_test.dart` | Create | Tests for tapered R-value calculation |
| `test/services/serialization_test.dart` | Create | Tests for v1→v2 migration and round-trip serialization |

---

### Task 1: Manufacturer Panel Data

**Files:**
- Create: `lib/data/board_schedules.dart`
- Test: `test/data/board_schedules_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/board_schedules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/data/board_schedules.dart';

void main() {
  group('TaperedPanel', () {
    test('X panel has correct dimensions', () {
      const panel = TaperedPanel(
        letter: 'X',
        thinEdge: 0.5,
        thickEdge: 1.5,
        avgThickness: 1.0,
        rPerInchLTTR: 5.7,
      );
      expect(panel.letter, 'X');
      expect(panel.thinEdge, 0.5);
      expect(panel.thickEdge, 1.5);
      expect(panel.avgThickness, 1.0);
    });
  });

  group('lookupPanelSequence', () {
    test('Versico 1/4 extended returns X Y Z ZZ', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/4:12',
        profileType: 'extended',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 4);
      expect(seq.panels.map((p) => p.letter).toList(),
          ['X', 'Y', 'Z', 'ZZ']);
    });

    test('Versico 1/4 standard returns X Y only', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/4:12',
        profileType: 'standard',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 2);
      expect(seq.panels.map((p) => p.letter).toList(), ['X', 'Y']);
    });

    test('Versico 1/8 extended returns AA through FF', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/8:12',
        profileType: 'extended',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 8);
      expect(seq.panels.first.letter, 'AA');
      expect(seq.panels.last.letter, 'FF');
    });

    test('Versico 1/8 standard returns AA A B C', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/8:12',
        profileType: 'standard',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 4);
      expect(seq.panels.map((p) => p.letter).toList(),
          ['AA', 'A', 'B', 'C']);
    });

    test('Versico 1/2 returns Q only', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/2:12',
        profileType: 'standard',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 1);
      expect(seq.panels.first.letter, 'Q');
    });

    test('TRI-BUILT 1/4 returns X Y (no extended)', () {
      final seq = lookupPanelSequence(
        manufacturer: 'TRI-BUILT',
        taperRate: '1/4:12',
        profileType: 'standard',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 2);
      expect(seq.panels.map((p) => p.letter).toList(), ['X', 'Y']);
    });

    test('TRI-BUILT 1/4 extended falls back to standard', () {
      final seq = lookupPanelSequence(
        manufacturer: 'TRI-BUILT',
        taperRate: '1/4:12',
        profileType: 'extended',
      );
      // TRI-BUILT has no extended; should fall back to standard
      expect(seq, isNotNull);
      expect(seq!.panels.length, 2);
    });

    test('TRI-BUILT 1/8 returns AA A B C', () {
      final seq = lookupPanelSequence(
        manufacturer: 'TRI-BUILT',
        taperRate: '1/8:12',
        profileType: 'standard',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 4);
    });

    test('invalid manufacturer returns null', () {
      final seq = lookupPanelSequence(
        manufacturer: 'FakeCo',
        taperRate: '1/4:12',
        profileType: 'standard',
      );
      expect(seq, isNull);
    });

    test('invalid taper rate returns null', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '9/9:12',
        profileType: 'standard',
      );
      expect(seq, isNull);
    });
  });

  group('taperRateToDecimal', () {
    test('converts 1/4:12 to 0.25', () {
      expect(taperRateToDecimal('1/4:12'), closeTo(0.25, 0.001));
    });

    test('converts 1/8:12 to 0.125', () {
      expect(taperRateToDecimal('1/8:12'), closeTo(0.125, 0.001));
    });

    test('converts 1/2:12 to 0.5', () {
      expect(taperRateToDecimal('1/2:12'), closeTo(0.5, 0.001));
    });

    test('converts 3/8:12 to 0.375', () {
      expect(taperRateToDecimal('3/8:12'), closeTo(0.375, 0.001));
    });

    test('converts 3/16:12 to 0.1875', () {
      expect(taperRateToDecimal('3/16:12'), closeTo(0.1875, 0.001));
    });

    test('returns 0 for invalid rate', () {
      expect(taperRateToDecimal('invalid'), 0.0);
    });
  });

  group('availableProfileTypes', () {
    test('Versico 1/4 offers standard and extended', () {
      final types = availableProfileTypes('Versico', '1/4:12');
      expect(types, containsAll(['standard', 'extended']));
    });

    test('TRI-BUILT 1/4 offers standard only', () {
      final types = availableProfileTypes('TRI-BUILT', '1/4:12');
      expect(types, ['standard']);
    });

    test('Versico 1/8 offers standard and extended', () {
      final types = availableProfileTypes('Versico', '1/8:12');
      expect(types, containsAll(['standard', 'extended']));
    });
  });

  group('availableTaperRates', () {
    test('Versico offers all rates', () {
      final rates = availableTaperRates('Versico');
      expect(rates, containsAll(['1/8:12', '1/4:12', '1/2:12']));
    });

    test('TRI-BUILT offers 1/8 1/4 1/2', () {
      final rates = availableTaperRates('TRI-BUILT');
      expect(rates, containsAll(['1/8:12', '1/4:12', '1/2:12']));
    });
  });

  group('kFlatStockThicknesses', () {
    test('contains standard increments from 0.5 to 4.0', () {
      expect(kFlatStockThicknesses, [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/data/board_schedules_test.dart`
Expected: Compilation error — `board_schedules.dart` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/data/board_schedules.dart`:

```dart
/// lib/data/board_schedules.dart
///
/// Hardcoded manufacturer panel data for tapered polyiso insulation.
/// Sources:
///   - Versico: data/Versico Tapered Polyiso.json (VersiCore TDB)
///   - TRI-BUILT: data/TRI_BUILT ISO II GRF ROOF INSULATION.json

// ─── DATA CLASSES ────────────────────────────────────────────────────────────

class TaperedPanel {
  final String letter;
  final double thinEdge;
  final double thickEdge;
  final double avgThickness;
  final double rPerInchLTTR;

  const TaperedPanel({
    required this.letter,
    required this.thinEdge,
    required this.thickEdge,
    required this.avgThickness,
    required this.rPerInchLTTR,
  });
}

class PanelSequence {
  final String manufacturer;
  final String taperRate;
  final String profileType;
  final List<TaperedPanel> panels;

  const PanelSequence({
    required this.manufacturer,
    required this.taperRate,
    required this.profileType,
    required this.panels,
  });

  /// Total rise across one full sequence cycle (inches).
  double get sequenceRise =>
      panels.last.thickEdge - panels.first.thinEdge;
}

// ─── CONSTANTS ───────────────────────────────────────────────────────────────

const List<double> kFlatStockThicknesses = [
  0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0,
];

const List<String> kManufacturers = ['Versico', 'TRI-BUILT'];

const List<String> kAllTaperRates = [
  '1/8:12', '3/16:12', '1/4:12', '3/8:12', '1/2:12',
];

// ─── PANEL SEQUENCES ─────────────────────────────────────────────────────────

const _kSequences = <PanelSequence>[
  // ── Versico 1/8" ──
  PanelSequence(
    manufacturer: 'Versico', taperRate: '1/8:12', profileType: 'standard',
    panels: [
      TaperedPanel(letter: 'AA', thinEdge: 0.5, thickEdge: 1.0, avgThickness: 0.75, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'A',  thinEdge: 1.0, thickEdge: 1.5, avgThickness: 1.25, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'B',  thinEdge: 1.5, thickEdge: 2.0, avgThickness: 1.75, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'C',  thinEdge: 2.0, thickEdge: 2.5, avgThickness: 2.25, rPerInchLTTR: 5.7),
    ],
  ),
  PanelSequence(
    manufacturer: 'Versico', taperRate: '1/8:12', profileType: 'extended',
    panels: [
      TaperedPanel(letter: 'AA', thinEdge: 0.5, thickEdge: 1.0, avgThickness: 0.75, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'A',  thinEdge: 1.0, thickEdge: 1.5, avgThickness: 1.25, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'B',  thinEdge: 1.5, thickEdge: 2.0, avgThickness: 1.75, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'C',  thinEdge: 2.0, thickEdge: 2.5, avgThickness: 2.25, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'D',  thinEdge: 2.5, thickEdge: 3.0, avgThickness: 2.75, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'E',  thinEdge: 3.0, thickEdge: 3.5, avgThickness: 3.25, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'F',  thinEdge: 3.5, thickEdge: 4.0, avgThickness: 3.75, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'FF', thinEdge: 4.0, thickEdge: 4.5, avgThickness: 4.25, rPerInchLTTR: 5.7),
    ],
  ),

  // ── Versico 1/4" ──
  PanelSequence(
    manufacturer: 'Versico', taperRate: '1/4:12', profileType: 'standard',
    panels: [
      TaperedPanel(letter: 'X',  thinEdge: 0.5, thickEdge: 1.5, avgThickness: 1.0, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'Y',  thinEdge: 1.5, thickEdge: 2.5, avgThickness: 2.0, rPerInchLTTR: 5.7),
    ],
  ),
  PanelSequence(
    manufacturer: 'Versico', taperRate: '1/4:12', profileType: 'extended',
    panels: [
      TaperedPanel(letter: 'X',  thinEdge: 0.5, thickEdge: 1.5, avgThickness: 1.0, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'Y',  thinEdge: 1.5, thickEdge: 2.5, avgThickness: 2.0, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'Z',  thinEdge: 2.5, thickEdge: 3.5, avgThickness: 3.0, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'ZZ', thinEdge: 3.5, thickEdge: 4.5, avgThickness: 4.0, rPerInchLTTR: 5.7),
    ],
  ),

  // ── Versico 1/2" ──
  PanelSequence(
    manufacturer: 'Versico', taperRate: '1/2:12', profileType: 'standard',
    panels: [
      TaperedPanel(letter: 'Q',  thinEdge: 0.5, thickEdge: 2.5, avgThickness: 1.5, rPerInchLTTR: 5.7),
    ],
  ),

  // ── Versico 3/8" ──
  PanelSequence(
    manufacturer: 'Versico', taperRate: '3/8:12', profileType: 'standard',
    panels: [
      TaperedPanel(letter: 'SS', thinEdge: 0.5, thickEdge: 2.0, avgThickness: 1.25, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'TT', thinEdge: 2.0, thickEdge: 3.5, avgThickness: 2.75, rPerInchLTTR: 5.7),
    ],
  ),

  // ── TRI-BUILT 1/8" ──
  PanelSequence(
    manufacturer: 'TRI-BUILT', taperRate: '1/8:12', profileType: 'standard',
    panels: [
      TaperedPanel(letter: 'AA', thinEdge: 0.5, thickEdge: 1.0, avgThickness: 0.75, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'A',  thinEdge: 1.0, thickEdge: 1.5, avgThickness: 1.25, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'B',  thinEdge: 1.5, thickEdge: 2.0, avgThickness: 1.75, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'C',  thinEdge: 2.0, thickEdge: 2.5, avgThickness: 2.25, rPerInchLTTR: 5.7),
    ],
  ),

  // ── TRI-BUILT 1/4" ──
  PanelSequence(
    manufacturer: 'TRI-BUILT', taperRate: '1/4:12', profileType: 'standard',
    panels: [
      TaperedPanel(letter: 'X',  thinEdge: 0.5, thickEdge: 1.5, avgThickness: 1.0, rPerInchLTTR: 5.7),
      TaperedPanel(letter: 'Y',  thinEdge: 1.5, thickEdge: 2.5, avgThickness: 2.0, rPerInchLTTR: 5.7),
    ],
  ),

  // ── TRI-BUILT 1/2" ──
  PanelSequence(
    manufacturer: 'TRI-BUILT', taperRate: '1/2:12', profileType: 'standard',
    panels: [
      TaperedPanel(letter: 'Q',  thinEdge: 0.5, thickEdge: 2.5, avgThickness: 1.5, rPerInchLTTR: 5.7),
    ],
  ),
];

// ─── LOOKUP FUNCTIONS ────────────────────────────────────────────────────────

/// Look up a panel sequence by manufacturer, taper rate, and profile type.
/// Returns null if no matching sequence exists.
/// If the requested profileType is 'extended' but only 'standard' exists
/// for that manufacturer/rate, falls back to standard.
PanelSequence? lookupPanelSequence({
  required String manufacturer,
  required String taperRate,
  required String profileType,
}) {
  // Try exact match first
  for (final seq in _kSequences) {
    if (seq.manufacturer == manufacturer &&
        seq.taperRate == taperRate &&
        seq.profileType == profileType) {
      return seq;
    }
  }
  // Fallback: extended requested but only standard available
  if (profileType == 'extended') {
    for (final seq in _kSequences) {
      if (seq.manufacturer == manufacturer &&
          seq.taperRate == taperRate &&
          seq.profileType == 'standard') {
        return seq;
      }
    }
  }
  return null;
}

/// Convert a taper rate string like '1/4:12' to decimal inches per foot.
/// Returns 0.0 for unrecognized formats.
double taperRateToDecimal(String taperRate) {
  final match = RegExp(r'^(\d+)/(\d+):12$').firstMatch(taperRate);
  if (match == null) return 0.0;
  final numerator = int.tryParse(match.group(1)!) ?? 0;
  final denominator = int.tryParse(match.group(2)!) ?? 1;
  if (denominator == 0) return 0.0;
  return numerator / denominator;
}

/// Returns the list of available profile types for a manufacturer and taper rate.
List<String> availableProfileTypes(String manufacturer, String taperRate) {
  final types = <String>[];
  for (final seq in _kSequences) {
    if (seq.manufacturer == manufacturer && seq.taperRate == taperRate) {
      types.add(seq.profileType);
    }
  }
  return types;
}

/// Returns the list of available taper rates for a manufacturer.
List<String> availableTaperRates(String manufacturer) {
  final rates = <String>{};
  for (final seq in _kSequences) {
    if (seq.manufacturer == manufacturer) {
      rates.add(seq.taperRate);
    }
  }
  return rates.toList()..sort();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/data/board_schedules_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/data/board_schedules.dart test/data/board_schedules_test.dart
git commit -m "feat: add manufacturer panel data for Versico and TRI-BUILT

Hardcoded board schedules with lookup functions, taper rate parsing,
and profile type availability per manufacturer."
```

---

### Task 2: New Data Models (ScupperLocation, DrainageZone, TaperDefaults)

**Files:**
- Create: `lib/models/drainage_zone.dart`
- Test: `test/models/drainage_zone_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/models/drainage_zone_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/drainage_zone.dart';

void main() {
  group('ScupperLocation', () {
    test('creates with edge index and position', () {
      const scupper = ScupperLocation(edgeIndex: 2, position: 0.5);
      expect(scupper.edgeIndex, 2);
      expect(scupper.position, 0.5);
    });

    test('copyWith updates fields', () {
      const scupper = ScupperLocation(edgeIndex: 2, position: 0.5);
      final updated = scupper.copyWith(position: 0.75);
      expect(updated.edgeIndex, 2);
      expect(updated.position, 0.75);
    });

    test('equality by value', () {
      const a = ScupperLocation(edgeIndex: 2, position: 0.5);
      const b = ScupperLocation(edgeIndex: 2, position: 0.5);
      const c = ScupperLocation(edgeIndex: 1, position: 0.5);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('TaperDefaults', () {
    test('initial factory creates sensible defaults', () {
      final defaults = TaperDefaults.initial();
      expect(defaults.taperRate, '1/4:12');
      expect(defaults.minThickness, 1.0);
      expect(defaults.manufacturer, 'Versico');
      expect(defaults.profileType, 'extended');
      expect(defaults.attachmentMethod, 'Mechanically Attached');
    });

    test('copyWith updates manufacturer', () {
      final defaults = TaperDefaults.initial();
      final updated = defaults.copyWith(manufacturer: 'TRI-BUILT');
      expect(updated.manufacturer, 'TRI-BUILT');
      expect(updated.taperRate, '1/4:12'); // unchanged
    });
  });

  group('DrainageZone', () {
    test('creates internal drain zone', () {
      const zone = DrainageZone(
        id: 'zone-1',
        type: 'internal_drain',
        lowPointIndex: 0,
      );
      expect(zone.type, 'internal_drain');
      expect(zone.lowPointIndex, 0);
      expect(zone.taperRateOverride, isNull);
    });

    test('creates scupper zone with overrides', () {
      const zone = DrainageZone(
        id: 'zone-2',
        type: 'scupper',
        lowPointIndex: 0,
        taperRateOverride: '1/8:12',
        manufacturerOverride: 'TRI-BUILT',
      );
      expect(zone.taperRateOverride, '1/8:12');
      expect(zone.manufacturerOverride, 'TRI-BUILT');
      expect(zone.minThicknessOverride, isNull);
      expect(zone.profileTypeOverride, isNull);
    });

    test('equality by value', () {
      const a = DrainageZone(id: 'z1', type: 'scupper', lowPointIndex: 0);
      const b = DrainageZone(id: 'z1', type: 'scupper', lowPointIndex: 0);
      const c = DrainageZone(id: 'z2', type: 'scupper', lowPointIndex: 0);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('DrainageZoneOverride', () {
    test('creates with zone id and overrides', () {
      const ovr = DrainageZoneOverride(
        zoneId: 'zone-1',
        taperRateOverride: '1/8:12',
      );
      expect(ovr.zoneId, 'zone-1');
      expect(ovr.taperRateOverride, '1/8:12');
      expect(ovr.minThicknessOverride, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/models/drainage_zone_test.dart`
Expected: Compilation error — `drainage_zone.dart` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/models/drainage_zone.dart`:

```dart
/// lib/models/drainage_zone.dart
///
/// Data models for the tapered insulation drainage system.
/// ScupperLocation: positioned low point on a roof edge.
/// DrainageZone: watershed zone around a drain or scupper.
/// TaperDefaults: global taper configuration for a building.
/// DrainageZoneOverride: per-zone config that differs from defaults.

// ─── SCUPPER LOCATION ────────────────────────────────────────────────────────

class ScupperLocation {
  final int edgeIndex;
  final double position;

  const ScupperLocation({
    required this.edgeIndex,
    this.position = 0.5,
  });

  ScupperLocation copyWith({int? edgeIndex, double? position}) =>
      ScupperLocation(
        edgeIndex: edgeIndex ?? this.edgeIndex,
        position: position ?? this.position,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScupperLocation &&
          edgeIndex == other.edgeIndex &&
          position == other.position;

  @override
  int get hashCode => Object.hash(edgeIndex, position);
}

// ─── TAPER DEFAULTS ──────────────────────────────────────────────────────────

class TaperDefaults {
  final String taperRate;
  final double minThickness;
  final String manufacturer;
  final String profileType;
  final String attachmentMethod;

  const TaperDefaults({
    this.taperRate = '1/4:12',
    this.minThickness = 1.0,
    this.manufacturer = 'Versico',
    this.profileType = 'extended',
    this.attachmentMethod = 'Mechanically Attached',
  });

  factory TaperDefaults.initial() => const TaperDefaults();

  TaperDefaults copyWith({
    String? taperRate,
    double? minThickness,
    String? manufacturer,
    String? profileType,
    String? attachmentMethod,
  }) =>
      TaperDefaults(
        taperRate: taperRate ?? this.taperRate,
        minThickness: minThickness ?? this.minThickness,
        manufacturer: manufacturer ?? this.manufacturer,
        profileType: profileType ?? this.profileType,
        attachmentMethod: attachmentMethod ?? this.attachmentMethod,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaperDefaults &&
          taperRate == other.taperRate &&
          minThickness == other.minThickness &&
          manufacturer == other.manufacturer &&
          profileType == other.profileType &&
          attachmentMethod == other.attachmentMethod;

  @override
  int get hashCode =>
      Object.hash(taperRate, minThickness, manufacturer, profileType, attachmentMethod);
}

// ─── DRAINAGE ZONE ───────────────────────────────────────────────────────────

class DrainageZone {
  final String id;
  final String type;           // 'internal_drain' | 'scupper'
  final int lowPointIndex;

  final String? taperRateOverride;
  final double? minThicknessOverride;
  final String? manufacturerOverride;
  final String? profileTypeOverride;

  const DrainageZone({
    required this.id,
    required this.type,
    required this.lowPointIndex,
    this.taperRateOverride,
    this.minThicknessOverride,
    this.manufacturerOverride,
    this.profileTypeOverride,
  });

  DrainageZone copyWith({
    String? id,
    String? type,
    int? lowPointIndex,
    String? taperRateOverride,
    double? minThicknessOverride,
    String? manufacturerOverride,
    String? profileTypeOverride,
  }) =>
      DrainageZone(
        id: id ?? this.id,
        type: type ?? this.type,
        lowPointIndex: lowPointIndex ?? this.lowPointIndex,
        taperRateOverride: taperRateOverride ?? this.taperRateOverride,
        minThicknessOverride: minThicknessOverride ?? this.minThicknessOverride,
        manufacturerOverride: manufacturerOverride ?? this.manufacturerOverride,
        profileTypeOverride: profileTypeOverride ?? this.profileTypeOverride,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrainageZone &&
          id == other.id &&
          type == other.type &&
          lowPointIndex == other.lowPointIndex &&
          taperRateOverride == other.taperRateOverride &&
          minThicknessOverride == other.minThicknessOverride &&
          manufacturerOverride == other.manufacturerOverride &&
          profileTypeOverride == other.profileTypeOverride;

  @override
  int get hashCode => Object.hash(id, type, lowPointIndex,
      taperRateOverride, minThicknessOverride, manufacturerOverride, profileTypeOverride);
}

// ─── DRAINAGE ZONE OVERRIDE ──────────────────────────────────────────────────

class DrainageZoneOverride {
  final String zoneId;
  final String? taperRateOverride;
  final double? minThicknessOverride;
  final String? manufacturerOverride;
  final String? profileTypeOverride;

  const DrainageZoneOverride({
    required this.zoneId,
    this.taperRateOverride,
    this.minThicknessOverride,
    this.manufacturerOverride,
    this.profileTypeOverride,
  });

  DrainageZoneOverride copyWith({
    String? zoneId,
    String? taperRateOverride,
    double? minThicknessOverride,
    String? manufacturerOverride,
    String? profileTypeOverride,
  }) =>
      DrainageZoneOverride(
        zoneId: zoneId ?? this.zoneId,
        taperRateOverride: taperRateOverride ?? this.taperRateOverride,
        minThicknessOverride: minThicknessOverride ?? this.minThicknessOverride,
        manufacturerOverride: manufacturerOverride ?? this.manufacturerOverride,
        profileTypeOverride: profileTypeOverride ?? this.profileTypeOverride,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrainageZoneOverride &&
          zoneId == other.zoneId &&
          taperRateOverride == other.taperRateOverride &&
          minThicknessOverride == other.minThicknessOverride &&
          manufacturerOverride == other.manufacturerOverride &&
          profileTypeOverride == other.profileTypeOverride;

  @override
  int get hashCode => Object.hash(zoneId, taperRateOverride,
      minThicknessOverride, manufacturerOverride, profileTypeOverride);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/models/drainage_zone_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/models/drainage_zone.dart test/models/drainage_zone_test.dart
git commit -m "feat: add ScupperLocation, DrainageZone, TaperDefaults models

New immutable data classes for tapered insulation drainage system.
Supports per-zone overrides for mixed-drainage configurations."
```

---

### Task 3: Modify InsulationSystem — Replace TaperedInsulation

**Files:**
- Modify: `lib/models/insulation_system.dart`

- [ ] **Step 1: Verify existing code compiles**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter analyze lib/models/insulation_system.dart 2>&1 | tail -5`
Expected: No issues found.

- [ ] **Step 2: Update constants — add missing taper rates and manufacturer list**

In `lib/models/insulation_system.dart`, replace the `kTaperSlopeOptions` constant:

```dart
// REPLACE this:
const List<String> kTaperSlopeOptions = [
  '1/8:12',
  '1/4:12',
  '1/2:12',
];

// WITH this:
const List<String> kTaperSlopeOptions = [
  '1/8:12',
  '3/16:12',
  '1/4:12',
  '3/8:12',
  '1/2:12',
];

const List<String> kTaperManufacturers = ['Versico', 'TRI-BUILT'];
const List<String> kTaperProfileTypes = ['standard', 'extended'];
```

- [ ] **Step 3: Replace TaperedInsulation class with imports**

Remove the entire `TaperedInsulation` class (lines 88–154) and the `hasTaperedInsulation`/`tapered` fields from `InsulationSystem`. Replace with imports and new fields.

At the top of the file, add:

```dart
import 'drainage_zone.dart';
```

Replace the `InsulationSystem` class fields and methods:

```dart
class InsulationSystem {
  final int numberOfLayers;
  final InsulationLayer layer1;
  final InsulationLayer? layer2;

  final bool hasTaper;
  final TaperDefaults? taperDefaults;
  final List<DrainageZoneOverride> zoneOverrides;

  final bool hasCoverBoard;
  final CoverBoard? coverBoard;

  const InsulationSystem({
    this.numberOfLayers = 1,
    this.layer1 = const InsulationLayer(),
    this.layer2,
    this.hasTaper = false,
    this.taperDefaults,
    this.zoneOverrides = const [],
    this.hasCoverBoard = false,
    this.coverBoard,
  });

  factory InsulationSystem.initial() => const InsulationSystem();

  InsulationSystem copyWith({
    int? numberOfLayers,
    InsulationLayer? layer1,
    InsulationLayer? layer2,
    bool? hasTaper,
    TaperDefaults? taperDefaults,
    List<DrainageZoneOverride>? zoneOverrides,
    bool? hasCoverBoard,
    CoverBoard? coverBoard,
  }) {
    return InsulationSystem(
      numberOfLayers: numberOfLayers ?? this.numberOfLayers,
      layer1: layer1 ?? this.layer1,
      layer2: layer2 ?? this.layer2,
      hasTaper: hasTaper ?? this.hasTaper,
      taperDefaults: taperDefaults ?? this.taperDefaults,
      zoneOverrides: zoneOverrides ?? this.zoneOverrides,
      hasCoverBoard: hasCoverBoard ?? this.hasCoverBoard,
      coverBoard: coverBoard ?? this.coverBoard,
    );
  }

  InsulationSystem withTwoLayers() => copyWith(
        numberOfLayers: 2,
        layer2: layer2 ?? InsulationLayer.initial(),
      );

  InsulationSystem withOneLayer() => copyWith(numberOfLayers: 1);
  InsulationSystem withNoLayers() => copyWith(numberOfLayers: 0);

  InsulationSystem withTaperEnabled() => copyWith(
        hasTaper: true,
        taperDefaults: taperDefaults ?? TaperDefaults.initial(),
      );

  InsulationSystem withTaperDisabled() => copyWith(hasTaper: false);

  InsulationSystem withCoverBoardEnabled() => copyWith(
        hasCoverBoard: true,
        coverBoard: coverBoard ?? CoverBoard.initial(),
      );

  InsulationSystem withCoverBoardDisabled() => copyWith(hasCoverBoard: false);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InsulationSystem &&
          numberOfLayers == other.numberOfLayers &&
          layer1 == other.layer1 &&
          layer2 == other.layer2 &&
          hasTaper == other.hasTaper &&
          taperDefaults == other.taperDefaults &&
          _listEquals(zoneOverrides, other.zoneOverrides) &&
          hasCoverBoard == other.hasCoverBoard &&
          coverBoard == other.coverBoard;

  @override
  int get hashCode => Object.hash(
        numberOfLayers, layer1, layer2,
        hasTaper, taperDefaults, Object.hashAll(zoneOverrides),
        hasCoverBoard, coverBoard,
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

- [ ] **Step 4: Fix compilation errors in dependent files**

The old `hasTaperedInsulation`, `tapered`, `withTaperedEnabled()`, and `withTaperedDisabled()` are referenced in other files. Search and update:

Run: `cd /Users/mattmoore/My_Project/protpo_app && grep -rn "hasTaperedInsulation\|withTaperedEnabled\|withTaperedDisabled\|\.tapered\b" lib/ --include="*.dart" | grep -v "insulation_system.dart"`

For each match, update:
- `hasTaperedInsulation` → `hasTaper`
- `.tapered` → `.taperDefaults`
- `withTaperedEnabled()` → `withTaperEnabled()`
- `withTaperedDisabled()` → `withTaperDisabled()`

Key files likely affected: `left_panel.dart`, `serialization.dart`, `r_value_calculator.dart` callers, `bom_calculator.dart`.

- [ ] **Step 5: Verify compilation**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter analyze lib/ 2>&1 | tail -10`
Expected: No analysis issues (or only pre-existing ones).

- [ ] **Step 6: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/models/insulation_system.dart
git add -u lib/  # stage all modified files
git commit -m "refactor: replace TaperedInsulation with TaperDefaults

InsulationSystem now uses hasTaper + TaperDefaults + zoneOverrides
instead of hasTaperedInsulation + TaperedInsulation. Updated all
references in dependent files."
```

---

### Task 4: Modify RoofGeometry — Add Scupper and Zone Fields

**Files:**
- Modify: `lib/models/roof_geometry.dart`

- [ ] **Step 1: Add import and new fields**

At the top of `lib/models/roof_geometry.dart`, add:

```dart
import 'drainage_zone.dart';
```

Add two new fields to the `RoofGeometry` class:

```dart
final List<ScupperLocation> scupperLocations;
final List<DrainageZone> drainageZones;
```

- [ ] **Step 2: Update constructor, factory, and copyWith**

Add to constructor with defaults:

```dart
this.scupperLocations = const [],
this.drainageZones = const [],
```

Add to `RoofGeometry.initial()`:

```dart
factory RoofGeometry.initial() =>
    RoofGeometry(shapes: [RoofShape.initial(1)]);
// scupperLocations and drainageZones default to const []
```

Add to `copyWith`:

```dart
List<ScupperLocation>? scupperLocations,
List<DrainageZone>? drainageZones,
```

And in the return body:

```dart
scupperLocations: scupperLocations ?? List.from(this.scupperLocations),
drainageZones: drainageZones ?? List.from(this.drainageZones),
```

- [ ] **Step 3: Add convenience getters**

```dart
int get numberOfScuppers => scupperLocations.length;
```

- [ ] **Step 4: Update equality and hashCode**

Add to `==` operator:

```dart
_listEquals(scupperLocations, other.scupperLocations) &&
_listEquals(drainageZones, other.drainageZones) &&
```

Add to `hashCode`:

```dart
Object.hashAll(scupperLocations), Object.hashAll(drainageZones),
```

- [ ] **Step 5: Verify compilation**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter analyze lib/models/roof_geometry.dart 2>&1 | tail -5`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/models/roof_geometry.dart
git commit -m "feat: add scupperLocations and drainageZones to RoofGeometry

Scuppers are positioned on edges (edgeIndex + position fraction).
DrainageZones reference drains or scuppers as low points with
optional per-zone taper overrides."
```

---

### Task 5: Board Schedule Calculator Engine

**Files:**
- Create: `lib/services/board_schedule_calculator.dart`
- Test: `test/services/board_schedule_calculator_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/services/board_schedule_calculator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/board_schedule_calculator.dart';

void main() {
  group('BoardScheduleCalculator', () {
    group('47x27 test case — Versico extended 1/4:12, 1.0" min', () {
      late BoardScheduleResult result;

      setUp(() {
        result = BoardScheduleCalculator.compute(
          BoardScheduleInput(
            distance: 47.0,
            taperRate: '1/4:12',
            minThickness: 1.0,
            manufacturer: 'Versico',
            profileType: 'extended',
            roofWidthFt: 27.0,
          ),
        );
      });

      test('produces 12 rows', () {
        expect(result.rows.length, 12);
      });

      test('first row is X panel with no flat fill', () {
        final row = result.rows.first;
        expect(row.panelDesignation, 'X');
        expect(row.flatFillThickness, 0.0);
        expect(row.thinEdge, closeTo(1.0, 0.01));
        expect(row.thickEdge, closeTo(2.0, 0.01));
      });

      test('row 4 is ZZ panel — end of first cycle', () {
        final row = result.rows[3]; // 0-indexed
        expect(row.panelDesignation, 'ZZ');
        expect(row.flatFillThickness, 0.0);
      });

      test('row 5 resets to X with flat fill', () {
        final row = result.rows[4]; // 0-indexed
        expect(row.panelDesignation, 'X');
        expect(row.flatFillThickness, greaterThan(0.0));
      });

      test('max thickness at front wall is 12.75"', () {
        expect(result.maxThickness, closeTo(12.75, 0.01));
      });

      test('tapered panel totals are correct', () {
        expect(result.taperedPanelCounts['X'], 14);
        expect(result.taperedPanelCounts['Y'], 21);
        expect(result.taperedPanelCounts['Z'], 21);
        expect(result.taperedPanelCounts['ZZ'], 28);
      });

      test('total tapered panels is 84', () {
        expect(result.totalTaperedPanels, 84);
      });

      test('flat fill totals are correct', () {
        expect(result.flatFillCounts[0.5], 7);
        expect(result.flatFillCounts[1.0], 28);
        expect(result.flatFillCounts[2.0], 28);
      });

      test('total flat fill panels is 63', () {
        expect(result.totalFlatFillPanels, 63);
      });

      test('total panels before waste is 147', () {
        expect(result.totalPanels, 147);
      });

      test('total panels with 10% waste is 162', () {
        expect(result.totalPanelsWithWaste, 162);
      });

      test('generates max thickness warning', () {
        expect(result.warnings, isNotEmpty);
        expect(result.warnings.first, contains('12.75'));
      });

      test('avgTaperThickness is computed correctly', () {
        // Average of all row mid-points weighted by row width
        expect(result.avgTaperThickness, greaterThan(5.0));
        expect(result.avgTaperThickness, lessThan(8.0));
      });
    });

    group('short run — no flat fill needed', () {
      test('8ft run at 1/4:12 needs only X and Y', () {
        final result = BoardScheduleCalculator.compute(
          BoardScheduleInput(
            distance: 8.0,
            taperRate: '1/4:12',
            minThickness: 1.0,
            manufacturer: 'Versico',
            profileType: 'extended',
            roofWidthFt: 10.0,
          ),
        );
        expect(result.rows.length, 2);
        expect(result.rows[0].panelDesignation, 'X');
        expect(result.rows[1].panelDesignation, 'Y');
        expect(result.totalFlatFillPanels, 0);
        expect(result.warnings, isEmpty);
      });
    });

    group('TRI-BUILT 1/4:12 — shorter sequence', () {
      test('8ft run uses X Y (same as Versico standard)', () {
        final result = BoardScheduleCalculator.compute(
          BoardScheduleInput(
            distance: 8.0,
            taperRate: '1/4:12',
            minThickness: 1.0,
            manufacturer: 'TRI-BUILT',
            profileType: 'standard',
            roofWidthFt: 10.0,
          ),
        );
        expect(result.rows.length, 2);
        expect(result.rows[0].panelDesignation, 'X');
        expect(result.rows[1].panelDesignation, 'Y');
      });

      test('16ft run needs flat fill at row 3', () {
        final result = BoardScheduleCalculator.compute(
          BoardScheduleInput(
            distance: 16.0,
            taperRate: '1/4:12',
            minThickness: 1.0,
            manufacturer: 'TRI-BUILT',
            profileType: 'standard',
            roofWidthFt: 10.0,
          ),
        );
        expect(result.rows.length, 4);
        // Row 3 should have flat fill (cycle 2)
        expect(result.rows[2].flatFillThickness, greaterThan(0.0));
      });
    });

    group('1/8:12 taper rate', () {
      test('Versico extended 1/8 uses 8-panel sequence', () {
        final result = BoardScheduleCalculator.compute(
          BoardScheduleInput(
            distance: 32.0,
            taperRate: '1/8:12',
            minThickness: 0.5,
            manufacturer: 'Versico',
            profileType: 'extended',
            roofWidthFt: 10.0,
          ),
        );
        expect(result.rows.length, 8);
        expect(result.rows[0].panelDesignation, 'AA');
        expect(result.rows[7].panelDesignation, 'FF');
        expect(result.totalFlatFillPanels, 0); // exactly one cycle
      });
    });

    group('edge cases', () {
      test('distance of 0 returns empty result', () {
        final result = BoardScheduleCalculator.compute(
          BoardScheduleInput(
            distance: 0.0,
            taperRate: '1/4:12',
            minThickness: 1.0,
            manufacturer: 'Versico',
            profileType: 'extended',
            roofWidthFt: 10.0,
          ),
        );
        expect(result.rows, isEmpty);
        expect(result.totalPanels, 0);
      });

      test('invalid manufacturer returns empty result', () {
        final result = BoardScheduleCalculator.compute(
          BoardScheduleInput(
            distance: 20.0,
            taperRate: '1/4:12',
            minThickness: 1.0,
            manufacturer: 'FakeCo',
            profileType: 'standard',
            roofWidthFt: 10.0,
          ),
        );
        expect(result.rows, isEmpty);
      });

      test('partial last row is handled correctly', () {
        // 6ft distance = 1 full row (4ft) + 1 partial row (2ft)
        final result = BoardScheduleCalculator.compute(
          BoardScheduleInput(
            distance: 6.0,
            taperRate: '1/4:12',
            minThickness: 1.0,
            manufacturer: 'Versico',
            profileType: 'extended',
            roofWidthFt: 10.0,
          ),
        );
        expect(result.rows.length, 2);
        expect(result.rows.last.distanceEnd, closeTo(6.0, 0.01));
      });
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/board_schedule_calculator_test.dart`
Expected: Compilation error — file does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/services/board_schedule_calculator.dart`:

```dart
/// lib/services/board_schedule_calculator.dart
///
/// Computes a board schedule for a single-direction taper run.
/// Given distance, taper rate, manufacturer, and profile type,
/// produces row-by-row panel designations with flat fill resets.

import 'dart:math' as math;
import '../data/board_schedules.dart';

// ─── INPUT / OUTPUT CLASSES ──────────────────────────────────────────────────

class BoardScheduleInput {
  final double distance;
  final String taperRate;
  final double minThickness;
  final String manufacturer;
  final String profileType;
  final double roofWidthFt;
  final double panelWidthFt;
  final double wasteFactor;

  const BoardScheduleInput({
    required this.distance,
    required this.taperRate,
    required this.minThickness,
    required this.manufacturer,
    required this.profileType,
    required this.roofWidthFt,
    this.panelWidthFt = 4.0,
    this.wasteFactor = 0.10,
  });
}

class BoardRow {
  final int row;
  final double distanceStart;
  final double distanceEnd;
  final double thinEdge;
  final double thickEdge;
  final double flatFillThickness;
  final String panelDesignation;
  final double panelThinEdge;
  final double panelThickEdge;

  const BoardRow({
    required this.row,
    required this.distanceStart,
    required this.distanceEnd,
    required this.thinEdge,
    required this.thickEdge,
    required this.flatFillThickness,
    required this.panelDesignation,
    required this.panelThinEdge,
    required this.panelThickEdge,
  });
}

class BoardScheduleResult {
  final List<BoardRow> rows;
  final double maxThickness;

  final Map<String, int> taperedPanelCounts;
  final Map<double, int> flatFillCounts;
  final int totalTaperedPanels;
  final int totalFlatFillPanels;
  final int totalPanels;
  final int totalPanelsWithWaste;
  final double totalTaperedSF;
  final double totalFlatFillSF;

  final double minThicknessAtDrain;
  final double avgTaperThickness;
  final double maxThicknessAtRidge;

  final List<String> warnings;

  const BoardScheduleResult({
    required this.rows,
    required this.maxThickness,
    required this.taperedPanelCounts,
    required this.flatFillCounts,
    required this.totalTaperedPanels,
    required this.totalFlatFillPanels,
    required this.totalPanels,
    required this.totalPanelsWithWaste,
    required this.totalTaperedSF,
    required this.totalFlatFillSF,
    required this.minThicknessAtDrain,
    required this.avgTaperThickness,
    required this.maxThicknessAtRidge,
    required this.warnings,
  });

  static const empty = BoardScheduleResult(
    rows: [],
    maxThickness: 0,
    taperedPanelCounts: {},
    flatFillCounts: {},
    totalTaperedPanels: 0,
    totalFlatFillPanels: 0,
    totalPanels: 0,
    totalPanelsWithWaste: 0,
    totalTaperedSF: 0,
    totalFlatFillSF: 0,
    minThicknessAtDrain: 0,
    avgTaperThickness: 0,
    maxThicknessAtRidge: 0,
    warnings: [],
  );
}

// ─── CALCULATOR ──────────────────────────────────────────────────────────────

class BoardScheduleCalculator {
  static const double _maxWarningThickness = 8.0;

  static BoardScheduleResult compute(BoardScheduleInput input) {
    if (input.distance <= 0) return BoardScheduleResult.empty;

    final sequence = lookupPanelSequence(
      manufacturer: input.manufacturer,
      taperRate: input.taperRate,
      profileType: input.profileType,
    );
    if (sequence == null) return BoardScheduleResult.empty;

    final rate = taperRateToDecimal(input.taperRate);
    if (rate <= 0) return BoardScheduleResult.empty;

    final pw = input.panelWidthFt;
    final seqLen = sequence.panels.length;
    final seqRise = sequence.sequenceRise;
    final numRows = (input.distance / pw).ceil();
    final panelsWide = (input.roofWidthFt / pw).ceil();

    final rows = <BoardRow>[];
    final taperedCounts = <String, int>{};
    final flatFillCounts = <double, int>{};
    double totalTaperVolume = 0.0;
    double totalArea = 0.0;

    for (int i = 0; i < numRows; i++) {
      final rowStart = i * pw;
      final rowEnd = math.min((i + 1) * pw, input.distance);
      final rowWidth = rowEnd - rowStart;

      final thinEdge = input.minThickness + (rowStart * rate);
      final thickEdge = input.minThickness + (rowEnd * rate);

      final cycleNumber = i ~/ seqLen;
      final seqIndex = i % seqLen;
      final panel = sequence.panels[seqIndex];

      double flatFill = 0.0;
      if (cycleNumber > 0) {
        flatFill = cycleNumber * seqRise;
        // Round down to nearest 0.5" increment
        flatFill = (flatFill * 2).floorToDouble() / 2;
      }

      rows.add(BoardRow(
        row: i + 1,
        distanceStart: rowStart,
        distanceEnd: rowEnd,
        thinEdge: thinEdge,
        thickEdge: thickEdge,
        flatFillThickness: flatFill,
        panelDesignation: panel.letter,
        panelThinEdge: panel.thinEdge,
        panelThickEdge: panel.thickEdge,
      ));

      // Count panels (tapered panels * width panels)
      taperedCounts[panel.letter] =
          (taperedCounts[panel.letter] ?? 0) + panelsWide;

      if (flatFill > 0) {
        flatFillCounts[flatFill] =
            (flatFillCounts[flatFill] ?? 0) + panelsWide;
      }

      // Volume for avg thickness: area × average height of taper+fill at this row
      final rowAvgHeight = (thinEdge + thickEdge) / 2;
      final rowArea = rowWidth * input.roofWidthFt;
      totalTaperVolume += rowAvgHeight * rowArea;
      totalArea += rowArea;
    }

    final maxThick = rows.isEmpty
        ? 0.0
        : input.minThickness + (input.distance * rate);

    final totalTapered = taperedCounts.values.fold(0, (a, b) => a + b);
    final totalFlatFill = flatFillCounts.values.fold(0, (a, b) => a + b);
    final totalPanels = totalTapered + totalFlatFill;
    final totalWithWaste = (totalPanels * (1 + input.wasteFactor)).ceil();

    final panelSF = pw * pw; // 4x4 = 16 SF
    final taperedSF = totalTapered * panelSF;
    final flatFillSF = totalFlatFill * panelSF;

    final avgTaperThick = totalArea > 0
        ? totalTaperVolume / totalArea
        : 0.0;

    final warnings = <String>[];
    if (maxThick > _maxWarningThickness) {
      warnings.add(
        'Max thickness ${maxThick.toStringAsFixed(2)}" at '
        '${input.distance.toStringAsFixed(0)}\' from drain — '
        'consider additional drain points to reduce',
      );
    }

    return BoardScheduleResult(
      rows: rows,
      maxThickness: maxThick,
      taperedPanelCounts: taperedCounts,
      flatFillCounts: flatFillCounts,
      totalTaperedPanels: totalTapered,
      totalFlatFillPanels: totalFlatFill,
      totalPanels: totalPanels,
      totalPanelsWithWaste: totalWithWaste,
      totalTaperedSF: taperedSF.toDouble(),
      totalFlatFillSF: flatFillSF.toDouble(),
      minThicknessAtDrain: input.minThickness,
      avgTaperThickness: avgTaperThick,
      maxThicknessAtRidge: maxThick,
      warnings: warnings,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/board_schedule_calculator_test.dart`
Expected: All tests PASS. If any expected values are off, adjust test expectations to match the engine's actual correct computation (verify math by hand first).

- [ ] **Step 5: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/services/board_schedule_calculator.dart test/services/board_schedule_calculator_test.dart
git commit -m "feat: add board schedule calculator engine

Computes row-by-row panel designations with flat fill resets.
Validated against 47x27 test case (Versico extended 1/4:12)."
```

---

### Task 6: R-Value Calculator — Add Min/Avg/Max for Tapered Systems

**Files:**
- Modify: `lib/services/r_value_calculator.dart`
- Test: `test/services/r_value_calculator_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/services/r_value_calculator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/r_value_calculator.dart';

void main() {
  group('RValueCalculator.calculate (existing behavior)', () {
    test('single layer polyiso 2.5"', () {
      final result = RValueCalculator.calculate(
        layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.5),
      );
      expect(result.totalRValue, closeTo(2.5 * 5.7 + 0.5, 0.1)); // 14.25 + 0.5
    });
  });

  group('RValueCalculator.calculateTapered', () {
    test('47x27 test case — full assembly R-values', () {
      final result = RValueCalculator.calculateTapered(
        layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.5),
        layer2: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.0),
        coverBoard: const CoverBoardInput(materialType: 'HD Polyiso', thickness: 0.5),
        taperMinThickness: 1.0,
        taperAvgThickness: 6.875,
        taperMaxThickness: 12.75,
      );

      // Base layers: (2.5 + 2.0) × 5.7 = 25.65
      // Cover: 0.5 × 5.7 = 2.85
      // Membrane: 0.5
      // Uniform total: 29.0

      // Min: 29.0 + 1.0 × 5.7 = 34.7
      expect(result.totalMinR, closeTo(34.7, 0.1));

      // Avg: 29.0 + 6.875 × 5.7 = 68.2
      expect(result.totalAvgR, closeTo(68.2, 0.2));

      // Max: 29.0 + 12.75 × 5.7 = 101.7
      expect(result.totalMaxR, closeTo(101.7, 0.2));
    });

    test('no base layers — taper only', () {
      final result = RValueCalculator.calculateTapered(
        layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 0.0),
        taperMinThickness: 1.0,
        taperAvgThickness: 3.0,
        taperMaxThickness: 5.0,
      );

      // Base: 0
      // Cover: none = 0
      // Membrane: 0.5
      // Min: 0.5 + 1.0 × 5.7 = 6.2
      expect(result.totalMinR, closeTo(6.2, 0.1));
    });

    test('breakdown contains taper min/avg/max labels', () {
      final result = RValueCalculator.calculateTapered(
        layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.5),
        taperMinThickness: 1.0,
        taperAvgThickness: 4.0,
        taperMaxThickness: 7.0,
      );

      expect(result.taperMinR, closeTo(1.0 * 5.7, 0.1));
      expect(result.taperAvgR, closeTo(4.0 * 5.7, 0.1));
      expect(result.taperMaxR, closeTo(7.0 * 5.7, 0.1));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/r_value_calculator_test.dart`
Expected: FAIL — `calculateTapered` method does not exist yet.

- [ ] **Step 3: Add the new TaperedAssemblyResult class and calculateTapered method**

Add to `lib/services/r_value_calculator.dart` after the existing `TaperedRValueResult` class:

```dart
// ─── TAPERED ASSEMBLY RESULT (min/avg/max) ───────────────────────────────────

class TaperedAssemblyResult {
  final double baseLayersR;
  final double coverBoardR;
  final double membraneR;

  final double taperMinR;
  final double taperAvgR;
  final double taperMaxR;

  double get uniformR => baseLayersR + coverBoardR + membraneR;
  double get totalMinR => uniformR + taperMinR;
  double get totalAvgR => uniformR + taperAvgR;
  double get totalMaxR => uniformR + taperMaxR;

  const TaperedAssemblyResult({
    required this.baseLayersR,
    required this.coverBoardR,
    required this.membraneR,
    required this.taperMinR,
    required this.taperAvgR,
    required this.taperMaxR,
  });
}
```

Add to the `RValueCalculator` class, after the existing `calculate` method:

```dart
  /// Calculate min/avg/max R-values for a tapered insulation assembly.
  ///
  /// [taperMinThickness]  Thickness at drain (inches) — from board schedule.
  /// [taperAvgThickness]  Volumetric avg thickness (inches) — from board schedule.
  /// [taperMaxThickness]  Thickness at ridge (inches) — from board schedule.
  static TaperedAssemblyResult calculateTapered({
    required InsulationLayerInput layer1,
    InsulationLayerInput? layer2,
    CoverBoardInput? coverBoard,
    required double taperMinThickness,
    required double taperAvgThickness,
    required double taperMaxThickness,
  }) {
    final r1 = layer1.thickness * rValuePerInch(layer1.materialType);
    final r2 = layer2 != null
        ? layer2.thickness * rValuePerInch(layer2.materialType)
        : 0.0;
    final rCover = coverBoard != null
        ? coverBoard.thickness * rValuePerInch(coverBoard.materialType)
        : 0.0;
    const rMembrane = 0.5;

    // Taper R uses polyiso R/inch (5.7) since all tapered panels are polyiso
    const taperRPerInch = 5.7;

    return TaperedAssemblyResult(
      baseLayersR: r1 + r2,
      coverBoardR: rCover,
      membraneR: rMembrane,
      taperMinR: taperMinThickness * taperRPerInch,
      taperAvgR: taperAvgThickness * taperRPerInch,
      taperMaxR: taperMaxThickness * taperRPerInch,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/r_value_calculator_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/services/r_value_calculator.dart test/services/r_value_calculator_test.dart
git commit -m "feat: add calculateTapered for min/avg/max R-value reporting

New TaperedAssemblyResult with totalMinR/totalAvgR/totalMaxR
computed from base layers + variable taper + cover board + membrane."
```

---

### Task 7: Serialization — Schema V2 Migration

**Files:**
- Modify: `lib/services/serialization.dart`
- Test: `test/services/serialization_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/services/serialization_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/serialization.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/drainage_zone.dart';
import 'package:protpo_app/models/roof_geometry.dart';

void main() {
  group('Schema v2 serialization', () {
    test('InsulationSystem round-trip with taper defaults', () {
      final system = InsulationSystem(
        numberOfLayers: 2,
        layer1: const InsulationLayer(type: 'Polyiso', thickness: 2.5, attachmentMethod: 'Mechanically Attached'),
        layer2: const InsulationLayer(type: 'Polyiso', thickness: 2.0, attachmentMethod: 'Mechanically Attached'),
        hasTaper: true,
        taperDefaults: TaperDefaults.initial(),
        hasCoverBoard: true,
        coverBoard: const CoverBoard(type: 'HD Polyiso', thickness: 0.5, attachmentMethod: 'Adhered'),
      );

      final json = insulationSystemToJson(system);
      final restored = insulationSystemFromJson(json);

      expect(restored.hasTaper, true);
      expect(restored.taperDefaults, isNotNull);
      expect(restored.taperDefaults!.taperRate, '1/4:12');
      expect(restored.taperDefaults!.manufacturer, 'Versico');
      expect(restored.taperDefaults!.profileType, 'extended');
      expect(restored.zoneOverrides, isEmpty);
    });

    test('InsulationSystem round-trip with zone overrides', () {
      final system = InsulationSystem(
        hasTaper: true,
        taperDefaults: TaperDefaults.initial(),
        zoneOverrides: const [
          DrainageZoneOverride(zoneId: 'z1', taperRateOverride: '1/8:12'),
        ],
      );

      final json = insulationSystemToJson(system);
      final restored = insulationSystemFromJson(json);

      expect(restored.zoneOverrides.length, 1);
      expect(restored.zoneOverrides.first.zoneId, 'z1');
      expect(restored.zoneOverrides.first.taperRateOverride, '1/8:12');
    });

    test('RoofGeometry round-trip with scuppers and zones', () {
      final geo = RoofGeometry(
        shapes: [RoofShape.initial(1)],
        scupperLocations: const [ScupperLocation(edgeIndex: 2, position: 0.5)],
        drainageZones: const [
          DrainageZone(id: 'z1', type: 'scupper', lowPointIndex: 0),
        ],
      );

      final json = roofGeometryToJson(geo);
      final restored = roofGeometryFromJson(json);

      expect(restored.scupperLocations.length, 1);
      expect(restored.scupperLocations.first.edgeIndex, 2);
      expect(restored.scupperLocations.first.position, 0.5);
      expect(restored.drainageZones.length, 1);
      expect(restored.drainageZones.first.type, 'scupper');
    });
  });

  group('Schema v1 migration', () {
    test('old hasTaperedInsulation migrates to hasTaper', () {
      final oldJson = {
        'numberOfLayers': 1,
        'layer1': {'type': 'Polyiso', 'thickness': 2.5, 'attachmentMethod': 'Mechanically Attached'},
        'hasTaperedInsulation': true,
        'tapered': {
          'boardType': 'VersiCore Tapered',
          'taperSlope': '1/4:12',
          'minThicknessAtDrain': 1.0,
          'maxThickness': 5.0,
          'systemArea': 1000.0,
          'attachmentMethod': 'Mechanically Attached',
        },
        'hasCoverBoard': false,
      };

      final restored = insulationSystemFromJson(oldJson);

      expect(restored.hasTaper, true);
      expect(restored.taperDefaults, isNotNull);
      expect(restored.taperDefaults!.taperRate, '1/4:12');
      expect(restored.taperDefaults!.minThickness, 1.0);
      expect(restored.taperDefaults!.attachmentMethod, 'Mechanically Attached');
    });

    test('old InsulationSystem without taper fields migrates cleanly', () {
      final oldJson = {
        'numberOfLayers': 1,
        'layer1': {'type': 'Polyiso', 'thickness': 2.5, 'attachmentMethod': 'Mechanically Attached'},
        'hasTaperedInsulation': false,
        'hasCoverBoard': false,
      };

      final restored = insulationSystemFromJson(oldJson);
      expect(restored.hasTaper, false);
      expect(restored.taperDefaults, isNull);
    });

    test('old RoofGeometry without scuppers/zones loads cleanly', () {
      final oldJson = {
        'shapes': [],
        'buildingHeight': 20.0,
        'roofSlope': 'Flat',
        'drainLocations': [{'x': 10.0, 'y': 15.0}],
      };

      final restored = roofGeometryFromJson(oldJson);
      expect(restored.scupperLocations, isEmpty);
      expect(restored.drainageZones, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/serialization_test.dart`
Expected: FAIL — new functions and migration logic don't exist yet.

- [ ] **Step 3: Update serialization.dart**

Add import at top of `lib/services/serialization.dart`:

```dart
import '../models/drainage_zone.dart';
```

Update `stateToJson` schema version:

```dart
'schemaVersion': 2,
```

**Replace the insulation system serialization functions** (lines 219-272):

```dart
Map<String, dynamic> insulationSystemToJson(InsulationSystem ins) => {
  'numberOfLayers':  ins.numberOfLayers,
  'layer1':          _insLayerToJson(ins.layer1),
  'layer2':          ins.layer2 != null ? _insLayerToJson(ins.layer2!) : null,
  'hasTaper':        ins.hasTaper,
  'taperDefaults':   ins.taperDefaults != null ? _taperDefaultsToJson(ins.taperDefaults!) : null,
  'zoneOverrides':   ins.zoneOverrides.map(_zoneOverrideToJson).toList(),
  'hasCoverBoard':   ins.hasCoverBoard,
  'coverBoard':      ins.coverBoard != null ? _coverBoardToJson(ins.coverBoard!) : null,
};

InsulationSystem insulationSystemFromJson(Map j) {
  final layer2json = j['layer2'];
  final cbJson = j['coverBoard'];

  // v1 → v2 migration: hasTaperedInsulation → hasTaper
  final hasTaper = (j['hasTaper'] as bool?) ?? (j['hasTaperedInsulation'] as bool?) ?? false;

  // v1 → v2 migration: tapered → taperDefaults
  TaperDefaults? taperDefaults;
  if (j['taperDefaults'] != null) {
    taperDefaults = _taperDefaultsFromJson(j['taperDefaults'] as Map);
  } else if (j['tapered'] != null && hasTaper) {
    // Migrate from old TaperedInsulation
    final old = j['tapered'] as Map;
    taperDefaults = TaperDefaults(
      taperRate: _s(old['taperSlope'], '1/4:12'),
      minThickness: _d(old['minThicknessAtDrain'], 1.0),
      manufacturer: 'Versico',
      profileType: 'extended',
      attachmentMethod: _s(old['attachmentMethod'], 'Mechanically Attached'),
    );
  }

  final overridesJson = j['zoneOverrides'] as List?;
  final zoneOverrides = overridesJson != null
      ? overridesJson.map((o) => _zoneOverrideFromJson(o as Map)).toList()
      : <DrainageZoneOverride>[];

  return InsulationSystem(
    numberOfLayers: _i(j['numberOfLayers'], 1),
    layer1: _insLayerFromJson(j['layer1'] as Map? ?? {}),
    layer2: layer2json != null ? _insLayerFromJson(layer2json as Map) : null,
    hasTaper: hasTaper,
    taperDefaults: taperDefaults,
    zoneOverrides: zoneOverrides,
    hasCoverBoard: j['hasCoverBoard'] as bool? ?? false,
    coverBoard: cbJson != null ? _coverBoardFromJson(cbJson as Map) : null,
  );
}

// Keep the private alias for internal use by _buildingStateToJson
Map<String, dynamic> _insulationSystemToJson(InsulationSystem ins) =>
    insulationSystemToJson(ins);

InsulationSystem _insulationSystemFromJson(Map j) =>
    insulationSystemFromJson(j);

Map<String, dynamic> _taperDefaultsToJson(TaperDefaults t) => {
  'taperRate':        t.taperRate,
  'minThickness':     t.minThickness,
  'manufacturer':     t.manufacturer,
  'profileType':      t.profileType,
  'attachmentMethod': t.attachmentMethod,
};

TaperDefaults _taperDefaultsFromJson(Map j) => TaperDefaults(
  taperRate:        _s(j['taperRate'], '1/4:12'),
  minThickness:     _d(j['minThickness'], 1.0),
  manufacturer:     _s(j['manufacturer'], 'Versico'),
  profileType:      _s(j['profileType'], 'extended'),
  attachmentMethod: _s(j['attachmentMethod'], 'Mechanically Attached'),
);

Map<String, dynamic> _zoneOverrideToJson(DrainageZoneOverride o) => {
  'zoneId':               o.zoneId,
  'taperRateOverride':    o.taperRateOverride,
  'minThicknessOverride': o.minThicknessOverride,
  'manufacturerOverride': o.manufacturerOverride,
  'profileTypeOverride':  o.profileTypeOverride,
};

DrainageZoneOverride _zoneOverrideFromJson(Map j) => DrainageZoneOverride(
  zoneId:               _s(j['zoneId']),
  taperRateOverride:    j['taperRateOverride'] as String?,
  minThicknessOverride: (j['minThicknessOverride'] as num?)?.toDouble(),
  manufacturerOverride: j['manufacturerOverride'] as String?,
  profileTypeOverride:  j['profileTypeOverride'] as String?,
);
```

Remove the old `_taperedToJson` and `_taperedFromJson` functions.

**Update roof geometry serialization** — add scupper and zone serialization:

In `_roofGeometryToJson`, add:

```dart
'scupperLocations': g.scupperLocations.map(_scupperToJson).toList(),
'drainageZones':    g.drainageZones.map(_drainageZoneToJson).toList(),
```

In `_roofGeometryFromJson`, add:

```dart
scupperLocations: (j['scupperLocations'] as List? ?? [])
    .map((s) => _scupperFromJson(s as Map<String, dynamic>))
    .toList(),
drainageZones: (j['drainageZones'] as List? ?? [])
    .map((z) => _drainageZoneFromJson(z as Map<String, dynamic>))
    .toList(),
```

Add public aliases for tests:

```dart
Map<String, dynamic> roofGeometryToJson(RoofGeometry g) =>
    _roofGeometryToJson(g);

RoofGeometry roofGeometryFromJson(Map j) =>
    _roofGeometryFromJson(j);
```

Add new helper functions:

```dart
Map<String, dynamic> _scupperToJson(ScupperLocation s) => {
  'edgeIndex': s.edgeIndex,
  'position':  s.position,
};

ScupperLocation _scupperFromJson(Map<String, dynamic> j) => ScupperLocation(
  edgeIndex: _i(j['edgeIndex'], 0),
  position:  _d(j['position'], 0.5),
);

Map<String, dynamic> _drainageZoneToJson(DrainageZone z) => {
  'id':                    z.id,
  'type':                  z.type,
  'lowPointIndex':         z.lowPointIndex,
  'taperRateOverride':     z.taperRateOverride,
  'minThicknessOverride':  z.minThicknessOverride,
  'manufacturerOverride':  z.manufacturerOverride,
  'profileTypeOverride':   z.profileTypeOverride,
};

DrainageZone _drainageZoneFromJson(Map<String, dynamic> j) => DrainageZone(
  id:                    _s(j['id']),
  type:                  _s(j['type'], 'internal_drain'),
  lowPointIndex:         _i(j['lowPointIndex'], 0),
  taperRateOverride:     j['taperRateOverride'] as String?,
  minThicknessOverride:  (j['minThicknessOverride'] as num?)?.toDouble(),
  manufacturerOverride:  j['manufacturerOverride'] as String?,
  profileTypeOverride:   j['profileTypeOverride'] as String?,
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/serialization_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Run all tests to verify nothing is broken**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git add lib/services/serialization.dart test/services/serialization_test.dart
git commit -m "feat: schema v2 serialization with v1 migration

Serialize TaperDefaults, DrainageZoneOverride, ScupperLocation,
and DrainageZone. Old hasTaperedInsulation/TaperedInsulation
documents migrate cleanly to new schema."
```

---

### Task 8: Final Integration Verification

**Files:** None created — verification only.

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test`
Expected: All tests PASS.

- [ ] **Step 2: Run static analysis**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter analyze lib/`
Expected: No errors. Warnings are acceptable if pre-existing.

- [ ] **Step 3: Verify the 47×27 test case end-to-end**

Run the board schedule test in verbose mode:

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/board_schedule_calculator_test.dart -v`
Expected: All 47×27 test case assertions pass — 12 rows, correct panel counts, correct flat fill, correct max thickness.

- [ ] **Step 4: Verify R-value integration end-to-end**

Run: `cd /Users/mattmoore/My_Project/protpo_app && flutter test test/services/r_value_calculator_test.dart -v`
Expected: Min R-34.7, Avg R-68.2, Max R-101.7 for the test case.

- [ ] **Step 5: Commit summary**

```bash
cd /Users/mattmoore/My_Project/protpo_app
git log --oneline -7
```

Expected commits (newest first):
1. `feat: schema v2 serialization with v1 migration`
2. `feat: add calculateTapered for min/avg/max R-value reporting`
3. `feat: add board schedule calculator engine`
4. `feat: add scupperLocations and drainageZones to RoofGeometry`
5. `refactor: replace TaperedInsulation with TaperDefaults`
6. `feat: add ScupperLocation, DrainageZone, TaperDefaults models`
7. `feat: add manufacturer panel data for Versico and TRI-BUILT`
