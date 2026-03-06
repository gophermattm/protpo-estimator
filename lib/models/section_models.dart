/// lib/models/membrane_system.dart
/// lib/models/parapet_walls.dart
/// lib/models/penetrations.dart
/// lib/models/metal_scope.dart
///
/// Remaining section data models.
/// All match INPUT_SPECIFICATIONS.md sections 5–8.
/// Kept in one file for convenience — split if they grow large.

// ═══════════════════════════════════════════════════════════════════════════════
// MEMBRANE SYSTEM  (section 5)
// ═══════════════════════════════════════════════════════════════════════════════

const List<String> kMembraneTypes = ['TPO', 'PVC', 'EPDM'];
const List<String> kMembraneThicknesses = ['45 mil', '60 mil', '80 mil'];
const List<String> kMembraneColors = ['White', 'Gray', 'Tan', 'Reflective White'];
const List<String> kFieldAttachmentMethods = [
  'Mechanically Attached',
  'Fully Adhered',
  'Rhinobond (Induction Welded)',
];
/// Field roll widths — used for field area calculations only.
const List<String> kRollWidths = ["5'", "10'", "12'"];

/// Perimeter/flashing roll is always 6'×100' per Versico spec. Not user-selectable.
const String kPerimeterRollWidth = "6'";

const List<String> kSeamTypes = ['Hot Air Welded', 'Tape'];

/// Roll coverage in sq ft by roll width (all TPO roll sizes).
const Map<String, double> kRollCoverage = {
  "5'":  500.0,
  "6'":  600.0,
  "10'": 1000.0,
  "12'": 1200.0,
};

class MembraneSystem {
  final String membraneType;        // from kMembraneTypes
  final String thickness;           // from kMembraneThicknesses
  final String color;               // from kMembraneColors
  final String manufacturer;        // "Versico" (only supported manufacturer)
  final String fieldAttachment;     // from kFieldAttachmentMethods
  final String rollWidth;           // from kRollWidths — FIELD AREA ONLY
  final String perimeterRollWidth;  // always kPerimeterRollWidth = "6'" — stored for BOM
  final String seamType;            // from kSeamTypes

  const MembraneSystem({
    this.membraneType = 'TPO',
    this.thickness = '60 mil',
    this.color = 'White',
    this.manufacturer = 'Versico',
    this.fieldAttachment = 'Mechanically Attached',
    this.rollWidth = "10'",
    this.perimeterRollWidth = "6'",
    this.seamType = 'Hot Air Welded',
  });

  factory MembraneSystem.initial() => const MembraneSystem();

  /// Coverage per field roll.
  double get rollCoverage => kRollCoverage[rollWidth] ?? 1000.0;

  /// Coverage per perimeter/flashing roll (always 600 sq ft).
  double get perimeterRollCoverage => 600.0;

  /// True when membrane requires bonding adhesive for field attachment.
  bool get requiresAdhesive => fieldAttachment == 'Fully Adhered';

