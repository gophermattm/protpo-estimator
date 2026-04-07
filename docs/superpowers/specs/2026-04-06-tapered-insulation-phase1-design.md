# Phase 1: Tapered Insulation — Data Model & Board Schedule Engine

**Date:** 2026-04-06
**Status:** Approved
**Project:** ProTPO (Flutter/Firebase)

---

## Overview

Add a tapered polyiso insulation design engine to ProTPO that computes board schedules, material quantities, and R-values from drain/scupper placement on the roof diagram. Phase 1 covers the data model, board schedule calculation engine, manufacturer panel data, and R-value integration. Diagram rendering and full UI are later phases.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Where do drainage zones live? | RoofGeometry (spatial data) + InsulationSystem (taper config) | Zones are geometric; insulation config stays with insulation |
| Zone computation model | Auto-computed from drain/scupper placement + per-zone overrides | Simple by default (80% of jobs), flexible when needed |
| Drain/scupper support | Both independently or together; scuppers get positioned on edges | Real commercial roofs have any combination |
| Manufacturer data storage | Hardcoded Dart constants (Versico + TRI-BUILT) | YAGNI — covers current need, Firestore layer can be added later |
| R-value reporting | Min / Average / Max from full assembly stack | Supports IECC compliance checks by multiple code editions |
| Thickness warnings | Informational only, never blocking | User decides whether to add drain points |

---

## Data Model Changes

### New: ScupperLocation

```dart
class ScupperLocation {
  final int edgeIndex;     // which edge of the roof polygon (0-based)
  final double position;   // 0.0–1.0 along that edge (0.5 = centered)
}
```

A scupper is a low point on a roof edge. `edgeIndex` ties it to the polygon edge from `RoofShape.edgeLengths`. The world-space (x, y) coordinates are computed from the edge geometry and position fraction.

### New: DrainageZone

```dart
class DrainageZone {
  final String id;                     // UUID
  final String type;                   // 'internal_drain' | 'scupper'
  final int lowPointIndex;             // index into drainLocations or scupperLocations

  // Per-zone overrides (null = inherit from TaperDefaults)
  final String? taperRateOverride;
  final double? minThicknessOverride;
  final String? manufacturerOverride;  // 'Versico' | 'TRI-BUILT'
  final String? profileTypeOverride;   // 'standard' | 'extended'
}
```

Zones are auto-computed when drains/scuppers are placed. Each zone defaults to the global `TaperDefaults` but can be individually overridden for mixed-drainage jobs.

### New: TaperDefaults

Replaces the existing `TaperedInsulation` class.

```dart
class TaperDefaults {
  final String taperRate;          // '1/8:12', '3/16:12', '1/4:12', '3/8:12', '1/2:12'
  final double minThickness;       // at drain/scupper, inches (default 1.0)
  final String manufacturer;       // 'Versico' | 'TRI-BUILT'
  final String profileType;        // 'standard' | 'extended'
  final String attachmentMethod;   // 'Mechanically Attached' | 'Adhered'
}
```

### Modified: RoofGeometry

Add scupper locations and drainage zones alongside existing drain locations.

```dart
class RoofGeometry {
  // Existing (unchanged):
  final List<RoofShape> shapes;
  final double buildingHeight;
  final String roofSlope;
  final double customSlope;
  final List<DrainLocation> drainLocations;
  final double? totalPerimeterOverride;
  final double? totalAreaOverride;
  final int perimeterCorners;
  final int insideCorners;
  final int outsideCorners;
  final WindZones windZones;

  // New:
  final List<ScupperLocation> scupperLocations;
  final List<DrainageZone> drainageZones;
}
```

### Modified: InsulationSystem

Replace `hasTaperedInsulation` + `TaperedInsulation` with `TaperDefaults` and per-zone overrides.

```dart
class InsulationSystem {
  // Existing (unchanged):
  final int numberOfLayers;
  final InsulationLayer layer1;
  final InsulationLayer? layer2;
  final bool hasCoverBoard;
  final CoverBoard? coverBoard;

  // Replaced:
  // final bool hasTaperedInsulation;       // REMOVED
  // final TaperedInsulation? tapered;      // REMOVED

  // New:
  final bool hasTaper;                      // replaces hasTaperedInsulation
  final TaperDefaults? taperDefaults;       // replaces TaperedInsulation
  final List<DrainageZoneOverride> zoneOverrides;  // per-zone config when different from defaults
}
```

### Removed: TaperedInsulation

