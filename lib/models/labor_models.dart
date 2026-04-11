/// lib/models/labor_models.dart
///
/// Data models for the labor cost estimation system.
///
/// Crews are project-level — each crew has a name and a set of per-item
/// rates. The selected crew's rates are multiplied by BOM-derived quantities
/// to produce labor line items.

/// Default labor line items with their standard rates.
/// Key = labor item name, value = default rate ($ per unit).
/// Default rates are per the unit shown in kLaborUnits.
/// SQ = 100 square feet (1 roofing square).
const Map<String, double> kDefaultLaborRates = {
  // Tear-off (per SQ)
  'Remove Torch Down': 15.00,
  'Remove EPDM': 15.00,
  'Remove TPO': 15.00,
  'Remove PVC': 15.00,
  'Remove Spray Foam': 20.00,
  'Remove Loose Gravel': 50.00,
  'Remove Tar and Gravel': 20.00,
  'Tear Off Wood Fiber': 10.00,
  // Install (per SQ)
  'Install Cover Board': 10.00,
  'Flutes': 10.00,
  'Install ISO Board': 10.00,
  'Install Taper System': 30.00,
  'Install TPO Membrane': 45.00,
  'Install Parapet Flashings': 75.00,
  'Install Crickets (sf)': 30.00,
  // Per unit
  'Install Decking (per sheet)': 15.00,
  'Install Custom HVAC Pipes': 25.00,
  'Install Custom Curb (exhaust fan)': 75.00,
  'HVAC Curbs': 150.00,
  'Skylight Curbs': 75.00,
  'Install Custom Scupper': 75.00,
  'Install Sealant Pockets': 75.00,
  // Per LF
  'Install Walkway Pads (p/f)': 1.00,
  'Install Drip Edge and Tape': 1.50,
  'Install Termination Bar': 1.50,
  'Install Cap Metal (per foot)': 2.50,
  'Install Wall Flashing': 1.50,
  'Install Gutter': 2.50,
  // Fixed
  'Drains': 50.00,
  'Dump Fees': 450.00,
};

/// All labor item names in display order.
const List<String> kLaborItemNames = [
  'Remove Torch Down',
  'Remove EPDM',
  'Remove TPO',
  'Remove PVC',
  'Remove Spray Foam',
  'Remove Loose Gravel',
  'Remove Tar and Gravel',
  'Tear Off Wood Fiber',
  'Install Cover Board',
  'Flutes',
  'Install ISO Board',
  'Install Taper System',
  'Install TPO Membrane',
  'Install Parapet Flashings',
  'Install Crickets (sf)',
  'Install Decking (per sheet)',
  'Install Custom HVAC Pipes',
  'Install Custom Curb (exhaust fan)',
  'HVAC Curbs',
  'Skylight Curbs',
  'Install Custom Scupper',
  'Install Sealant Pockets',
  'Install Walkway Pads (p/f)',
  'Install Drip Edge and Tape',
  'Install Termination Bar',
  'Install Cap Metal (per foot)',
  'Install Wall Flashing',
  'Install Gutter',
  'Drains',
  'Dump Fees',
];

/// Unit type for each labor item.
/// SQ = 1 roofing square = 100 sq ft.
const Map<String, String> kLaborUnits = {
  'Remove Torch Down': 'SQ',
  'Remove EPDM': 'SQ',
  'Remove TPO': 'SQ',
  'Remove PVC': 'SQ',
  'Remove Spray Foam': 'SQ',
  'Remove Loose Gravel': 'SQ',
  'Remove Tar and Gravel': 'SQ',
  'Tear Off Wood Fiber': 'SQ',
  'Install Cover Board': 'SQ',
  'Flutes': 'SQ',
  'Install ISO Board': 'SQ',
  'Install Taper System': 'SQ',
  'Install TPO Membrane': 'SQ',
  'Install Parapet Flashings': 'SQ',
  'Install Crickets (sf)': 'SQ',
  'Install Decking (per sheet)': 'sheets',
  'Install Custom HVAC Pipes': 'each',
  'Install Custom Curb (exhaust fan)': 'each',
  'HVAC Curbs': 'each',
  'Skylight Curbs': 'each',
  'Install Custom Scupper': 'each',
  'Install Sealant Pockets': 'each',
  'Install Walkway Pads (p/f)': 'LF',
  'Install Drip Edge and Tape': 'LF',
  'Install Termination Bar': 'LF',
  'Install Cap Metal (per foot)': 'LF',
  'Install Wall Flashing': 'LF',
  'Install Gutter': 'LF',
  'Drains': 'each',
  'Dump Fees': 'each',
};

/// A named crew with per-item labor rates.
class LaborCrew {
  final String name;

  /// Item name → rate per unit. Missing entries use kDefaultLaborRates.
  final Map<String, double> rates;

  const LaborCrew({required this.name, this.rates = const {}});

  /// Get the rate for a labor item (crew override or default).
  double rateFor(String itemName) =>
      rates[itemName] ?? kDefaultLaborRates[itemName] ?? 0.0;

  LaborCrew copyWith({String? name, Map<String, double>? rates}) =>
      LaborCrew(name: name ?? this.name, rates: rates ?? this.rates);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaborCrew && name == other.name && _mapEquals(rates, other.rates);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(rates.entries));

  static bool _mapEquals(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}

/// A computed labor line item with quantity and cost.
class LaborLineItem {
  final String name;
  final String unit;
  final double rate;
  final double quantity;

  const LaborLineItem({
    required this.name,
    required this.unit,
    required this.rate,
    required this.quantity,
  });

  double get total => rate * quantity;
  bool get hasQuantity => quantity > 0;
}
