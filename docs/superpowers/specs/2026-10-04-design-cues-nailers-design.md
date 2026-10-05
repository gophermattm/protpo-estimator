# Design Cues, Headwalls, Edge Metal by Edge Type, Nailers, Nailbase

Date: 2026-10-04
Status: Approved design (chat, 2026-10-04); spec pending review

## Problem

A flat MA job on a metal deck with no walls (every edge Eave or Flat Drip Edge,
cover board off) produced a VersiWeld bonding adhesive line. VersiWeld is only
emitted for (a) a Fully Adhered field membrane or (b) parapet TPO area. The
exact trigger on the user's job could not be read back, but one confirmed path
matches: `_syncEdgeTypeTotals` (left_panel.dart) writes parapet LF from
Parapet edges only when > 0 and never clears it, so an edge changed from
Parapet back to Eave leaves stale parapet LF in the BOM. Several other design
inputs are either disconnected or ignore context:

- Headwall Height / Headwall LF inputs are not wired to the model or BOM.
- Cover board attachment defaults to Adhered regardless of membrane attachment.
- One edge metal type is applied to every roof edge; Hip/Valley/Ridge count as drip edge.
- No perimeter wood nailers, no nailbase.
- Adhesive auto-packages to 15-gal cylinders over 600 sf instead of pails.

## Goals

1. Project Geometry edge types are the source of truth for parapet, headwall, and edge LF.
2. Adhesive appears in the BOM only when a design input calls for it.
3. Headwalls produce the same flashing scope as parapets.
4. New design options: edge metal per edge type, perimeter wood nailers, nailbase cover board.

## Non-goals

- Per-edge nailer heights on tapered roofs (flat stack used; flagged Needs Validation).
- FM 1-49 wind-zone nailer fastener table (fixed default; flagged Needs Validation).
- Changing QXO pricing mappings beyond adding SKU keys for new lines.

## 1. Adhesive options

- `kAdhesiveTypes` becomes:
  - `VersiWeld TPO Bonding Adhesive — 5 Gal Pails` (default, `kAdhesiveVersiWeldPails`)
  - `CAV-GRIP 3V Spray`
- The auto 1-gal / 5-gal / 15-gal branch in `bom_calculator.dart` is removed. VersiWeld is
  always ordered in 5-gal pails at 60 sf/gal.
- Applies to field membrane (`MembraneSystem.adhesiveType`), parapet
  (`ParapetWalls.parapetAdhesiveType`), and headwall (shares the wall adhesive type, below).
- Serialization: legacy value `VersiWeld TPO Bonding Adhesive` (and any unknown value)
  deserializes to `kAdhesiveVersiWeldPails`.

## 2. Geometry as source of truth for LF

`_syncEdgeTypeTotals` changes:

- Always writes parapet LF, headwall LF, and each edge-metal LF, including 0.
- Parapet LF from edges == 0 → `setParapetEnabled(false)`; > 0 → enabled.
- Hip, Valley, Ridge no longer add to any edge-metal bucket.
- Buckets: Eave, Rake Edge, Flat Drip Edge (edge metal); Parapet (parapet LF);
  Headwall (headwall LF); Clerestory (wall flashing metal, as today).
- When any shape has edge lengths, the Parapet LF and Headwall LF fields render
  read-only with helper text "From Project Geometry". Manual entry remains when no shape
  edges exist.
- Termination bar LF override behavior unchanged (still defaults to parapet LF).

## 3. Headwalls

Model: `ParapetWalls` gains
- `headwallHeight` (inches, default 0)
- `headwallLF` (LF, default 0)

The existing parapet adhesive type is reused for headwalls (renamed in UI to
"Wall Flashing Adhesive"; field name `parapetAdhesiveType` kept for serialization
compatibility).

BOM: extract the parapet flashing block into a shared helper
`_wallFlashingItems(label, heightIn, lf, ...)` used for both Parapet and Headwall. For each
wall with height > 0 and LF > 0:

- TPO flashing area = (height/12 + 0.33) × LF, added to membrane/flashing area exactly as
  parapet area is today.