The existing `TaperedInsulation` class (insulation_system.dart lines 88-154) is replaced by `TaperDefaults` + `DrainageZone`. Fields that moved:

| Old field | New location |
|---|---|
| `boardType` (free text) | Removed — engine auto-determines from manufacturer + taper rate |
| `taperSlope` | `TaperDefaults.taperRate` |
| `minThicknessAtDrain` | `TaperDefaults.minThickness` |
| `maxThickness` | Auto-calculated by engine (distance × taper rate + min) |
| `systemArea` | Auto-calculated from drainage zone geometry |
| `attachmentMethod` | `TaperDefaults.attachmentMethod` |

---

## Board Schedule Engine

### Location

New file: `lib/services/board_schedule_calculator.dart`

### Input

```dart
BoardScheduleInput {
  double distance;           // feet from low point to high point
  String taperRate;          // '1/4:12' etc.
  double minThickness;       // inches at drain/scupper
  String manufacturer;       // 'Versico' | 'TRI-BUILT'
  String profileType;        // 'standard' | 'extended'
  double panelWidth;         // 4.0 ft (standard)
}
```

### Algorithm

```
FOR each row (i = 0 to ceil(distance / panelWidth) - 1):
  rowStart = i × panelWidth
  rowEnd   = min((i+1) × panelWidth, distance)
  rowWidth = rowEnd - rowStart

  thinEdge  = minThickness + (rowStart × taperRateDecimal)
  thickEdge = minThickness + (rowEnd × taperRateDecimal)

  // Determine panel from manufacturer's sequence
  panelSequence = lookupSequence(manufacturer, taperRate, profileType)
  sequenceIndex = i % panelSequence.length

  // If we've cycled past the sequence, flat fill is needed
  cycleNumber = i ~/ panelSequence.length
  IF cycleNumber > 0:
    flatFillThickness = computeFlatFill(cycleNumber, panelSequence, taperRateDecimal)
  ELSE:
    flatFillThickness = 0.0

  panel = panelSequence[sequenceIndex]

  YIELD BoardRow(
    row: i + 1,
    distance: (rowStart, rowEnd),
    thinEdge: thinEdge,
    thickEdge: thickEdge,
    flatFillThickness: flatFillThickness,
    panelDesignation: panel.letter,
    panelThinEdge: panel.thinEdge,
    panelThickEdge: panel.thickEdge,
  )
```

### Output

```dart
BoardScheduleResult {
  List<BoardRow> rows;
  double maxThickness;           // at farthest point

  // Aggregated totals
  Map<String, int> taperedPanelCounts;    // {'X': 14, 'Y': 21, ...}
  Map<double, int> flatFillCounts;        // {1.0: 28, 2.0: 28, ...}
  int totalTaperedPanels;
  int totalFlatFillPanels;
  int totalPanels;                        // before waste
  int totalPanelsWithWaste;               // after 10% waste
  double totalTaperedSF;
  double totalFlatFillSF;

  // R-value data
  double minThicknessAtDrain;
  double avgTaperThickness;               // volumetric average
  double maxThicknessAtRidge;

  // Warnings (informational only)
  List<String> warnings;                  // e.g., "Max thickness 12.75\" — consider additional drain points"
}
```

### Flat Fill Reset Logic

Tapered panels max out at 4.5" thick. When the required thickness exceeds what the panel sequence can provide, the system "resets" by adding flat stock underneath:

