/// lib/data/versico_ma_fastening.dart
///
/// Versico mechanically attached (MA) TPO membrane fastening criteria.
///
/// Source: Versico VersiWeld TPO 3-Part CSI Format Design Guide (7/2025),
/// "TPO Membrane Fastening Criteria" — the same document indexed into the
/// VersiBot knowledge base (Firestore `versico_technical_data`):
///   - Steel / structural concrete decks table (p. 9)
///   - Table III, wood (plywood / OSB) decks (p. 10)
///   - Table IV, lightweight insulating concrete / gypsum / cementitious
///     wood fiber decks (p. 11)
/// All tables are "Up to 20 Year Warranty". Rows are keyed by the Peak Gust
/// Wind Speed Warranty (55 / 72 / 80 / 90 mph), building height, deck, and
/// sheet widths; each row gives the minimum number of perimeter sheets by
/// distance from the coastline and one fastening density (in the seam) that
/// applies to both field and perimeter sheets.
///
/// Fasteners are placed in the seam, which is lapped ~5-1/2" (MA spec
/// 3.0 B.3), so each sheet contributes (width − 5.5") of seam spacing.

/// Seam lap for MA sheets where fastening plates are located (feet).
const double kVersicoMaSeamLapFt = 5.5 / 12.0;

/// Peak Gust Wind Speed Warranty options (mph).
const List<int> kVersicoWindWarrantyMph = [55, 72, 80, 90];

/// Building distance from coastline bands, in table column order.
const List<String> kCoastlineDistances = [
  'Greater than 7 miles',
  '3 to 7 miles',
  'Less than 3 miles',
];

/// Wood deck grades from Table III (projected pull-out value).
const List<String> kWoodDeckGrades = [
  '15/32" 5-Ply Plywood',
  '15/32" 3-Ply Plywood',
  '5/8" OSB',
  '7/16" OSB',
];

enum VersicoMaStatus {
  /// Row found for the exact deck / wind / height / sheet widths.
  ok,

  /// Deck / wind / height is in the table but not with these sheet widths.
  sheetWidthNotListed,

  /// Not acceptable ("N/A") for this coastline distance.
  notAcceptable,

  /// Outside the published tables — Versico approval required.
  contactVersico,
}

class VersicoMaResult {
  final VersicoMaStatus status;

  /// Minimum number of perimeter sheets at the building edge.
  final int perimeterSheets;

  /// Fastener spacing in the seam, inches o.c. (field and perimeter sheets).
  final double spacingIn;

  /// Human-readable basis for the trace / warnings.
  final String basis;

  /// Field/perimeter sheet width pairs the table lists for this condition.
  final List<String> listedSheets;

  const VersicoMaResult({
    required this.status,
    required this.perimeterSheets,
    required this.spacingIn,
    required this.basis,
    this.listedSheets = const [],
  });

  bool get isListed => status == VersicoMaStatus.ok;
}

class _Row {
  final String deck;          // 'steel', 'concrete', 'wood', 'lwc', 'gypsum'
  final String? woodGrade;    // Table III only
  final int wind;             // mph
  final bool tall;            // true = 61'–100' (steel/concrete table only)
  final int fieldFt;
  final int perimFt;
  final List<int?> sheets;    // by coastline band; null = N/A
  final List<double?> spacing; // by coastline band (footnotes can tighten)
  final String note;
  const _Row(this.deck, this.woodGrade, this.wind, this.tall, this.fieldFt,
      this.perimFt, this.sheets, this.spacing, [this.note = '']);
}

// "**" note on the steel/concrete table: structural concrete 12" o.c.
// (MP 14-10 / CD-10); steel 6" o.c. with HPVX (12" o.c. only with HPV-XL).
const double _ssSteel = 6, _ssConc = 12;

