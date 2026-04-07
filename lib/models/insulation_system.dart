/// lib/models/insulation_system.dart
///
/// Immutable data classes for the Insulation section.
/// Matches INPUT_SPECIFICATIONS.md section 4.
/// R-value calculations delegate to RValueCalculator in lib/services/.

import 'drainage_zone.dart';

// ─── CONSTANTS ────────────────────────────────────────────────────────────────

const List<String> kInsulationTypes = [
  'Polyiso',
  'EPS',
  'XPS',
  'Mineral Wool',
];

const List<double> kInsulationThicknesses = [
  0.5, 1.0, 1.5, 2.0, 2.5, 2.6, 3.0, 3.5, 4.0,
];

const List<String> kAttachmentMethods = [
  'Mechanically Attached',
  'Adhered',
];

const List<String> kCoverBoardTypes = [
  'HD Polyiso',
  'Gypsum',
  'DensDeck',
  'DensDeck Prime',
];

const List<double> kCoverBoardThicknesses = [
  0.25,  // 1/4"
  0.375, // 3/8"
  0.5,   // 1/2"
  0.625, // 5/8"
];

const List<String> kTaperSlopeOptions = [
  '1/8:12',
  '3/16:12',
  '1/4:12',
  '3/8:12',
  '1/2:12',
];

const List<String> kTaperManufacturers = ['Versico', 'TRI-BUILT'];
const List<String> kTaperProfileTypes = ['standard', 'extended'];

const List<double> kTaperMinThicknesses = [0.5, 1.0, 1.5];

// ─── INSULATION LAYER ─────────────────────────────────────────────────────────

class InsulationLayer {
  final String type;             // from kInsulationTypes
  final double thickness;        // from kInsulationThicknesses, in inches
  final String attachmentMethod; // from kAttachmentMethods

  const InsulationLayer({
    this.type = 'Polyiso',
    this.thickness = 2.5,
    this.attachmentMethod = 'Mechanically Attached',
  });

  factory InsulationLayer.initial() => const InsulationLayer();

  InsulationLayer copyWith({
    String? type,
    double? thickness,
    String? attachmentMethod,
  }) {
    return InsulationLayer(
      type: type ?? this.type,
      thickness: thickness ?? this.thickness,
      attachmentMethod: attachmentMethod ?? this.attachmentMethod,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InsulationLayer &&
          type == other.type &&
          thickness == other.thickness &&
          attachmentMethod == other.attachmentMethod;

  @override
  int get hashCode => Object.hash(type, thickness, attachmentMethod);
}

// ─── COVER BOARD ─────────────────────────────────────────────────────────────

class CoverBoard {
  final String type;             // from kCoverBoardTypes
  final double thickness;        // from kCoverBoardThicknesses, inches
  final String attachmentMethod; // from kAttachmentMethods

  const CoverBoard({
    this.type = 'HD Polyiso',
    this.thickness = 0.5,
    this.attachmentMethod = 'Adhered',
  });

  factory CoverBoard.initial() => const CoverBoard();

  CoverBoard copyWith({
    String? type,
    double? thickness,
    String? attachmentMethod,
  }) {
    return CoverBoard(
      type: type ?? this.type,
      thickness: thickness ?? this.thickness,
      attachmentMethod: attachmentMethod ?? this.attachmentMethod,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoverBoard &&
          type == other.type &&
          thickness == other.thickness &&
          attachmentMethod == other.attachmentMethod;

  @override
  int get hashCode => Object.hash(type, thickness, attachmentMethod);
}

// ─── INSULATION SYSTEM ────────────────────────────────────────────────────────

class InsulationSystem {
  final int numberOfLayers;     // 0, 1, or 2
  final InsulationLayer layer1;
  final InsulationLayer? layer2; // null when numberOfLayers == 1

  final bool hasTaper;
  final TaperDefaults? taperDefaults; // null when hasTaper == false
  final List<DrainageZoneOverride> zoneOverrides;

  final bool hasCoverBoard;
  final CoverBoard? coverBoard;    // null when hasCoverBoard == false

  const InsulationSystem({
    this.numberOfLayers = 1,
    this.layer1 = const InsulationLayer(),
    this.layer2,
    this.hasTaper = false,
    this.taperDefaults,
    this.zoneOverrides = const [],
    this.hasCoverBoard = false,
    this.coverBoard,
  });

  factory InsulationSystem.initial() => const InsulationSystem();

  InsulationSystem copyWith({
    int? numberOfLayers,
    InsulationLayer? layer1,
    InsulationLayer? layer2,
    bool? hasTaper,
    TaperDefaults? taperDefaults,
    List<DrainageZoneOverride>? zoneOverrides,
    bool? hasCoverBoard,
    CoverBoard? coverBoard,
  }) {
    return InsulationSystem(
      numberOfLayers: numberOfLayers ?? this.numberOfLayers,
      layer1: layer1 ?? this.layer1,
      layer2: layer2 ?? this.layer2,
      hasTaper: hasTaper ?? this.hasTaper,
      taperDefaults: taperDefaults ?? this.taperDefaults,
      zoneOverrides: zoneOverrides ?? this.zoneOverrides,
      hasCoverBoard: hasCoverBoard ?? this.hasCoverBoard,
      coverBoard: coverBoard ?? this.coverBoard,
    );
  }

  /// Toggle to 2 layers — seeds layer2 with defaults if not yet set.
  InsulationSystem withTwoLayers() => copyWith(
        numberOfLayers: 2,
        layer2: layer2 ?? InsulationLayer.initial(),
      );

  /// Toggle to 1 layer — preserves layer2 data in case user toggles back.
  InsulationSystem withOneLayer() => copyWith(numberOfLayers: 1);

  /// Toggle to 0 layers — no flat insulation (tapered/cover board only).
  InsulationSystem withNoLayers() => copyWith(numberOfLayers: 0);

  /// Enables tapered insulation — seeds with defaults if not yet set.
  InsulationSystem withTaperEnabled() => copyWith(
        hasTaper: true,
        taperDefaults: taperDefaults ?? TaperDefaults.initial(),
      );

  InsulationSystem withTaperDisabled() =>
      copyWith(hasTaper: false);

  /// Enables cover board — seeds with defaults if not yet set.
  InsulationSystem withCoverBoardEnabled() => copyWith(
        hasCoverBoard: true,
        coverBoard: coverBoard ?? CoverBoard.initial(),
      );

  InsulationSystem withCoverBoardDisabled() =>
      copyWith(hasCoverBoard: false);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InsulationSystem &&
          numberOfLayers == other.numberOfLayers &&
          layer1 == other.layer1 &&
          layer2 == other.layer2 &&
          hasTaper == other.hasTaper &&
          taperDefaults == other.taperDefaults &&
          _listEquals(zoneOverrides, other.zoneOverrides) &&
          hasCoverBoard == other.hasCoverBoard &&
          coverBoard == other.coverBoard;

  @override
  int get hashCode => Object.hash(
        numberOfLayers,
        layer1,
        layer2,
        hasTaper,
        taperDefaults,
        Object.hashAll(zoneOverrides),
        hasCoverBoard,
        coverBoard,
      );
}

// ─── HELPERS ─────────────────────────────────────────────────────────────────

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
