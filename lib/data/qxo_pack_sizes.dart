/// lib/data/qxo_pack_sizes.dart
///
/// Versico fastener and plate pack sizes as stocked by QXO.
///
/// Snapshot of the QXO catalog (itemDetails variants) taken 2026-09-29 via the
/// gorilla-integrations gateway. Regenerate with `tools/qxo_pack_sizes.py`.
/// Pack size varies by length — e.g. #14 HPV is 1,000/carton up to 6" but
/// 500/carton at 8" — so fasteners are looked up per length.

/// Fastener family → { length in inches → units per carton }.
/// Keys double as the lengths QXO stocks.
final Map<String, Map<double, int>> kQxoFastenerPacks = {
  // Versico #14 HPV (wood decks)
  'HPV': {1.25: 1000, 2: 1000, 4: 1000, 5: 1000, 6: 1000, 8: 500},
  // Versico #15 HPVX (steel, gypsum, cementitious wood fiber)
  'HPVX': {2: 1000, 3: 1000, 4: 1000, 5: 500, 6: 500, 7: 500, 8: 500,
      9: 500, 10: 500, 12: 500},
  // Versico #14-10 MP (structural concrete)
  'MP 14-10': {1.25: 1000, 1.75: 1000, 2: 1000, 3: 1000, 4: 1000, 5: 500,
      6: 500, 7: 500, 14: 250},
};

/// Plate pack sizes (units per carton).
const int kQxoInsulationPlate3inPack = 1000; // 3" Steel Insulation Fastening Plates
const int kQxoSeamPlate2inPack = 1000;       // 2" Seam Fastening Plates (HPV)
const int kQxoHpvxPlatePack = 1000;          // 2.38" HPVX Steel Fastening Plates
const int kQxoRhinobondPlatePack = 500;      // 3" RhinoBond TPO Plates

/// Pack size used when QXO doesn't stock the family/length (e.g. CD-10).
const int kDefaultFastenerPack = 500;

/// QXO fastener family for a deck-fastener display name
/// ("Versico HPVX" → "HPVX"), or null when QXO doesn't carry it.
String? qxoFastenerFamily(String fastenerName) {
  if (fastenerName.contains('HPVX')) return 'HPVX';
  if (fastenerName.contains('HPV')) return 'HPV';
  if (fastenerName.contains('MP 14-10')) return 'MP 14-10';
  return null;
}

/// Units per carton for [fastenerName] at [lengthIn]; falls back to
/// [kDefaultFastenerPack] when QXO has no matching variant.
int qxoFastenerPack(String fastenerName, double lengthIn) {
  final fam = qxoFastenerFamily(fastenerName);
  return kQxoFastenerPacks[fam]?[lengthIn] ?? kDefaultFastenerPack;
}