List<_Row> _steelConcrete(String deck) {
  final ss = deck == 'steel' ? _ssSteel : _ssConc;
  const t = [12.0, 12.0, 12.0];
  final s = [ss, ss, ss];
  return [
    _Row(deck, null, 55, false, 12, 6, const [1, 2, 3], t),
    _Row(deck, null, 55, false, 10, 6, const [1, 2, 3], t),
    _Row(deck, null, 55, false, 8, 4, const [1, 2, 3], t),
    _Row(deck, null, 55, true, 10, 6, const [2, 2, 3], s, '** note'),
    _Row(deck, null, 55, true, 8, 4, const [2, 2, 3], t),
    _Row(deck, null, 72, false, 12, 6, const [2, 2, 3], t),
    _Row(deck, null, 72, false, 10, 6, const [2, 2, 3], t),
    _Row(deck, null, 72, false, 8, 4, const [2, 2, 3], t),
    _Row(deck, null, 72, true, 10, 6, const [3, 4, 4], s, '** note'),
    _Row(deck, null, 72, true, 8, 4, const [3, 4, 4], t),
    _Row(deck, null, 80, false, 10, 6, const [3, 3, 4], s, '** note'),
    _Row(deck, null, 80, false, 8, 4, const [3, 3, 4], t),
    _Row(deck, null, 80, true, 10, 6, const [3, 4, 4], s, '** note'),
    _Row(deck, null, 80, true, 8, 4, const [3, 4, 4], t),
    _Row(deck, null, 90, false, 10, 6, const [3, 4, 4], s, '** note'),
    _Row(deck, null, 90, false, 8, 4, const [3, 4, 4], t),
    _Row(deck, null, 90, true, 10, 6, const [4, 5, 5], s, '** note'),
    _Row(deck, null, 90, true, 8, 4, const [4, 5, 5], t),
  ];
}

const _t12 = [12.0, 12.0, 12.0];
const _t9 = [9.0, 9.0, 9.0];

final List<_Row> _rows = [
  ..._steelConcrete('steel'),
  ..._steelConcrete('concrete'),
  // Table III — wood decks (up to 60' building height)
  const _Row('wood', '7/16" OSB', 55, false, 10, 6, [2, 3, 3], _t9),
  const _Row('wood', '7/16" OSB', 55, false, 8, 4, [2, 3, 3], _t12),
  const _Row('wood', '15/32" 3-Ply Plywood', 55, false, 8, 4, [2, 2, 3], _t12),
  const _Row('wood', '15/32" 5-Ply Plywood', 55, false, 10, 6, [1, 2, 3], _t12),
  const _Row('wood', '5/8" OSB', 55, false, 10, 6, [2, 3, 3], _t12),
  const _Row('wood', '5/8" OSB', 55, false, 8, 4, [2, 3, 3], _t12),
  const _Row('wood', '15/32" 3-Ply Plywood', 72, false, 8, 4, [2, 3, 3], _t12),
  const _Row('wood', '15/32" 5-Ply Plywood', 72, false, 10, 6, [2, 3, 3], _t12),
  const _Row('wood', '5/8" OSB', 72, false, 8, 4, [2, 3, 3], _t12),
  // Table IV — 55 mph only, 50' max building height
  // (1) 12' sheets 3–7 mi: 6" o.c.; (2) 51'–75' with 10' sheets: 9" o.c.;
  // (3) 8' sheets acceptable to 75'; (4) <3 mi with 8' sheets: 9" o.c.
  const _Row('lwc', null, 55, false, 12, 6, [2, 3, null], [12, 6, null], 'Table IV (1)'),
  const _Row('lwc', null, 55, false, 10, 6, [1, 2, 4], _t12, 'Table IV'),
  const _Row('lwc', null, 55, false, 8, 4, [1, 2, 3], _t12, 'Table IV'),
  const _Row('gypsum', null, 55, false, 10, 6, [2, 3, null], [9, 9, null], 'Table IV'),
  const _Row('gypsum', null, 55, false, 8, 4, [2, 3, 4], [12, 12, 9], 'Table IV (4)'),
];

String _deckKey(String deckType) {
  switch (deckType) {
    case 'Metal':       return 'steel';
    case 'Concrete':    return 'concrete';
    case 'Wood':        return 'wood';
    case 'LW Concrete': return 'lwc';
    case 'Gypsum':
    case 'Tectum':      return 'gypsum';
    default:            return 'steel';
  }
}

int _ft(String width) =>
    int.tryParse(width.replaceAll("'", '').trim()) ?? 10;

