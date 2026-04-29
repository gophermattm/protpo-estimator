/// Registry of every BOM `skuKey` the calculator can emit.
///
/// The admin page reads this list to show ALL known SKUs (mapped or not),
/// not just the ones that already exist in Firestore.
///
/// Adding a new skuKey to `BomCalculator`?  Add a matching entry here so it
/// appears in the admin UI.
library;

import '../services/bom_calculator.dart';

class SkuRegistryEntry {
  /// Stable identifier emitted by the BOM (snake_case).
  final String skuKey;

  /// Human-readable label shown in admin UI.
  final String displayName;

  /// Which BOM category this maps to (matches BomLineItem.category).
  final String category;

  /// Attribute keys that discriminate variants (e.g. ['thickness', 'color']).
  /// Each unique combination of these attribute values becomes one row in
  /// the admin page for this skuKey.
  final List<String> variantAttributes;

  /// Optional notes shown to the operator (where to find the SKU, etc.).
  final String? notes;

  /// Pre-defined variant combinations the BOM commonly emits. Admin shows
  /// one row per known variant pre-populated with these attribute values
  /// — operator just clicks "Map" and picks the QXO SKU. Custom variants
  /// can still be added on top.
  final List<Map<String, dynamic>> knownVariants;

  const SkuRegistryEntry({
    required this.skuKey,
    required this.displayName,
    required this.category,
    this.variantAttributes = const [],
    this.notes,
    this.knownVariants = const [],
  });
}

/// Generates `(deckType × length)` combinations for fastener skuKeys. The
/// fastener name is derived from the deck so the operator never has to type
/// it: "Versico HPV" for wood, "HPVX" for metal/gypsum/tectum, etc.
List<Map<String, dynamic>> _fastenerVariants() {
  final out = <Map<String, dynamic>>[];
  for (final deck in BomCalculator.kFastenerDeckTypes) {
    final name = BomCalculator.fastenerNamePublic(deck);
    for (final length in BomCalculator.fastenerLengthLabels(deck)) {
      out.add({
        'fastenerName': name,
        'length':       length,
        'deckType':     deck,
      });
    }
  }
  return out;
}