1. Calculate which cycle of the panel sequence we're in: `cycleNumber = rowIndex ~/ sequenceLength`
2. Each cycle after the first requires flat fill. The fill thickness equals the total rise of one full panel sequence multiplied by the cycle number minus one: `flatFill = (cycleNumber) × sequenceRise`. For Versico extended 1/4" (X/Y/Z/ZZ), sequenceRise = 4.0" (from 0.5" to 4.5"). For Versico standard 1/4" (X/Y), sequenceRise = 2.0" (from 0.5" to 2.5").
3. Round flat fill down to the nearest available stock increment (0.5" steps): `flatFill = floor(flatFill / 0.5) × 0.5`

Example for Versico extended 1/4":12 (X/Y/Z/ZZ sequence, 4-panel repeat):
- Cycle 1 (rows 1-4): No flat fill. Panels X→Y→Z→ZZ cover 0.5" to 4.5"
- Cycle 2 (rows 5-8): 1.0" flat fill under each panel. Sequence restarts X→Y→Z→ZZ
- Cycle 3 (rows 9-12): 2.0" flat fill. Sequence restarts X→Y→Z→ZZ

For Versico standard 1/4":12 (X/Y only, 2-panel repeat):
- Cycle 1 (rows 1-2): No flat fill. X→Y cover 0.5" to 2.5"
- Cycle 2 (rows 3-4): Flat fill needed. X→Y restart
- Resets happen twice as often as extended — more flat fill, more labor

For TRI-BUILT 1/4":12 (X/Y only, 2-panel repeat):
- Same as Versico standard — TRI-BUILT doesn't offer extended profiles at 1/4"

---

## Manufacturer Panel Data

### Location

New file: `lib/data/board_schedules.dart`

### Data Structure

```dart
class TaperedPanel {
  final String letter;        // 'X', 'Y', 'Z', 'ZZ', 'AA', 'A', etc.
  final double thinEdge;      // inches
  final double thickEdge;     // inches
  final double avgThickness;  // inches
  final double avgLTTR;       // R-value (from manufacturer data)
}

class PanelSequence {
  final String manufacturer;
  final String taperRate;
  final String profileType;   // 'standard' | 'extended'
  final List<TaperedPanel> panels;
}
```

### Versico VersiCore Tapered Polyiso

Source: `data/Versico Tapered Polyiso.json` (existing in project)

**1/8":12 Standard** (4-panel repeat): AA → A → B → C
**1/8":12 Extended** (8-panel repeat): AA → A → B → C → D → E → F → FF

**1/4":12 Standard** (2-panel repeat): X → Y
**1/4":12 Extended** (4-panel repeat): X → Y → Z → ZZ

**1/2":12**: Q (1-panel, then flat fill)

**3/8":12**: SS → TT (2-panel repeat) [from industry research — verify against Versico catalog]

| Rate | Profile | Panels | Thin→Thick per panel |
|---|---|---|---|
| 1/8" | std | AA(0.5→1.0), A(1.0→1.5), B(1.5→2.0), C(2.0→2.5) | +0.5" per panel |
| 1/8" | ext | AA→A→B→C→D(2.5→3.0)→E(3.0→3.5)→F(3.5→4.0)→FF(4.0→4.5) | +0.5" per panel |
| 1/4" | std | X(0.5→1.5), Y(1.5→2.5) | +1.0" per panel |
| 1/4" | ext | X(0.5→1.5), Y(1.5→2.5), Z(2.5→3.5), ZZ(3.5→4.5) | +1.0" per panel |
| 1/2" | std | Q(0.5→2.5) | +2.0" per panel |

### TRI-BUILT ISO II GRF

Source: `data/TRI_BUILT ISO II GRF ROOF INSULATION.json` (existing in project)

| Rate | Panels | Notes |
|---|---|---|
| 1/8" | AA(0.5→1.0), A(1.0→1.5), B(1.5→2.0), C(2.0→2.5) | Same as Versico standard |
| 1/4" | X(0.5→1.5), Y(1.5→2.5) | No extended profile available |
| 1/2" | Q(0.5→2.5) | Same as Versico |

TRI-BUILT does not offer:
- Extended profiles (no Z, ZZ, D, E, F, FF)
- 3/16" or 3/8" taper rates

The engine must restrict profile type options based on selected manufacturer.

### Flat Stock Thicknesses

Available for flat fill (both manufacturers): 0.5", 1.0", 1.5", 2.0", 2.5", 3.0", 3.5", 4.0"

---

## R-Value Integration

### Location

Modified file: `lib/services/r_value_calculator.dart`

### Changes

The existing calculator computes a single R-value from the insulation stack. The new calculator produces three values.

**Uniform components (unchanged calculation):**
- Base Layer 1: `thickness × R_per_inch`
- Base Layer 2: `thickness × R_per_inch` (if present)
- Cover Board: `thickness × R_per_inch` (if present)
- Membrane: fixed R-0.5

**Variable component (new — from board schedule engine):**
- Taper at drain (min): `minThickness × R_per_inch` (flat fill = 0 at drain)
- Taper average: `avgTaperThickness × R_per_inch` (volumetric average across all rows)
- Taper at ridge (max): `maxThickness × R_per_inch`

**Output:**

```dart
class TaperedRValueResult {
  // Uniform components
  final double baseLayersR;       // layer1 + layer2
  final double coverBoardR;
  final double membraneR;

  // Variable component (three values)
  final double taperMinR;         // at drain — taper panel only, no flat fill
  final double taperAvgR;         // volumetric average of taper + flat fill
  final double taperMaxR;         // at ridge — tallest taper + flat fill stack

  // Totals
  double get totalMinR => baseLayersR + taperMinR + coverBoardR + membraneR;
  double get totalAvgR => baseLayersR + taperAvgR + coverBoardR + membraneR;
  double get totalMaxR => baseLayersR + taperMaxR + coverBoardR + membraneR;

  // IECC compliance (informational)
  final Map<String, bool> codeCompliance;  // {'IECC 2021': true, 'IECC 2024': true}
}
```

### R-Value Constants

From manufacturer data and existing calculator:
- Polyiso: 5.7 R/inch (LTTR, conservative)
- EPS: 4.0 R/inch
- XPS: 5.0 R/inch
- HD Polyiso: 5.7 R/inch
- Gypsum: 0.9 R/inch
- DensDeck: 1.0 R/inch
- Membrane: 0.5 (fixed)

TRI-BUILT tapered panels list 4.3 LTTR for the thinnest panels and up to 5.7 for thicker — the engine uses 5.7 for consistency with existing calculator behavior. [Inference: manufacturer LTTR values vary by thickness; 5.7 is the standard industry figure used in estimation.]

---

## Serialization Changes

### RoofGeometry additions

```json
{
  "scupperLocations": [
    {"edgeIndex": 2, "position": 0.5}
  ],
  "drainageZones": [
    {
      "id": "uuid",
      "type": "scupper",
      "lowPointIndex": 0,
      "taperRateOverride": null,
      "minThicknessOverride": null,
      "manufacturerOverride": null,
      "profileTypeOverride": null
    }
  ]
}
```

### InsulationSystem changes

```json
{
  "numberOfLayers": 2,
  "layer1": {"type": "Polyiso", "thickness": 2.5, "attachmentMethod": "Mechanically Attached"},
  "layer2": {"type": "Polyiso", "thickness": 2.0, "attachmentMethod": "Mechanically Attached"},
  "hasTaper": true,
  "taperDefaults": {
    "taperRate": "1/4:12",
    "minThickness": 1.0,
    "manufacturer": "Versico",
    "profileType": "extended",
    "attachmentMethod": "Mechanically Attached"
  },
  "zoneOverrides": [],
  "hasCoverBoard": true,
  "coverBoard": {"type": "HD Polyiso", "thickness": 0.5, "attachmentMethod": "Adhered"}
}
```

### Schema version

Increment `schemaVersion` from 1 to 2. Add migration logic for existing saved projects:
- `hasTaperedInsulation` → `hasTaper`
- `TaperedInsulation` fields map to `TaperDefaults` where possible
- Missing fields get sensible defaults

---

## Validation Test Case

**Input:** 47' × 27' building, 3.5' parapets, scupper centered on 27' back wall, 1/4":12, 1.0" min, Versico extended, 2.5" + 2.0" base polyiso, 0.5" HD polyiso cover board.

**Expected output:**
- 12 rows, X→Y→Z→ZZ sequence repeating with flat fill resets
- Max thickness at front wall: 12.75"
- 84 tapered panels + 63 flat fill panels = 147 total (162 with 10% waste)
- Panel totals: X=14, Y=21, Z=21, ZZ=28
- Flat fill totals: 0.5"=7, 1.0"=28, 2.0"=28
- R-value: min R-34.7, avg R-68.2, max R-101.7
- Warning: "Max thickness 12.75\" at front wall — consider additional drain points to reduce"

---

## Files Created/Modified

| File | Action | Description |
|---|---|---|
| `lib/data/board_schedules.dart` | **New** | Manufacturer panel data (Versico + TRI-BUILT) |
| `lib/models/drainage_zone.dart` | **New** | ScupperLocation, DrainageZone, TaperDefaults, DrainageZoneOverride |
| `lib/services/board_schedule_calculator.dart` | **New** | Board schedule computation engine |
| `lib/models/insulation_system.dart` | **Modified** | Remove TaperedInsulation, add hasTaper + TaperDefaults + zoneOverrides |
| `lib/models/roof_geometry.dart` | **Modified** | Add scupperLocations, drainageZones |
| `lib/services/r_value_calculator.dart` | **Modified** | Add min/avg/max R-value output for tapered systems |
| `lib/services/serialization.dart` | **Modified** | Serialize new models, schema version 2 migration |

## Out of Scope (Later Phases)

- Watershed geometry engine (zone boundary computation from drain/scupper positions)
- Left panel UI for drainage configuration and per-zone overrides
- Interactive scupper placement on diagram edges
- Diagram rendering (flow arrows, gradient, ridge/valley lines, crickets, sumps)
- Cricket auto-generation and sizing
- BOM integration with QXO pricing for tapered boards