/// Looks up Versico MA fastening criteria.
///
/// Anything the tables don't list returns a conservative fallback — the most
/// perimeter sheets for that group and 6" o.c. (the tight end of Versico's
/// 6"–12" range) — with a non-ok [VersicoMaStatus] so the BOM can warn.
VersicoMaResult versicoMaLookup({
  required String deckType,
  required String woodDeckGrade,
  required int windWarrantyMph,
  required double buildingHeightFt,
  required String coastlineDistance,
  required String fieldRollWidth,
  required String perimeterRollWidth,
}) {
  final deck = _deckKey(deckType);
  final coast = kCoastlineDistances.indexOf(coastlineDistance).clamp(0, 2);
  final fieldFt = _ft(fieldRollWidth);
  final perimFt = perimeterRollWidth == 'None' ? 0 : _ft(perimeterRollWidth);
  final tall = buildingHeightFt > 60;

  final maxHeight = switch (deck) {
    'lwc' => fieldFt == 8 ? 75.0 : (fieldFt == 10 ? 75.0 : 50.0),
    'gypsum' => 50.0,
    'wood' => 60.0,
    _ => 100.0,
  };

  final group = _rows.where((r) =>
      r.deck == deck &&
      r.wind == windWarrantyMph &&
      (deck == 'wood' ? r.woodGrade == woodDeckGrade : true) &&
      (deck == 'steel' || deck == 'concrete' ? r.tall == tall : true)).toList();

  VersicoMaResult fallback(VersicoMaStatus status, String why) {
    final most = group.isEmpty
        ? 4
        : group
            .map((r) => r.sheets.whereType<int>().fold(0, (a, b) => a > b ? a : b))
            .fold(0, (a, b) => a > b ? a : b);
    return VersicoMaResult(
      status: status,
      perimeterSheets: most == 0 ? 4 : most,
      spacingIn: 6,
      basis: '$why — using conservative 6" o.c.',
      listedSheets: [for (final r in group) "${r.fieldFt}'/${r.perimFt}'"],
    );
  }

  if (buildingHeightFt > maxHeight) {
    return fallback(VersicoMaStatus.contactVersico,
        'Building height ${buildingHeightFt.toInt()}\' exceeds the Versico table (${maxHeight.toInt()}\' max)');
  }
  if (group.isEmpty) {
    return fallback(VersicoMaStatus.contactVersico,
        'No Versico table for $deckType${deck == 'wood' ? ' ($woodDeckGrade)' : ''} at $windWarrantyMph mph');
  }
  final row = group.where((r) => r.fieldFt == fieldFt && r.perimFt == perimFt).firstOrNull;
  if (row == null) {
    return fallback(VersicoMaStatus.sheetWidthNotListed,
        "$fieldFt'/${perimFt == 0 ? 'no' : "$perimFt'"} perimeter sheets not listed for this condition");
  }
  final sheets = row.sheets[coast];
  var spacing = row.spacing[coast];
  if (sheets == null || spacing == null) {
    return fallback(VersicoMaStatus.notAcceptable,
        'Not acceptable (N/A) for ${kCoastlineDistances[coast].toLowerCase()} from coastline');
  }
  // Table IV (2): LW concrete, 10' sheets, 51'–75' building → 9" o.c.
  if (deck == 'lwc' && fieldFt == 10 && buildingHeightFt > 50) spacing = 9;

  final deckLabel = deck == 'wood' ? 'Wood ($woodDeckGrade)' : deckType;
  return VersicoMaResult(
    status: VersicoMaStatus.ok,
    perimeterSheets: sheets,
    spacingIn: spacing,
    basis: 'Versico MA table: $deckLabel, $windWarrantyMph mph warranty, '
        '${tall ? "61'–100'" : "≤${maxHeight.toInt()}'"} bldg, '
        '${kCoastlineDistances[coast].toLowerCase()} from coast, '
        "$fieldFt'/$perimFt' sheets → $sheets perimeter sheet${sheets == 1 ? '' : 's'}, "
        '${spacing.toInt()}" o.c.${row.note == '** note' && deck == 'steel' ? ' (HPVX; 12" o.c. only with HPV-XL)' : ''}',
  );
}
