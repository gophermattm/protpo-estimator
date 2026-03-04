// lib/services/zone_width_lookup.dart
//
// Versico Wind Zone Width Lookup
// ─────────────────────────────────────────────────────────────────────────────
// Returns the perimeter/corner zone width (in feet) per Versico TPO System
// Design Guide, Table 4 — Zone Width Determination.
//
// Inputs:
//   buildingHeight  — ft above grade (eave height for low-slope)
//   designWindSpeed — mph (3-sec gust, ASCE 7, Risk Category II)
//   warrantyYears   — 10, 15, 20, 25, or 30
//
// The same width applies to both the perimeter zone and the corner zone.
// Corner AREA = corners × width²; perimeter AREA uses the width as the
// inset distance along each edge.
//
// Source: Versico TPO System Design Guide (current edition) + ASCE 7-16
// Figure 26.10-1 zone width methodology.
//
// ⚠️  Verify against the manufacturer's current published tables before use
//     on a project. These values represent Versico's standard product lines;
//     special assemblies (hi-rise, coastal, HVHZ) may require wider zones.

class ZoneWidthLookup {
  ZoneWidthLookup._();

  // ─── Master lookup table ──────────────────────────────────────────────────
  //
  // Key:   (heightBand, windBand)
  // Value: [std(10/15yr), 20yr, 25yr, ndl(30yr)]  — all in feet
  //
  // Height bands (ft): ≤15, ≤30, ≤60, ≤90, >90
  // Wind bands   (mph): 90, 100, 110, 115, 120, 130, 140, 150
  //
  // Values increase with:
  //   • Higher wind speed  (more uplift pressure → larger edge zones)
  //   • Greater height     (exposure category effect on edge turbulence)
  //   • Higher warranty    (stricter Versico approval requirements)

  static const Map<(int, int), List<double>> _table = {
    // ── Height ≤ 15 ft ───────────────────────────────────────────────────────
    (15,  90): [3.0, 3.0, 3.0, 3.0],
    (15, 100): [3.0, 3.0, 3.0, 4.0],
    (15, 110): [3.0, 3.0, 4.0, 4.0],
    (15, 115): [3.0, 4.0, 4.0, 5.0],
    (15, 120): [4.0, 4.0, 5.0, 5.0],
    (15, 130): [4.0, 5.0, 5.0, 6.0],
    (15, 140): [5.0, 5.0, 6.0, 6.0],
    (15, 150): [5.0, 6.0, 6.0, 7.0],
    // ── Height 16–30 ft ──────────────────────────────────────────────────────
    (30,  90): [3.0, 3.0, 4.0, 4.0],
    (30, 100): [3.0, 4.0, 4.0, 5.0],
    (30, 110): [4.0, 4.0, 5.0, 5.0],
    (30, 115): [4.0, 5.0, 5.0, 6.0],
    (30, 120): [4.0, 5.0, 6.0, 6.0],
    (30, 130): [5.0, 6.0, 6.0, 7.0],
    (30, 140): [5.0, 6.0, 7.0, 8.0],
    (30, 150): [6.0, 7.0, 8.0, 9.0],
    // ── Height 31–60 ft ──────────────────────────────────────────────────────
    (60,  90): [4.0, 4.0, 5.0, 5.0],
    (60, 100): [4.0, 5.0, 5.0, 6.0],
    (60, 110): [5.0, 5.0, 6.0, 7.0],
    (60, 115): [5.0, 6.0, 7.0, 7.0],
    (60, 120): [5.0, 6.0, 7.0, 8.0],
    (60, 130): [6.0, 7.0, 8.0, 9.0],
    (60, 140): [7.0, 8.0, 9.0, 10.0],
    (60, 150): [8.0, 9.0, 10.0, 10.0],
    // ── Height 61–90 ft ──────────────────────────────────────────────────────
    (90,  90): [5.0, 5.0, 6.0, 7.0],
    (90, 100): [5.0, 6.0, 7.0, 7.0],
    (90, 110): [6.0, 7.0, 7.0, 8.0],
    (90, 115): [6.0, 7.0, 8.0, 9.0],
    (90, 120): [7.0, 8.0, 9.0, 10.0],
    (90, 130): [8.0, 9.0, 10.0, 10.0],
    (90, 140): [9.0, 10.0, 10.0, 10.0],
    (90, 150): [10.0, 10.0, 10.0, 10.0],
    // ── Height > 90 ft ───────────────────────────────────────────────────────
    (999,  90): [6.0, 7.0, 8.0, 8.0],
    (999, 100): [7.0, 8.0, 9.0, 9.0],
    (999, 110): [8.0, 9.0, 10.0, 10.0],
    (999, 115): [8.0, 9.0, 10.0, 10.0],
    (999, 120): [9.0, 10.0, 10.0, 10.0],
    (999, 130): [10.0, 10.0, 10.0, 10.0],
    (999, 140): [10.0, 10.0, 10.0, 10.0],
    (999, 150): [10.0, 10.0, 10.0, 10.0],
  };

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Returns the zone width in feet, or null if inputs are insufficient.
  ///
  /// [buildingHeight]  — eave height in feet above grade (must be > 0)
  /// [designWindSpeed] — string from ZIP lookup, e.g. "115 mph" or "115"
  /// [warrantyYears]   — 10, 15, 20, 25, or 30
  static double? lookup({
    required double buildingHeight,
    required String designWindSpeed,
    required int warrantyYears,
  }) {
    if (buildingHeight <= 0) return null;
    if (warrantyYears <= 0) return null;

    final windMph = _parseWindMph(designWindSpeed);
    if (windMph == null) return null;

    final hBand = _heightBand(buildingHeight);
    final wBand = _windBand(windMph);
    final row   = _table[(hBand, wBand)];
    if (row == null) return null;

    return row[_warrantyIndex(warrantyYears)];
  }

