/// Manufacturer board schedule data for tapered polyiso insulation.
///
/// Provides panel letter designations, thickness ranges, and lookup functions
/// used by the tapered insulation calculation engine.

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

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

  /// Total rise across the full sequence:
  /// thick edge of the last panel minus thin edge of the first panel.
  double get sequenceRise => panels.last.thickEdge - panels.first.thinEdge;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const List<double> kFlatStockThicknesses = [
  0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0,
];

const List<String> kManufacturers = ['Versico', 'TRI-BUILT'];

const List<String> kAllTaperRates = [
  '1/8:12',
  '3/16:12',
  '1/4:12',
  '3/8:12',
  '1/2:12',
];

// ---------------------------------------------------------------------------
// Panel definitions — R/inch = 5.7 for all panels
// ---------------------------------------------------------------------------

// --- Versico 1/8 standard ---
const _versico18Standard = PanelSequence(
  manufacturer: 'Versico',
  taperRate: '1/8:12',
  profileType: 'standard',
  panels: [
    TaperedPanel(letter: 'AA', thinEdge: 0.5, thickEdge: 1.0, avgThickness: 0.75, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'A',  thinEdge: 1.0, thickEdge: 1.5, avgThickness: 1.25, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'B',  thinEdge: 1.5, thickEdge: 2.0, avgThickness: 1.75, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'C',  thinEdge: 2.0, thickEdge: 2.5, avgThickness: 2.25, rPerInchLTTR: 5.7),
  ],
);

// --- Versico 1/8 extended ---
const _versico18Extended = PanelSequence(
  manufacturer: 'Versico',
  taperRate: '1/8:12',
  profileType: 'extended',
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
);

// --- Versico 1/4 standard ---
const _versico14Standard = PanelSequence(
  manufacturer: 'Versico',
  taperRate: '1/4:12',
  profileType: 'standard',
  panels: [
    TaperedPanel(letter: 'X', thinEdge: 0.5, thickEdge: 1.5, avgThickness: 1.0, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'Y', thinEdge: 1.5, thickEdge: 2.5, avgThickness: 2.0, rPerInchLTTR: 5.7),
  ],
);

// --- Versico 1/4 extended ---
const _versico14Extended = PanelSequence(
  manufacturer: 'Versico',
  taperRate: '1/4:12',
  profileType: 'extended',
  panels: [
    TaperedPanel(letter: 'X',  thinEdge: 0.5, thickEdge: 1.5, avgThickness: 1.0, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'Y',  thinEdge: 1.5, thickEdge: 2.5, avgThickness: 2.0, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'Z',  thinEdge: 2.5, thickEdge: 3.5, avgThickness: 3.0, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'ZZ', thinEdge: 3.5, thickEdge: 4.5, avgThickness: 4.0, rPerInchLTTR: 5.7),
  ],
);

// --- Versico 3/8 standard ---
const _versico38Standard = PanelSequence(
  manufacturer: 'Versico',
  taperRate: '3/8:12',
  profileType: 'standard',
  panels: [
    TaperedPanel(letter: 'SS', thinEdge: 0.5, thickEdge: 2.0, avgThickness: 1.25, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'TT', thinEdge: 2.0, thickEdge: 3.5, avgThickness: 2.75, rPerInchLTTR: 5.7),
  ],
);

// --- Versico 1/2 standard ---
const _versico12Standard = PanelSequence(
  manufacturer: 'Versico',
  taperRate: '1/2:12',
  profileType: 'standard',
  panels: [
    TaperedPanel(letter: 'Q', thinEdge: 0.5, thickEdge: 2.5, avgThickness: 1.5, rPerInchLTTR: 5.7),
  ],
);

// --- TRI-BUILT 1/8 standard ---
const _triBuilt18Standard = PanelSequence(
  manufacturer: 'TRI-BUILT',
  taperRate: '1/8:12',
  profileType: 'standard',
  panels: [
    TaperedPanel(letter: 'AA', thinEdge: 0.5, thickEdge: 1.0, avgThickness: 0.75, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'A',  thinEdge: 1.0, thickEdge: 1.5, avgThickness: 1.25, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'B',  thinEdge: 1.5, thickEdge: 2.0, avgThickness: 1.75, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'C',  thinEdge: 2.0, thickEdge: 2.5, avgThickness: 2.25, rPerInchLTTR: 5.7),
  ],
);