  MembraneSystem copyWith({
    String? membraneType,
    String? thickness,
    String? color,
    String? manufacturer,
    String? fieldAttachment,
    String? rollWidth,
    String? perimeterRollWidth,
    String? seamType,
  }) {
    return MembraneSystem(
      membraneType: membraneType ?? this.membraneType,
      thickness: thickness ?? this.thickness,
      color: color ?? this.color,
      manufacturer: manufacturer ?? this.manufacturer,
      fieldAttachment: fieldAttachment ?? this.fieldAttachment,
      rollWidth: rollWidth ?? this.rollWidth,
      perimeterRollWidth: perimeterRollWidth ?? this.perimeterRollWidth,
      seamType: seamType ?? this.seamType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MembraneSystem &&
          membraneType == other.membraneType &&
          thickness == other.thickness &&
          color == other.color &&
          manufacturer == other.manufacturer &&
          fieldAttachment == other.fieldAttachment &&
          rollWidth == other.rollWidth &&
          perimeterRollWidth == other.perimeterRollWidth &&
          seamType == other.seamType;

  @override
  int get hashCode => Object.hash(
        membraneType, thickness, color, manufacturer,
        fieldAttachment, rollWidth, perimeterRollWidth, seamType,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// PARAPET WALLS  (section 6)
// ═══════════════════════════════════════════════════════════════════════════════

const List<String> kParapetWallTypes = [
  'Concrete Block',
  'Wood',
  'Metal Stud',
];

const List<String> kTerminationTypes = [
  'Termination Bar',
  'TPO Coated Drip Edge',
];

class ParapetWalls {
  final bool hasParapetWalls;

  // Active when hasParapetWalls == true
  final double parapetHeight;       // inches
  final double parapetTotalLF;      // linear feet
  final String wallType;            // from kParapetWallTypes

  /// Termination bar LF — defaults to parapetTotalLF, but user-editable.
  /// null means "not yet set"; UI should default-display parapetTotalLF.
  final double? terminationBarLFOverride;

  final String terminationType;     // from kTerminationTypes

  const ParapetWalls({
    this.hasParapetWalls = false,
    this.parapetHeight = 0.0,
    this.parapetTotalLF = 0.0,
    this.wallType = 'Concrete Block',
    this.terminationBarLFOverride,
    this.terminationType = 'Termination Bar',
  });

  factory ParapetWalls.initial() => const ParapetWalls();

  /// Parapet area in sq ft: (height in inches ÷ 12) × LF.
  double get parapetArea => (parapetHeight / 12) * parapetTotalLF;

  /// Effective termination bar LF: override if set, otherwise use total LF.
  double get terminationBarLF =>
      terminationBarLFOverride ?? parapetTotalLF;

  /// Anchor type is auto-derived from wall type.
  String get anchorType {
    switch (wallType) {
      case 'Wood':
        return 'Wood Nailers';
      case 'Metal Stud':
        return 'Metal Anchors';
      default:
        return 'Concrete Anchors';
    }
  }

  ParapetWalls copyWith({
    bool? hasParapetWalls,
    double? parapetHeight,
    double? parapetTotalLF,
    String? wallType,
    double? terminationBarLFOverride,
    String? terminationType,
  }) {
    return ParapetWalls(
      hasParapetWalls: hasParapetWalls ?? this.hasParapetWalls,
      parapetHeight: parapetHeight ?? this.parapetHeight,
      parapetTotalLF: parapetTotalLF ?? this.parapetTotalLF,
      wallType: wallType ?? this.wallType,
      terminationBarLFOverride:
          terminationBarLFOverride ?? this.terminationBarLFOverride,
      terminationType: terminationType ?? this.terminationType,
    );
  }

  /// Clears the termination bar override, reverting to auto = parapetTotalLF.
  ParapetWalls clearTerminationBarOverride() => ParapetWalls(
        hasParapetWalls: hasParapetWalls,
        parapetHeight: parapetHeight,
        parapetTotalLF: parapetTotalLF,
        wallType: wallType,
        terminationBarLFOverride: null,
        terminationType: terminationType,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParapetWalls &&
          hasParapetWalls == other.hasParapetWalls &&
          parapetHeight == other.parapetHeight &&
          parapetTotalLF == other.parapetTotalLF &&
          wallType == other.wallType &&
          terminationBarLFOverride == other.terminationBarLFOverride &&
          terminationType == other.terminationType;

  @override
  int get hashCode => Object.hash(
        hasParapetWalls, parapetHeight, parapetTotalLF,
        wallType, terminationBarLFOverride, terminationType,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// PENETRATIONS  (section 7)
// ═══════════════════════════════════════════════════════════════════════════════

const List<String> kDrainTypes = ['Standard', 'Overflow', 'Retrofit'];

class RTUDetail {
  final double length;  // feet
  final double width;   // feet
  final double height;  // inches

  const RTUDetail({
    this.length = 0.0,
    this.width = 0.0,
    this.height = 0.0,
  });

  /// Curb perimeter LF: 2 × (length + width).
  double get perimeterLF => 2 * (length + width);

  RTUDetail copyWith({double? length, double? width, double? height}) =>
      RTUDetail(
        length: length ?? this.length,
        width: width ?? this.width,
        height: height ?? this.height,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RTUDetail &&
          length == other.length &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(length, width, height);
}

class Penetrations {
  // RTUs
  final double rtuTotalLF;          // total curb perimeter LF (all RTUs)
  final List<RTUDetail> rtuDetails; // optional per-unit dimensions

  // Drains — count comes from RoofGeometry; type set here
  final String drainType;           // from kDrainTypes

  // Pipes
  final int smallPipeCount;  // 1–4" diameter
  final int largePipeCount;  // 4–12" diameter

  // Other penetrations
  final int skylightCount;
  final int scupperCount;
  final double expansionJointLF;
  final int pitchPanCount;

  const Penetrations({
    this.rtuTotalLF = 0.0,
    this.rtuDetails = const [],
    this.drainType = 'Standard',
    this.smallPipeCount = 0,
    this.largePipeCount = 0,
    this.skylightCount = 0,
    this.scupperCount = 0,
    this.expansionJointLF = 0.0,
    this.pitchPanCount = 0,
  });

  factory Penetrations.initial() => const Penetrations();

  Penetrations copyWith({
    double? rtuTotalLF,
    List<RTUDetail>? rtuDetails,
    String? drainType,
    int? smallPipeCount,
    int? largePipeCount,
    int? skylightCount,
    int? scupperCount,
    double? expansionJointLF,
    int? pitchPanCount,
  }) {
    return Penetrations(
      rtuTotalLF: rtuTotalLF ?? this.rtuTotalLF,
      rtuDetails: rtuDetails ?? List.from(this.rtuDetails),
      drainType: drainType ?? this.drainType,
      smallPipeCount: smallPipeCount ?? this.smallPipeCount,
      largePipeCount: largePipeCount ?? this.largePipeCount,
      skylightCount: skylightCount ?? this.skylightCount,
      scupperCount: scupperCount ?? this.scupperCount,
      expansionJointLF: expansionJointLF ?? this.expansionJointLF,
      pitchPanCount: pitchPanCount ?? this.pitchPanCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Penetrations &&
          rtuTotalLF == other.rtuTotalLF &&
          _listEquals(rtuDetails, other.rtuDetails) &&
          drainType == other.drainType &&
          smallPipeCount == other.smallPipeCount &&
          largePipeCount == other.largePipeCount &&
          skylightCount == other.skylightCount &&
          scupperCount == other.scupperCount &&
          expansionJointLF == other.expansionJointLF &&
          pitchPanCount == other.pitchPanCount;

  @override
  int get hashCode => Object.hash(
        rtuTotalLF, Object.hashAll(rtuDetails), drainType,
        smallPipeCount, largePipeCount, skylightCount,
        scupperCount, expansionJointLF, pitchPanCount,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// METAL SCOPE  (section 8)
// ═══════════════════════════════════════════════════════════════════════════════

const List<String> kCopingWidths = ['8"', '10"', '12"', '14"', '16"'];
const List<String> kEdgeMetalTypes = ['ES-1', 'Gravel Stop', 'Drip Edge'];
const List<String> kGutterSizes = ['5"', '6"', '7"', '8"'];

// Edge type → metal bucket mapping
// Wall Flashing: Parapet, Headwall, Clerestory
// Drip Edge: Eave, Flat Drip Edge, Rake Edge, Hip, Valley, Ridge
const Set<String> kWallFlashingEdgeTypes = {'Parapet', 'Headwall', 'Clerestory'};

class MetalScope {
  // Coping
  final String copingWidth;  // from kCopingWidths
  final double copingLF;

  // Edge metal — 3 separate fields
  final double wallFlashingLF;   // Parapet/Headwall/Clerestory edges
  final double dripEdgeLF;       // Eave/Flat Drip Edge/Rake/Hip/Valley/Ridge edges
  final double otherEdgeMetalLF; // Manual entry for anything else
  final String edgeMetalType;    // kept for BOM labeling (ES-1, Gravel Stop, Drip Edge)

  // Gutters
  final String gutterSize;    // from kGutterSizes
  final double gutterLF;
  final int downspoutCount;

  // Convenience: total edge metal
  double get edgeMetalLF => wallFlashingLF + dripEdgeLF + otherEdgeMetalLF;

  const MetalScope({
    this.copingWidth = '12"',
    this.copingLF = 0.0,
    this.wallFlashingLF = 0.0,
    this.dripEdgeLF = 0.0,
    this.otherEdgeMetalLF = 0.0,
    this.edgeMetalType = 'ES-1',
    this.gutterSize = '6"',
    this.gutterLF = 0.0,
    this.downspoutCount = 0,
  });

  factory MetalScope.initial() => const MetalScope();

  MetalScope copyWith({
    String? copingWidth,
    double? copingLF,
    double? wallFlashingLF,
    double? dripEdgeLF,
    double? otherEdgeMetalLF,
    String? edgeMetalType,
    String? gutterSize,
    double? gutterLF,
    int? downspoutCount,
  }) {
    return MetalScope(
      copingWidth: copingWidth ?? this.copingWidth,
      copingLF: copingLF ?? this.copingLF,
      wallFlashingLF: wallFlashingLF ?? this.wallFlashingLF,
      dripEdgeLF: dripEdgeLF ?? this.dripEdgeLF,
      otherEdgeMetalLF: otherEdgeMetalLF ?? this.otherEdgeMetalLF,
      edgeMetalType: edgeMetalType ?? this.edgeMetalType,
      gutterSize: gutterSize ?? this.gutterSize,
      gutterLF: gutterLF ?? this.gutterLF,
      downspoutCount: downspoutCount ?? this.downspoutCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetalScope &&
          copingWidth == other.copingWidth &&
          copingLF == other.copingLF &&
          wallFlashingLF == other.wallFlashingLF &&
          dripEdgeLF == other.dripEdgeLF &&
          otherEdgeMetalLF == other.otherEdgeMetalLF &&
          edgeMetalType == other.edgeMetalType &&
          gutterSize == other.gutterSize &&
          gutterLF == other.gutterLF &&
          downspoutCount == other.downspoutCount;

  @override
  int get hashCode => Object.hash(
        copingWidth, copingLF, wallFlashingLF, dripEdgeLF,
        otherEdgeMetalLF, edgeMetalType, gutterSize, gutterLF, downspoutCount,
      );
}

// ─── SHARED UTILITY ───────────────────────────────────────────────────────────

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
