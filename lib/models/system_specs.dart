/// lib/models/system_specs.dart
///
/// Immutable data class for the System Specs section.
/// Matches INPUT_SPECIFICATIONS.md section 3.

// ─── CONSTANTS ────────────────────────────────────────────────────────────────

const List<String> kProjectTypes = [
  'New Construction',
  'Recover',
  'Tear-off & Replace',
];

const List<String> kDeckTypes = [
  'Metal',
  'Concrete',
  'Wood',
  'Gypsum',
  'Tectum',
  'LW Concrete',
];

const List<String> kVaporRetarderOptions = [
  'None',
  'Self-Adhered',
  'Hot Applied',
  'Mechanically Attached',
];

const List<String> kExistingRoofTypes = [
  'BUR',
  'Modified Bitumen',
  'Single-Ply',
  'Metal',
];

/// Returns valid fastener options for a given deck type.
/// Source: Deck-Fastener Matrix in INPUT_SPECIFICATIONS.md section 3.
List<String> fastenersForDeck(String deckType) {
  switch (deckType) {
    case 'Metal':
      return ['#14 HP Fastener', '#15 HP Fastener'];
    case 'Concrete':
      return ['Concrete Anchor (Pre-drill)'];
    case 'Wood':
      return ['Wood Screw'];
    case 'Gypsum':
      return ['Gypsum-Specific Fastener'];
    case 'Tectum':
      return ['Tectum-Specific Fastener'];
    case 'LW Concrete':
      return ['LW Concrete Anchor'];
    default:
      return [];
  }
}

// ─── SYSTEM SPECS ─────────────────────────────────────────────────────────────

class SystemSpecs {
  final String projectType;    // from kProjectTypes
  final String deckType;       // from kDeckTypes
  final String vaporRetarder;  // from kVaporRetarderOptions

  // Only relevant when projectType is 'Recover' or 'Tear-off & Replace'
  final String existingRoofType;   // from kExistingRoofTypes
  final int existingLayers;        // 1–5
  final bool moistureScanRequired; // defaults to true for recover/tear-off

  const SystemSpecs({
    this.projectType = 'Tear-off & Replace',
    this.deckType = 'Metal',
    this.vaporRetarder = 'None',
    this.existingRoofType = 'BUR',
    this.existingLayers = 1,
    this.moistureScanRequired = true,  // true by default since default is Tear-off
  });

  factory SystemSpecs.initial() => const SystemSpecs();

  /// Whether existing roof fields are relevant to this project.
  bool get isReRoof =>
      projectType == 'Recover' || projectType == 'Tear-off & Replace';

  /// Valid fasteners for the currently selected deck type.
  List<String> get validFasteners => fastenersForDeck(deckType);

  /// Returns true when deck type is set and a fastener can be determined.
  bool get deckTypeIsSet => deckType.isNotEmpty;

  SystemSpecs copyWith({
    String? projectType,
    String? deckType,
    String? vaporRetarder,
    String? existingRoofType,
    int? existingLayers,
    bool? moistureScanRequired,
  }) {
    return SystemSpecs(
      projectType: projectType ?? this.projectType,
      deckType: deckType ?? this.deckType,
      vaporRetarder: vaporRetarder ?? this.vaporRetarder,
      existingRoofType: existingRoofType ?? this.existingRoofType,
      existingLayers: existingLayers ?? this.existingLayers,
      moistureScanRequired: moistureScanRequired ?? this.moistureScanRequired,
    );
  }

  /// When project type changes to a re-roof type, auto-enable moisture scan.
  SystemSpecs withProjectType(String newType) {
    final isNowReRoof =
        newType == 'Recover' || newType == 'Tear-off & Replace';
    return copyWith(
      projectType: newType,
      moistureScanRequired: isNowReRoof ? true : false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemSpecs &&
          projectType == other.projectType &&
          deckType == other.deckType &&
          vaporRetarder == other.vaporRetarder &&
          existingRoofType == other.existingRoofType &&
          existingLayers == other.existingLayers &&
          moistureScanRequired == other.moistureScanRequired;

  @override
  int get hashCode => Object.hash(
        projectType,
        deckType,
        vaporRetarder,
        existingRoofType,
        existingLayers,
        moistureScanRequired,
      );
}