// --- TRI-BUILT 1/4 standard ---
const _triBuilt14Standard = PanelSequence(
  manufacturer: 'TRI-BUILT',
  taperRate: '1/4:12',
  profileType: 'standard',
  panels: [
    TaperedPanel(letter: 'X', thinEdge: 0.5, thickEdge: 1.5, avgThickness: 1.0, rPerInchLTTR: 5.7),
    TaperedPanel(letter: 'Y', thinEdge: 1.5, thickEdge: 2.5, avgThickness: 2.0, rPerInchLTTR: 5.7),
  ],
);

// --- TRI-BUILT 1/2 standard ---
const _triBuilt12Standard = PanelSequence(
  manufacturer: 'TRI-BUILT',
  taperRate: '1/2:12',
  profileType: 'standard',
  panels: [
    TaperedPanel(letter: 'Q', thinEdge: 0.5, thickEdge: 2.5, avgThickness: 1.5, rPerInchLTTR: 5.7),
  ],
);

// ---------------------------------------------------------------------------
// Master sequence table
// ---------------------------------------------------------------------------

const List<PanelSequence> _allSequences = [
  _versico18Standard,
  _versico18Extended,
  _versico14Standard,
  _versico14Extended,
  _versico38Standard,
  _versico12Standard,
  _triBuilt18Standard,
  _triBuilt14Standard,
  _triBuilt12Standard,
];

// ---------------------------------------------------------------------------
// Public functions
// ---------------------------------------------------------------------------

/// Returns the [PanelSequence] for the given [manufacturer], [taperRate], and
/// [profileType].
///
/// Lookup priority:
/// 1. Exact match on all three criteria.
/// 2. If [profileType] is 'extended' and no extended sequence exists, falls
///    back to the standard sequence for the same manufacturer + taperRate.
///
/// Returns null if no match is found even after fallback.
PanelSequence? lookupPanelSequence({
  required String manufacturer,
  required String taperRate,
  required String profileType,
}) {
  // Exact match first.
  for (final seq in _allSequences) {
    if (seq.manufacturer == manufacturer &&
        seq.taperRate == taperRate &&
        seq.profileType == profileType) {
      return seq;
    }
  }

  // Fallback: extended → standard.
  if (profileType == 'extended') {
    for (final seq in _allSequences) {
      if (seq.manufacturer == manufacturer &&
          seq.taperRate == taperRate &&
          seq.profileType == 'standard') {
        return seq;
      }
    }
  }

  return null;
}

/// Parses a taper rate string in "N/D:12" format and returns the decimal slope
/// value (N/D). Returns 0.0 for any invalid input.
double taperRateToDecimal(String taperRate) {
  // Expected format: "N/D:12"
  final colonIdx = taperRate.indexOf(':');
  if (colonIdx == -1) return 0.0;

  final fraction = taperRate.substring(0, colonIdx);
  final slashIdx = fraction.indexOf('/');
  if (slashIdx == -1) return 0.0;

  final numerator = double.tryParse(fraction.substring(0, slashIdx));
  final denominator = double.tryParse(fraction.substring(slashIdx + 1));

  if (numerator == null || denominator == null || denominator == 0) return 0.0;

  return numerator / denominator;
}

/// Returns the profile types available for a given [manufacturer] and
/// [taperRate] combination.
List<String> availableProfileTypes(String manufacturer, String taperRate) {
  final types = <String>[];
  for (final seq in _allSequences) {
    if (seq.manufacturer == manufacturer && seq.taperRate == taperRate) {
      if (!types.contains(seq.profileType)) {
        types.add(seq.profileType);
      }
    }
  }
  return types;
}

/// Returns the taper rates available for a given [manufacturer].
List<String> availableTaperRates(String manufacturer) {
  final rates = <String>[];
  for (final seq in _allSequences) {
    if (seq.manufacturer == manufacturer) {
      if (!rates.contains(seq.taperRate)) {
        rates.add(seq.taperRate);
      }
    }
  }
  return rates;
}