/// Master list. Order here drives display order in the admin UI.
final List<SkuRegistryEntry> kSkuRegistry = [
  // ─── MEMBRANE ─────────────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'tpo_membrane_field',
    displayName: 'TPO Membrane — Field Roll',
    category: 'Membrane',
    variantAttributes: ['membraneType', 'thickness', 'color', 'rollWidth'],
  ),
  SkuRegistryEntry(
    skuKey: 'tpo_membrane_flashing',
    displayName: 'TPO Membrane — Flashing Roll (6\')',
    category: 'Membrane',
    variantAttributes: ['membraneType', 'thickness', 'color', 'rollWidth'],
  ),
  SkuRegistryEntry(
    skuKey: 'tpo_rtu_curb_flashing',
    displayName: 'TPO Curb Flashing — RTU',
    category: 'Details & Accessories',
    variantAttributes: ['membraneType', 'thickness', 'color'],
  ),
  SkuRegistryEntry(
    skuKey: 'tpo_overlayment_strip_6in',
    displayName: 'TPO Reinforced Overlayment Strip (6")',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'tpo_walkway_pads',
    displayName: 'TPO Walkway Pads (Heat Weldable)',
    category: 'Details & Accessories',
  ),

  // ─── INSULATION ───────────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'iso_polyiso_flat',
    displayName: 'Polyiso — Flat Layer',
    category: 'Insulation',
    variantAttributes: ['type', 'thicknessIn', 'boardSize'],
  ),
  SkuRegistryEntry(
    skuKey: 'iso_polyiso_tapered_panel',
    displayName: 'Tapered Polyiso — Panel',
    category: 'Insulation',
    variantAttributes: ['manufacturer', 'taperRate', 'profileType', 'panelLetter'],
    notes: 'One row per panel letter (A, B, C, …) per taper rate / manufacturer.',
  ),
  SkuRegistryEntry(
    skuKey: 'iso_polyiso_flat_fill',
    displayName: 'Flat Fill Polyiso (4×4)',
    category: 'Insulation',
    variantAttributes: ['manufacturer', 'thicknessIn', 'boardSize'],
  ),
  SkuRegistryEntry(
    skuKey: 'iso_coverboard',
    displayName: 'Cover Board',
    category: 'Insulation',
    variantAttributes: ['type', 'thicknessIn', 'boardSize'],
  ),

  // ─── FASTENERS ────────────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'fastener_membrane',
    displayName: 'Fastener — MA Membrane',
    category: 'Fasteners & Plates',
    variantAttributes: ['fastenerName', 'length', 'deckType'],
    notes: 'Each (deck type × length) combination is a separate QXO SKU.',
    knownVariants: _fastenerVariants(),
  ),
  SkuRegistryEntry(
    skuKey: 'fastener_insulation',
    displayName: 'Fastener — Insulation',
    category: 'Fasteners & Plates',
    variantAttributes: ['fastenerName', 'length', 'deckType'],
    notes: 'Each (deck type × length) combination is a separate QXO SKU. '
        'Same fastener line is used for L1, L2, taper, and cover board.',
    knownVariants: _fastenerVariants(),
  ),
  SkuRegistryEntry(
    skuKey: 'fastener_rhinobond',
    displayName: 'Fastener — Rhinobond',
    category: 'Fasteners & Plates',
    variantAttributes: ['fastenerName', 'length', 'deckType'],
    notes: 'Each (deck type × length) combination is a separate QXO SKU.',
    knownVariants: _fastenerVariants(),
  ),
  SkuRegistryEntry(
    skuKey: 'fastener_edge_metal',
    displayName: 'Fastener — Edge Metal',
    category: 'Parapet & Termination',
    variantAttributes: ['fastenerName', 'length', 'deckType'],
    notes: 'Each (deck type × length) combination is a separate QXO SKU.',
    knownVariants: _fastenerVariants(),
  ),
  SkuRegistryEntry(
    skuKey: 'fastener_russ_strip',
    displayName: 'Fastener — RUSS Strip',
    category: 'Parapet & Termination',
    variantAttributes: ['fastenerName', 'length', 'deckType'],
    notes: 'Each (deck type × length) combination is a separate QXO SKU.',
    knownVariants: _fastenerVariants(),
  ),
  SkuRegistryEntry(
    skuKey: 'fastener_termbar_masonry',
    displayName: 'Masonry Anchors — Termination Bar',
    category: 'Parapet & Termination',
    variantAttributes: ['wallType', 'length'],
  ),
  SkuRegistryEntry(
    skuKey: 'fastener_termbar_wood',
    displayName: 'Wood Screws — Termination Bar',
    category: 'Parapet & Termination',
    variantAttributes: ['wallType', 'length'],
  ),
  SkuRegistryEntry(
    skuKey: 'fastener_termbar_tek',
    displayName: 'TEK Screws — Termination Bar',
    category: 'Parapet & Termination',
    variantAttributes: ['wallType', 'length'],
  ),

  // ─── PLATES ───────────────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'plate_3in_insulation',
    displayName: '3" Insulation Plates',
    category: 'Fasteners & Plates',
    notes: 'Single SKU. Used by L1, L2, tapered, and cover board fasteners.',
  ),
  SkuRegistryEntry(
    skuKey: 'plate_seam_stress_3in',
    displayName: '3" Seam Stress Plates',
    category: 'Fasteners & Plates',
  ),
  SkuRegistryEntry(
    skuKey: 'plate_rhinobond',
    displayName: 'Rhinobond Induction Weld Plates',
    category: 'Fasteners & Plates',
  ),
  SkuRegistryEntry(
    skuKey: 'plate_russ_seam_fastening',
    displayName: 'Seam Fastening Plates — RUSS Strip',
    category: 'Parapet & Termination',
  ),

  // ─── ADHESIVES ────────────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'adhesive_versiweld_bonding',
    displayName: 'VersiWeld TPO Bonding Adhesive',
    category: 'Adhesives & Sealants',
    variantAttributes: ['voc', 'packageGal', 'application'],
    notes: 'packageGal = 1 / 5 / 15. application = field / parapet.',
  ),
  SkuRegistryEntry(
    skuKey: 'adhesive_cavgrip_3v_40lb',
    displayName: 'Versico CAV-GRIP 3V — #40 Cylinder',
    category: 'Adhesives & Sealants',
    variantAttributes: ['voc', 'application'],
  ),
  SkuRegistryEntry(
    skuKey: 'adhesive_olybond_500_set',
    displayName: 'OlyBond500 / FAST 100LV Insulation Adhesive — Dual Cartridge Set',
    category: 'Adhesives & Sealants',
  ),

  // ─── MASTIC / SEALANTS ────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'mastic_water_cutoff',
    displayName: 'Versico Water Cut-Off Mastic',
    category: 'Adhesives & Sealants',
  ),
  SkuRegistryEntry(
    skuKey: 'mastic_water_cutoff_lowvoc',
    displayName: 'Low-VOC Water Cut-Off Mastic (Term Bar)',
    category: 'Parapet & Termination',
  ),
  SkuRegistryEntry(
    skuKey: 'sealant_cut_edge',
    displayName: 'Versico TPO Cut Edge Sealant',
    category: 'Adhesives & Sealants',
    variantAttributes: ['voc'],
  ),
  SkuRegistryEntry(
    skuKey: 'sealant_lap',
    displayName: 'Versico Lap Sealant',
    category: 'Adhesives & Sealants',
    variantAttributes: ['voc'],
  ),
  SkuRegistryEntry(
    skuKey: 'sealant_universal_singleply',
    displayName: 'Universal Single-Ply Sealant',
    category: 'Parapet & Termination',
  ),

  // ─── PRIMER / CLEANER ─────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'primer_tpo_225',
    displayName: 'Versico TPO Primer (225 sf/gal)',
    category: 'Adhesives & Sealants',
    variantAttributes: ['voc'],
  ),
  SkuRegistryEntry(
    skuKey: 'primer_lowvoc_epdm_tpo_700',
    displayName: 'Versico Low-VOC EPDM & TPO Primer (700 sf/gal)',
    category: 'Adhesives & Sealants',
  ),
  SkuRegistryEntry(
    skuKey: 'primer_cavprime_cylinder',
    displayName: 'Versico CAV-PRIME Low-VOC Primer — #32 Cylinder',
    category: 'Adhesives & Sealants',
  ),
  SkuRegistryEntry(
    skuKey: 'primer_deck_substrate',
    displayName: 'Deck Primer (Post Tear-Off Prep)',
    category: 'Adhesives & Sealants',
  ),
  SkuRegistryEntry(
    skuKey: 'primer_vapor_retarder',
    displayName: 'Vapor Retarder Primer',
    category: 'Adhesives & Sealants',
  ),
  SkuRegistryEntry(
    skuKey: 'cleaner_weathered_membrane',
    displayName: 'Versico Weathered Membrane Cleaner',
    category: 'Adhesives & Sealants',
    variantAttributes: ['voc'],
  ),
  SkuRegistryEntry(
    skuKey: 'cleaner_untack_8oz_aerosol',
    displayName: 'Versico UN-TACK Adhesive Remover & Cleaner — #8 Aerosol',
    category: 'Adhesives & Sealants',
    variantAttributes: ['application'],
  ),
  SkuRegistryEntry(
    skuKey: 'cleaner_rags_tpo',
    displayName: 'Rags & TPO Cleaner',
    category: 'Details & Accessories',
  ),

  // ─── TERMINATION ──────────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'term_bar_aluminum_10ft',
    displayName: 'Termination Bar (Aluminum, 10\')',
    category: 'Parapet & Termination',
  ),
  SkuRegistryEntry(
    skuKey: 'term_tpo_coated_drip_edge_10ft',
    displayName: 'TPO Coated Drip Edge (10\')',
    category: 'Parapet & Termination',
  ),
  SkuRegistryEntry(
    skuKey: 'russ_strip_6in',
    displayName: 'VersiWeld RUSS Strip (6")',
    category: 'Parapet & Termination',
  ),

  // ─── ACCESSORIES ──────────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'accessory_tjoint_covers',
    displayName: 'T-Joint Covers (Cover Tape)',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'tape_tpo_seam_3in',
    displayName: 'Versico TPO Seam Tape (3" wide)',
    category: 'Adhesives & Sealants',
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_corner_inside_prefab',
    displayName: 'TPO Inside Corners (Prefab)',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_corner_outside_prefab',
    displayName: 'TPO Outside Corners (Prefab)',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_drain_assembly',
    displayName: 'Roof Drain Assembly',
    category: 'Details & Accessories',
    variantAttributes: ['drainType'],
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_pipeboot_small',
    displayName: 'Pipe Boot — Small (1–4")',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_pipeboot_large',
    displayName: 'Pipe Boot — Large (4–12")',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_skylight_kit',
    displayName: 'Skylight Flashing Kit',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_scupper',
    displayName: 'Scupper Assembly',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_pitch_pan',
    displayName: 'TPO Molded Sealant Pocket (Pitch Pan)',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_expansion_joint_cover',
    displayName: 'Expansion Joint Cover',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_rtu_corner_wrap',
    displayName: 'TPO Curb Wrap Corners — RTU',
    category: 'Details & Accessories',
  ),
  SkuRegistryEntry(
    skuKey: 'accessory_hook_blades',
    displayName: 'Hook Blades',
    category: 'Details & Accessories',
  ),

  // ─── METAL SCOPE ──────────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'metal_coping_cap',
    displayName: 'Coping Cap',
    category: 'Metal Scope',
    variantAttributes: ['width'],
  ),
  SkuRegistryEntry(
    skuKey: 'metal_wall_flashing',
    displayName: 'Wall Flashing',
    category: 'Metal Scope',
  ),
  SkuRegistryEntry(
    skuKey: 'metal_drip_edge',
    displayName: 'Drip Edge',
    category: 'Metal Scope',
    variantAttributes: ['edgeMetalType'],
  ),
  SkuRegistryEntry(
    skuKey: 'metal_other_edge',
    displayName: 'Other Edge Metal',
    category: 'Metal Scope',
  ),
  SkuRegistryEntry(
    skuKey: 'metal_gutter',
    displayName: 'Gutter',
    category: 'Metal Scope',
    variantAttributes: ['size'],
  ),
  SkuRegistryEntry(
    skuKey: 'metal_downspout',
    displayName: 'Downspout',
    category: 'Metal Scope',
  ),

  // ─── VAPOR RETARDER ───────────────────────────────────────────────────────
  SkuRegistryEntry(
    skuKey: 'vapor_retarder',
    displayName: 'Vapor Retarder',
    category: 'Vapor Retarder',
    variantAttributes: ['type'],
  ),
];

/// Lookup by skuKey. Returns null if not registered.
SkuRegistryEntry? lookupSkuRegistryEntry(String skuKey) {
  for (final e in kSkuRegistry) {
    if (e.skuKey == skuKey) return e;
  }
  return null;
}

/// All registered keys grouped by category, preserving registry order.
Map<String, List<SkuRegistryEntry>> skuRegistryByCategory() {
  final out = <String, List<SkuRegistryEntry>>{};
  for (final e in kSkuRegistry) {
    out.putIfAbsent(e.category, () => []).add(e);
  }
  return out;
}