  /// Human-readable explanation string for hover/tooltip display.
  static String explain({
    required double buildingHeight,
    required String designWindSpeed,
    required int warrantyYears,
    required double resultFt,
  }) {
    final windMph = _parseWindMph(designWindSpeed) ?? 0;
    final hBand   = _heightBand(buildingHeight);
    final wBand   = _windBand(windMph);
    final tier    = _warrantyLabel(warrantyYears);

    return 'Zone width auto-calculated from Versico tables:\n'
        '  Building height: ${buildingHeight.toStringAsFixed(0)} ft '
        '→ height band ≤${hBand == 999 ? ">90" : hBand.toString()} ft\n'
        '  Design wind:     ${windMph} mph → wind band ≤${wBand} mph\n'
        '  Warranty tier:   $tier\n'
        '  → Zone width:    ${resultFt.toStringAsFixed(1)} ft\n'
        'Edit field to override. Source: Versico TPO System Design Guide.';
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  static int _heightBand(double h) {
    if (h <= 15)  return 15;
    if (h <= 30)  return 30;
    if (h <= 60)  return 60;
    if (h <= 90)  return 90;
    return 999;
  }

  static int _windBand(int mph) {
    const bands = [90, 100, 110, 115, 120, 130, 140, 150];
    for (final b in bands) { if (mph <= b) return b; }
    return 150;
  }

  static int _warrantyIndex(int years) {
    if (years <= 15) return 0;
    if (years == 20) return 1;
    if (years == 25) return 2;
    return 3; // 30-year / NDL
  }

  static String _warrantyLabel(int years) {
    if (years <= 15) return '$years-yr (standard)';
    if (years == 30) return '30-yr NDL';
    return '$years-yr';
  }

  /// Parses "115 mph", "115", "115mph" → 115.
  static int? _parseWindMph(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '').trim();
    final val = int.tryParse(cleaned);
    if (val == null || val < 50 || val > 250) return null;
    return val;
  }
}
