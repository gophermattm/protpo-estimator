/// lib/models/insulation_system.dart
///
/// Immutable data classes for the Insulation section.
/// Matches INPUT_SPECIFICATIONS.md section 4.
/// R-value calculations delegate to RValueCalculator in lib/services/.

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
  '1/4:12',
  '1/2:12',
];

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

// ─── TAPERED INSULATION ───────────────────────────────────────────────────────

class TaperedInsulation {
  /// Board product name from Versico/Tri-Built loading chart.
  /// [Inference] Exact product list requires Versico catalog — stored as
  /// free text until the product table is implemented.
  final String boardType;
  final String taperSlope;          // from kTaperSlopeOptions
  final double minThicknessAtDrain; // from kTaperMinThicknesses, inches
  final double maxThickness;        // user input or calculated, inches
  final double systemArea;          // sq ft — may be partial roof

  const TaperedInsulation({
    this.boardType = '',
    this.taperSlope = '1/4:12',
    this.minThicknessAtDrain = 0.5,
    this.maxThickness = 0.0,
    this.systemArea = 0.0,
  });

  factory TaperedInsulation.initial() => const TaperedInsulation();

  /// Average R-value uses arithmetic mean thickness.
  /// Delegates the actual R/inch lookup to be done at the provider level
  /// (avoids importing the calculator service into the model layer).
  double get averageThickness =>
      (minThicknessAtDrain + maxThickness) / 2;

  TaperedInsulation copyWith({
    String? boardType,
    String? taperSlope,
    double? minThicknessAtDrain,
    double? maxThickness,
    double? systemArea,
  }) {
    return TaperedInsulation(
      boardType: boardType ?? this.boardType,
      taperSlope: taperSlope ?? this.taperSlope,
      minThicknessAtDrain: minThicknessAtDrain ?? this.minThicknessAtDrain,
      maxThickness: maxThickness ?? this.maxThickness,
      systemArea: systemArea ?? this.systemArea,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaperedInsulation &&
          boardType == other.boardType &&
          taperSlope == other.taperSlope &&
          minThicknessAtDrain == other.minThicknessAtDrain &&
          maxThickness == other.maxThickness &&
          systemArea == other.systemArea;

  @override
  int get hashCode => Object.hash(
        boardType,
        taperSlope,
        minThicknessAtDrain,
        maxThickness,
        systemArea,
      );
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
  final int numberOfLayers;     // 1 or 2
  final InsulationLayer layer1;
  final InsulationLayer? layer2; // null when numberOfLayers == 1

  final bool hasTaperedInsulation;
  final TaperedInsulation? tapered; // null when hasTaperedInsulation == false

  final bool hasCoverBoard;
  final CoverBoard? coverBoard;    // null when hasCoverBoard == false

  const InsulationSystem({
    this.numberOfLayers = 1,
    this.layer1 = const InsulationLayer(),
    this.layer2,
    this.hasTaperedInsulation = false,
    this.tapered,
    this.hasCoverBoard = false,
    this.coverBoard,
  });

  factory InsulationSystem.initial() => const InsulationSystem();

  InsulationSystem copyWith({
    int? numberOfLayers,
    InsulationLayer? layer1,
    InsulationLayer? layer2,
    bool? hasTaperedInsulation,
    TaperedInsulation? tapered,
    bool? hasCoverBoard,
    CoverBoard? coverBoard,
  }) {
    return InsulationSystem(
      numberOfLayers: numberOfLayers ?? this.numberOfLayers,
      layer1: layer1 ?? this.layer1,
      layer2: layer2 ?? this.layer2,
      hasTaperedInsulation: hasTaperedInsulation ?? this.hasTaperedInsulation,
      tapered: tapered ?? this.tapered,
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

  /// Enables tapered insulation — seeds with defaults if not yet set.
  InsulationSystem withTaperedEnabled() => copyWith(
        hasTaperedInsulation: true,
        tapered: tapered ?? TaperedInsulation.initial(),
      );

  InsulationSystem withTaperedDisabled() =>
      copyWith(hasTaperedInsulation: false);

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
          hasTaperedInsulation == other.hasTaperedInsulation &&
          tapered == other.tapered &&
          hasCoverBoard == other.hasCoverBoard &&
          coverBoard == other.coverBoard;

  @override
  int get hashCode => Object.hash(
        numberOfLayers,
        layer1,
        layer2,
        hasTaperedInsulation,
        tapered,
        hasCoverBoard,
        coverBoard,
      );
}