- Wall adhesive: same Versico short-wall rule as parapet (skip when height ≤ 12", or
  ≤ 18" with Termination Bar). VersiWeld pails or CAV-GRIP + UN-TACK per adhesive type.
  Line names suffixed `(Parapet)` / `(Headwall)`.
- Termination bar LF += headwall LF.
- MA/Rhinobond: RUSS strip and fasteners include headwall LF.

UI: Headwall Height input moves from Penetrations to the Parapet section (renamed
"Walls: Parapet & Headwall"), shown when headwall LF > 0. The dead `_cWallHeight` /
`_cWallLF` controllers in Penetrations are removed.

## 4. Smart attachment defaults

- `setCoverBoardEnabled(true)` sets cover board attachment from membrane field attachment:
  Fully Adhered → `Adhered`; Mechanically Attached / Rhinobond → `Mechanically Attached`.
  Nailbase → `Mechanically Attached` regardless.
- `CoverBoard` model default and serialization fallback become `Mechanically Attached`.
  Saved jobs that stored a value are unaffected; only missing values change.
- Validation warning (not error): layer 1 `Adhered` and deck `Metal` →
  "Adhered insulation directly to steel deck: verify the adhesive and assembly are approved
  for steel deck (FM/Versico)." [Inference: approval varies by assembly.]

## 5. Edge metal by edge type

`MetalScope` replaces `dripEdgeLF` + `edgeMetalType` with three buckets:

| Field | Type field | Default type |
|---|---|---|
| `eaveLF` | `eaveMetalType` | `TPO-Coated Drip Edge` |
| `rakeLF` | `rakeMetalType` | `TPO-Coated Drip Edge` |
| `flatDripLF` | `flatDripMetalType` | `TPO-Coated Drip Edge` |

- `dripEdgeLF` stays as a computed getter (sum of three) so overlayment-strip math and
  other readers keep working.
- BOM emits one line per non-zero bucket: `Eave Edge Metal — <type>`, etc., skuKey
  `metal_drip_edge` with `attributes: {edgeMetalType, edgeType}`.
- Serialization migration: legacy `dripEdgeLF` → `eaveLF`; legacy `edgeMetalType` → all three
  type fields. New jobs re-derive buckets from geometry on first sync.
- UI (Metal Scope): one row per bucket, type dropdown + LF (read-only when from geometry).

## 6. Perimeter wood nailers

Model: `MetalScope` gains `hasNailers` (default false), `nailerWidth` (`2x6` | `2x8` | `2x10`,
default `2x6`).

Derived:
- Nailer LF = eaveLF + rakeLF + flatDripLF.
- Nailer height (in) = flat stack = layer1 + layer2 + cover board thickness (no taper).
- Plies = ceil(height / 1.5), minimum 1.

BOM (category `Wood Nailers`):
- `Pressure-Treated Lumber <width> × 16'` (salt-based preservative): pieces =
  ceil(LF × plies × (1 + wMat) / 16). Note: "Salt-based preservative treatment only; creosote,
  penta, copper naphthenate damage membrane (Carlisle)."
- `Nailer Fasteners`: count = LF × 2 rows × (12 / 12" spacing) × plies, × (1 + wAcc),
  boxed per existing fastener pack logic. Fastener name follows deck type
  (`fastenerNamePublic`). Line note: **Needs Validation for nailer fastener spacing**
  (FM 1-49 Table 2.2.2.3.4-1 by wind zone).
- Warning when `hasTaper`: **Needs Validation for nailer height at tapered high edges**
  (flat stack used).

Sources: FM DS 1-49 (2x6 nominal minimum; two staggered rows on steel deck);
Carlisle SynTec "Wood Nailers for Roofing" (treatment, height flush with insulation);
Versico spec (nailer height matches insulation, required for metal edge securement).

UI: Metal Scope toggle "Perimeter Wood Nailers", width dropdown, read-only calc box
(LF, height, plies).

## 7. Nailbase cover board

- `kCoverBoardTypes` adds `Nailbase (Polyiso + 7/16" OSB)`.
- Thickness list when Nailbase selected: 1.5, 2.0, 2.5, 3.0, 3.5, 4.0 (total incl. OSB).
- R-value by lookup (Hunter H-Shield NB TDS, LTTR): 1.5→6.3, 2.0→9.2, 2.5→12.0,
  3.0→15.0, 3.5→18.0, 4.0→21.1. Implemented as a table in `r_value_calculator.dart`, not
  per-inch.
- BOM cover board line uses the existing cover board path (board count by area,
  4'×8' boards) with name `Nailbase (Polyiso + 7/16" OSB) <t>"`; fastener stack length
  includes nailbase thickness.

## Testing

TDD per section, tests in `test/services/` and `test/models/`:

1. Regression: MA, Metal deck, edges Eave + Flat Drip Edge only, cover board off →
   no `adhesive_*` SKU lines.
2. Stale parapet: sync with Parapet edge then switch to Eave → parapet LF 0, disabled,
   no parapet lines. (Extract sync totals into a pure function to make this unit-testable.)
3. Adhesive: FA 10,000 sf → VersiWeld 5-gal pails; legacy value deserializes to pails.
4. Headwall: 24" × 50 LF → flashing area, adhesive (Headwall), term bar, RUSS on MA;
   12" → adhesive omitted.
5. Cover board default follows membrane; validation warning on adhered-to-steel.
6. Edge metal: three lines with own types; Hip/Valley/Ridge excluded; legacy migration.
7. Nailers: 400 LF, 2.5" stack → 2 plies, pieces = ceil(400×2×1.10/16) = 55; fastener count;
   taper warning.
8. Nailbase R lookup and BOM line.

Then the full suite (`flutter test`) and `flutter analyze`. No commit, push, or deploy
unless requested.

## Needs Validation (carried into the app)

- Needs Validation for nailer fastener spacing (default 2 rows @ 12" o.c.).
- Needs Validation for nailer height at tapered high edges (flat stack used).
