# ProTPO Code Evaluation — 2026-09-05

> **Status (same day):** 15 of 16 findings fixed on branch `fix/eval-2026-09-05` (9 commits, TDD, one regression test per finding in `test/services/eval_fixes_test.dart` + `test/providers/labor_line_items_test.dart`). Suite 187 pass / 0 fail. `flutter build web` OK. Not merged, not deployed. **Open: F9** (BOM unit vs QXO UOM mismatch flag) — needs a sample of real QXO `uom` values to design the check. F2 table verified against two IECC 2021 renderings: Z1 20 / Z2–3 25 / Z4–5 30 / **Z6–8 35** (the report's [Unverified] guess had Z6 at 30 — corrected to 35).

Scope: full `lib/` (32.4k lines Dart, 46 files) at commit `4544c57`, plus the test suite. Focus per brief: functional correctness and calculation accuracy. Method: line-by-line read of every calculation engine (BOM, board schedule, R-value, wind zones, watershed, labor, pricing, export totals), cross-file tracing of provider wiring and serialization, and throwaway tests to confirm the two highest-impact claims.

Legend: **CONFIRMED** = reproduced by test or unambiguous code trace. **[Inference]** = follows from the code but not executed. **[Unverified]** = depends on a Versico/IECC/ASHRAE source not available in the repo.

---

## 1. Baseline

| Check | Result |
|---|---|
| `flutter analyze` | Analysis server crashed (exit 64). Not a code issue — Flutter 3.38.5 tool crash. Rerun after `flutter pub get`; if it persists, `flutter clean`. |
| `flutter test` | **146 pass, 7 fail.** See §4. Note: running `flutter analyze` and `flutter test` concurrently corrupted the build cache and produced bogus SDK compile errors (`Matrix4`, `FileSpan`). Run them sequentially. |
| Dead code | `lib/widgets/estimator_providers.dart` (799 lines) and `lib/models/estimator_providers.dart` (614 lines) are not imported anywhere. Only `lib/providers/estimator_providers.dart` is live. Delete the other two; they will drift and mislead. |
| Project CLAUDE.md | None exists. |

---

## 2. Findings — ranked by impact on the numbers

### F1. Tapered MA insulation with no drains placed orders ZERO insulation fasteners and plates — CONFIRMED
`lib/services/bom_calculator.dart:851` — `final taperMA = effectiveTaperMA && taperMaxIn > 0;`
When tapered insulation is Mechanically Attached and no board schedule exists (no drains placed yet), `taperMaxIn` is 0, so the tapered fastener block is skipped. Because `taperMAFlag` is true, Layer 1 and Layer 2 fastener blocks are also suppressed (line 702). Result: the BOM orders the tapered boards (172 boards in the repro) with no fasteners and no plates.
Repro: 100×50 rectangle, 0 flat layers, tapered enabled (defaults), no drains → tapered boards = 172, `fastener_insulation` lines = 0.
Fix: when `taperMaxIn == 0`, fall back to a placeholder fastener line sized from `taper.minThickness + estimated rise`, or emit a BLOCKER warning instead of silently omitting.

### F2. Three different "required R-value" tables in the app disagree with each other — CONFIRMED
| Source | Z1 | Z2 | Z3 | Z4 | Z5 | Z6 | Z7 | Z8 |
|---|---|---|---|---|---|---|---|---|
| `zip_lookup.dart:78` (what the app actually uses via ZIP) | 20 | 20 | 20 | 25 | 30 | 30 | 35 | 35 |
| `r_value_calculator.dart:352` (labeled "IECC 2021") | 15 | 20 | 20 | 25 | 25 | 25 | 30 | 35 |
| IECC 2021 C402.1.3 / ASHRAE 90.1-2019, insulation entirely above deck [Unverified — from memory, not source text] | 20 | 25 | 25 | 30 | 30 | 30 | 35 | 35 |

The ZIP-driven value is what lands in `ProjectInfo.requiredRValue` and drives the compliance chip. If my recollection of the code tables is right, Zones 2–4 are understated by R-5, so a Zone 4 assembly at R-26 shows "compliant" when code wants R-30. Pick one table, cite the edition in a comment, delete the other.

### F3. BOM's own R-value warning uses a separate, inconsistent engine — CONFIRMED
`lib/services/bom_calculator.dart:2789` `_estimateRValue` ignores tapered insulation entirely and omits the membrane R-0.5, and its per-inch values differ from `r_value_calculator.dart` (EPS 3.8 vs 4.0, Mineral Wool 4.2 vs 4.1, cover boards 4.0/in generic vs 0.9–1.0). Repro above shows `WARNING: Insulation R-value ~0.0 may not meet code requirement of R-25` on a tapered-only roof while the center panel shows a real R-value. This is the same class of bug fixed on Apr 8 (hardcoded 5.7). Delete `_estimateRValue` and pass the `RValueResult` into `BomCalculator.calculate`, or drop the warning from BOM.

### F4. Multi-shape roofs: perimeter, polygon, watershed and board schedule all use `shapes.first` only — CONFIRMED
- `lib/models/roof_geometry.dart:544` `totalPerimeter` returns the first shape's perimeter. Repro: 100×50 + 40×40 → area 6,600 sf (correct), perimeter 300 ft (should be 460).
- `lib/providers/estimator_providers.dart:228, 1372` watershed and board schedule build the polygon from `shapes.first` but pass `geo.totalArea` (all shapes) as the zone area.
- Wind-zone areas (left panel) derive from that perimeter.
Everything downstream of perimeter (perimeter-zone membrane, MA fastener zones, RUSS, edge metal defaults) is wrong on any 2+ shape roof. Either sum perimeters (approximation) or build a unioned polygon; at minimum warn the user that multi-shape is single-shape-approximated.

### F5. Wind-zone area math double-counts corners — CONFIRMED
`lib/widgets/left_panel.dart:468`
```
ca = corners × w²
pa = P × w − ca          // this is the whole edge band INCLUDING corners
fa = total − ca − pa     // corners subtracted twice
```
Correct: `pa = P×w − 2·corners·w²`, `fa = total − ca − pa`. Example 100×100, w=5: code gives perimeter 1,900 / field 8,000; correct is 1,800 / 8,100. Error is 4w² sf, so ~1–3% on typical roofs, always in the over-order direction for perimeter flashing rolls and fasteners.

### F6. Board schedule ignores `minThickness` at the drain — CONFIRMED
`lib/services/board_schedule_calculator.dart:154, 164` Row thin/thick edges are reported as `minThickness + distance×rate`, but every panel sequence in `board_schedules.dart` starts at 0.5" and flat fill is only added for cycle > 0. With the default `TaperDefaults.minThickness = 1.0` the schedule reports a 1.0" drain thickness but the boards ordered give 0.5"; no base flat fill is ever ordered to make up the difference. Fastener lengths (`maxThicknessAtRidge`) and R-values are computed from the reported (wrong) thickness. Either force `minThickness` to the sequence's first thin edge, or add a base flat-fill row of `(minThickness − sequence.first.thinEdge)` across the whole tapered area.

### F7. Flat-fill thicknesses exceed stock sizes on long runs — CONFIRMED (tests expect it)
Same file, line 164: flat fill = `cycleNumber × seqRise`, so cycle 2 on 1/4:12 extended = 8.0", cycle 3 = 12.0". `kFlatStockThicknesses` tops out at 4.0". The BOM then emits "Flat Fill Polyiso 8"" as a single board line. The existing test (`47×27` case) asserts `flatFillCounts[8.0]`, so this is currently by design — but no such board exists to order. Decompose into stock thicknesses (2 × 4.0") before emitting BOM lines.

### F8. QXO fuzzy pricing divides package count by pack size a second time — CONFIRMED
`lib/services/qxo_pricing_service.dart:108` Callers (`center_panel.dart:172`, `right_panel.dart:1633`) pass `bomQuantities[name] = item.orderQty` which is already the number of **boxes/rolls/buckets**. The service then does `orderQty = ceil(bomQty / packQty)`. A 3-box fastener need against a QXO item with `packQty = 500` becomes 1 box. Any unmapped line with `packQty > 1` is under-ordered and under-priced. The deterministic path (`line 650`) does not have this problem. Either pass raw unit counts (`trace.withWaste`) or skip pack adjustment when the BOM unit is already a package.

### F9. No unit reconciliation between BOM unit and QXO UOM — [Inference]
`qxo_pricing_service.dart:650` `totalCost = unitPrice × orderQty` where `orderQty` is BOM packages and `unitPrice` is whatever UOM QXO returns first (`priceMap.entries.first`). If QXO prices a fastener per EA and the BOM line is "boxes", the total is off by the pack size. The `uom` is captured but never compared to `BomLineItem.unit`. Add a mismatch flag in the priced-item UI.

### F10. PDF "TOTAL PROJECT VALUE" ignores edits, deletions and manual lines — CONFIRMED
`lib/services/export_service.dart:728` The summary box iterates `pricedItems.values` (original QXO results) while the table rows above it apply `bomEdits` (qty/price overrides), `bomDeletedItems`, and `bomManualItems`. The printed grand total therefore does not equal the sum of the printed line totals whenever the user edited anything. Sum the rendered rows instead.

### F11. Labor line items use the wrong rate keys — CONFIRMED
`lib/providers/estimator_providers.dart`
- 1201: Sealant Pockets billed at `Install Custom Curb (exhaust fan)` rate ($75) — a `Install Sealant Pockets` key exists.
- 1231: Wall Flashing billed at `Install Drip Edge and Tape` rate — `Install Wall Flashing` key exists.
- 1238: Gutter billed at `Install Cap Metal (per foot)` rate — `Install Gutter` key exists.
Crew-specific overrides for those three keys are silently ignored. Also line 1120: `Install ISO Board (Layer 1)` labor is emitted whenever `layer1.thickness > 0`, which is true by default even when `numberOfLayers == 0` (tapered-only job) → phantom labor line.

### F12. Validation engine has permanently-firing "missing item" penalties — CONFIRMED
`lib/services/validation_engine.dart`
- 280: "Stainless Steel Clamping Rings" is flagged missing whenever pipes > 0. The BOM never emits an item containing "clamp"; pre-molded boots include rings (the rule's own text says so). Always −10 health points.
- 321 (and two similar checks): primer detection is `name.contains('tpo primer')`. Selecting `CAV-PRIME Spray` produces "Versico CAV-PRIME Low-VOC Primer", which does not match → three critical "TPO Primer missing" items fire (−30 points) even though primer is on the BOM.
- Scupper EPDM flashing is always flagged (never satisfiable, −3).
- Line 238: validation says RUSS fasteners need 6" o.c. for >20-yr warranty or ≥90 mph, but `bom_calculator.dart:2242` always uses 12" o.c. The BOM under-orders RUSS fasteners and plates by 50% in exactly the cases the validator calls out.

### F13. Edge types are not saved — CONFIRMED
`lib/services/serialization.dart:180` `_roofShapeToJson` writes `edgeLengths` but not `edgeTypes`, and `_roofShapeFromJson` never reads them. After save/reload every edge reverts to the `'Eave'` fallback. Anything derived from edge types (wall-flashing vs drip-edge LF auto-bucketing, renderer colors, PDF diagram labels) is lost on reload. Add both sides.

### F14. Estimate `totalValue` is always saved as 0 — CONFIRMED
`lib/screens/estimator_screen.dart:107` The job/estimate list therefore never shows a dollar value. Compute from priced items + labor at save time, or drop the field from the UI until it is real.

### F15. Board-schedule waste hardcoded at 10% in multi-zone aggregation — CONFIRMED (minor)
`lib/providers/estimator_providers.dart:1482` `totalPanelsWithWaste = totalPanels × 1.10` regardless of `ProjectInfo.wasteMaterial`. The BOM re-applies the real waste to the raw counts, so the PDF board-schedule page and the BOM disagree whenever waste ≠ 10%.

### F16. Seam length estimated two different ways — [Inference]
`bom_calculator.dart:1270` cut-edge sealant uses `(rolls − 1) × 100'`; line 2122 membrane cleaner uses `area ÷ roll width`. Same physical quantity, two formulas, small divergence. Pick one helper.

---

## 3. Items checked and found sound

- Membrane roll math (field 10'/12' × 100', flashing 6' × 100' = 600 sf), parapet strip width (height + 4" lap), waste and ceiling-per-package convention: correct throughout.
- MA / Rhinobond density tables, wind-speed tier bump, warranty defaults: internally consistent. Actual densities are [Unverified] against current Versico tables — the code comments say the same.
- Fastener length selection (stack + deck + embedment → next catalog length, "verify" flag past catalog): correct; Wood deck adds 0.75" deck thickness properly.
- `_consolidate` (sum raw units, ceil once per SKU): correct and matches the Apr 8 intent.
- Aggregate multi-building BOM (sum `withWaste`, ceil once): correct.
- Shoelace area with turn templates for Rectangle/L/T/U: correct for closed polygons. There is no closure check, so a non-closing L-shape silently yields a wrong area — worth a validation warning.
- Watershed grid sampling + vertex sampling, per-zone effective width: reasonable; per-zone max distance is Euclidean to the farthest zone point, which is conservative (longer run → thicker ridge) for two-way taper layouts [Inference].
- Zone-width lookup table structure and warranty index: consistent. Values are [Unverified].
- Margin math `sell = cost / (1 − margin)`: correct for gross-margin semantics.
- Serialization: all other fields round-trip, with v1 → v2 migration for taper and edge-metal keys.
- Firestore rules: open read/write with size caps, no auth. Documented as intentional TODO. Anyone with the project ID can delete every job. Not a calc issue but should be on the roadmap before customer data grows.

---

## 4. Test suite

| Failure | Cause | Action |
|---|---|---|
| `test/widget_test.dart` | Flutter template test references `MyApp`; app class is `ProTPOApp`. | Delete the file or rewrite as a smoke test. |
| 6 × `board_schedule_calculator_test.dart` "47×27" | Tests assert per-row ceiling (28/56/140/154/1344/896). Code now ceils once per letter (27/54/138/152/1296/864) since the Apr 8 over-count fix. | Update expectations to the per-letter values; the code is the intended behaviour. |

Coverage gaps worth closing with the fixes above: no test for tapered-MA-without-drains fastener emission (F1), no multi-shape geometry test (F4), no wind-zone area test (F5), no serialization test that asserts `edgeTypes` round-trip (F13), no labor rate-key test (F11), no QXO pack-adjust test (F8).

---

## 5. Recommended fix order

1. F1, F8 — silent under-orders on material and pricing.
2. F2, F3 — pick one R-value requirement table and one R-value engine.
3. F4, F5 — geometry; F4 needs a design decision (sum vs union).
4. F6, F7 — board schedule base fill and stock decomposition.
5. F10, F11, F14 — money totals and labor.
6. F12, F13, F15, F16 — validation noise, save fidelity, consistency.
7. Delete the two dead `estimator_providers.dart` copies; fix the 7 tests; add the six coverage tests listed in §4.
