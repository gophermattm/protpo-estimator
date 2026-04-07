/// ProTPO R-Value Calculation Engine
/// Location: lib/services/r_value_calculator.dart
///
/// All formulas derived from INPUT_SPECIFICATIONS.md.
/// R/inch values are mid-point of published ranges unless noted.
/// Code compliance thresholds are IECC 2021 by climate zone.

// ─── R/INCH LOOKUP TABLE ──────────────────────────────────────────────────────

/// Returns the R-value per inch for a given insulation material.
/// Values are mid-point of published manufacturer ranges.
/// [Inference] Exact values vary by manufacturer and product line —
/// these are standard industry reference values.
double rValuePerInch(String materialType) {
  switch (materialType.trim()) {
    case 'Polyiso':
      return 5.7; // Conservative end of 5.7–6.0 range (aged in-situ)
    case 'EPS':
      return 4.0; // Mid-point of 3.8–4.2 range
    case 'XPS':
      return 5.0; // Fixed per ASTM C578
    case 'Mineral Wool':
      return 4.1; // Mid-point of 4.0–4.2 range
    case 'HD Polyiso': // Cover board grade
      return 5.7;
    case 'Gypsum': // Cover board
      return 0.9;
    case 'DensDeck':
      return 1.0;
    case 'DensDeck Prime':
      return 1.0;
    default:
      return 0.0; // Unknown material — caller should validate
  }
}

// ─── DATA CLASSES ─────────────────────────────────────────────────────────────

class InsulationLayerInput {
  final String materialType; // e.g. 'Polyiso', 'EPS', 'XPS', 'Mineral Wool'
  final double thickness; // inches

  const InsulationLayerInput({
    required this.materialType,
    required this.thickness,
  });
}

class TaperedInsulationInput {
  final String materialType; // e.g. 'Polyiso'
  final double minThicknessAtDrain; // inches — thinnest point
  final double maxThickness; // inches — thickest point
  // Average R is calculated as the arithmetic mean of min/max R-values.
  // This is a standard industry approximation for tapered systems.

  const TaperedInsulationInput({
    required this.materialType,
    required this.minThicknessAtDrain,
    required this.maxThickness,
  });
}

class CoverBoardInput {
  final String materialType; // e.g. 'HD Polyiso', 'Gypsum', 'DensDeck'
  final double thickness; // inches

  const CoverBoardInput({
    required this.materialType,
    required this.thickness,
  });
}

// ─── RESULT CLASSES ───────────────────────────────────────────────────────────

class LayerRValueResult {
  final String materialType;
  final double thickness;
  final double rPerInch;
  final double rValue;

  const LayerRValueResult({
    required this.materialType,
    required this.thickness,
    required this.rPerInch,
    required this.rValue,
  });

  /// Human-readable breakdown string for "Hover Math" display.
  String get mathString =>
      '${thickness}" × R-${rPerInch.toStringAsFixed(1)}/in = R-${rValue.toStringAsFixed(1)}';
}

class TaperedRValueResult {
  final String materialType;
  final double minThickness;
  final double maxThickness;
  final double avgThickness;
  final double rPerInch;
  final double averageRValue;

  const TaperedRValueResult({
    required this.materialType,
    required this.minThickness,
    required this.maxThickness,
    required this.avgThickness,
    required this.rPerInch,
    required this.averageRValue,
  });

  String get mathString =>
      'avg(${minThickness}" + ${maxThickness}") ÷ 2 = ${avgThickness.toStringAsFixed(2)}" × R-${rPerInch.toStringAsFixed(1)}/in = R-${averageRValue.toStringAsFixed(1)}';
}

class TaperedAssemblyResult {
  final double baseLayersR;
  final double coverBoardR;
  final double membraneR;
  final double taperMinR;
  final double taperAvgR;
  final double taperMaxR;

  double get uniformR => baseLayersR + coverBoardR + membraneR;
  double get totalMinR => uniformR + taperMinR;
  double get totalAvgR => uniformR + taperAvgR;
  double get totalMaxR => uniformR + taperMaxR;

  const TaperedAssemblyResult({
    required this.baseLayersR,
    required this.coverBoardR,
    required this.membraneR,
    required this.taperMinR,
    required this.taperAvgR,
    required this.taperMaxR,
  });
}

class RValueResult {
  // Individual component results
  final LayerRValueResult layer1;
  final LayerRValueResult? layer2;
  final TaperedRValueResult? tapered;
  final LayerRValueResult? coverBoard;
  final double membraneContribution; // Always 0.5

  // Totals
  final double totalRValue;

  // Code compliance
  final double? requiredRValue; // null if ZIP not entered
  final bool? meetsCodeRequirement; // null if requiredRValue is null

  const RValueResult({
    required this.layer1,
    this.layer2,
    this.tapered,
    this.coverBoard,
    this.membraneContribution = 0.5,
    required this.totalRValue,
    this.requiredRValue,
    this.meetsCodeRequirement,
  });

  /// Full "Hover Math" breakdown as a list of labeled lines.
  List<Map<String, String>> get breakdown {
    final lines = <Map<String, String>>[];

    lines.add({
      'label': 'Layer 1 (${layer1.materialType})',
      'math': layer1.mathString,
      'value': 'R-${layer1.rValue.toStringAsFixed(1)}',
    });

    if (layer2 != null) {
      lines.add({
        'label': 'Layer 2 (${layer2!.materialType})',
        'math': layer2!.mathString,
        'value': 'R-${layer2!.rValue.toStringAsFixed(1)}',
      });
    }

    if (tapered != null) {
      lines.add({
        'label': 'Tapered (${tapered!.materialType})',
        'math': tapered!.mathString,
        'value': 'R-${tapered!.averageRValue.toStringAsFixed(1)}',
      });
    }

    if (coverBoard != null) {
      lines.add({
        'label': 'Cover Board (${coverBoard!.materialType})',
        'math': coverBoard!.mathString,
        'value': 'R-${coverBoard!.rValue.toStringAsFixed(1)}',
      });
    }

    lines.add({
      'label': 'Membrane',
      'math': 'Fixed contribution',
      'value': 'R-${membraneContribution.toStringAsFixed(1)}',
    });

    lines.add({
      'label': 'TOTAL',
      'math': '',
      'value': 'R-${totalRValue.toStringAsFixed(1)}',
    });

    if (requiredRValue != null) {
      lines.add({
        'label': 'Code Required',
        'math': meetsCodeRequirement == true ? '✓ Compliant' : '✗ Below minimum',
        'value': 'R-${requiredRValue!.toStringAsFixed(0)}',
      });
    }

    return lines;
  }
}

// ─── CALCULATOR ───────────────────────────────────────────────────────────────

class RValueCalculator {
  /// Calculate total R-value for a roofing assembly.
  ///
  /// [layer1]           Required. Primary insulation layer.
  /// [layer2]           Optional. Second insulation layer.
  /// [tapered]          Optional. Tapered insulation system.
  /// [coverBoard]       Optional. Cover board on top of insulation.
  /// [requiredRValue]   Optional. Code minimum from ZIP lookup.
  ///                    Pass null if ZIP has not been entered yet.
  static RValueResult calculate({
    required InsulationLayerInput layer1,
    InsulationLayerInput? layer2,
    TaperedInsulationInput? tapered,
    CoverBoardInput? coverBoard,
    double? requiredRValue,
  }) {
    // Layer 1
    final r1PerInch = rValuePerInch(layer1.materialType);
    final r1 = layer1.thickness * r1PerInch;
    final layer1Result = LayerRValueResult(
      materialType: layer1.materialType,
      thickness: layer1.thickness,
      rPerInch: r1PerInch,
      rValue: r1,
    );

    // Layer 2
    LayerRValueResult? layer2Result;
    double r2 = 0;
    if (layer2 != null) {
      final r2PerInch = rValuePerInch(layer2.materialType);
      r2 = layer2.thickness * r2PerInch;
      layer2Result = LayerRValueResult(
        materialType: layer2.materialType,
        thickness: layer2.thickness,
        rPerInch: r2PerInch,
        rValue: r2,
      );
    }

    // Tapered insulation — average R-value method
    // Average thickness = (min + max) / 2
    TaperedRValueResult? taperedResult;
    double rTapered = 0;
    if (tapered != null) {
      final taperedRPerInch = rValuePerInch(tapered.materialType);
      final avgThickness = (tapered.minThicknessAtDrain + tapered.maxThickness) / 2;
      rTapered = avgThickness * taperedRPerInch;
      taperedResult = TaperedRValueResult(
        materialType: tapered.materialType,
        minThickness: tapered.minThicknessAtDrain,
        maxThickness: tapered.maxThickness,
        avgThickness: avgThickness,
        rPerInch: taperedRPerInch,
        averageRValue: rTapered,
      );
    }

    // Cover board
    LayerRValueResult? coverBoardResult;
    double rCover = 0;
    if (coverBoard != null) {
      final rCoverPerInch = rValuePerInch(coverBoard.materialType);
      rCover = coverBoard.thickness * rCoverPerInch;
      coverBoardResult = LayerRValueResult(
        materialType: coverBoard.materialType,
        thickness: coverBoard.thickness,
        rPerInch: rCoverPerInch,
        rValue: rCover,
      );
    }

    // Membrane fixed contribution
    const double membraneR = 0.5;

    // Total
    final total = r1 + r2 + rTapered + rCover + membraneR;

    // Code compliance
    bool? meetsCode;
    if (requiredRValue != null) {
      meetsCode = total >= requiredRValue;
    }

    return RValueResult(
      layer1: layer1Result,
      layer2: layer2Result,
      tapered: taperedResult,
      coverBoard: coverBoardResult,
      membraneContribution: membraneR,
      totalRValue: total,
      requiredRValue: requiredRValue,
      meetsCodeRequirement: meetsCode,
    );
  }

  static TaperedAssemblyResult calculateTapered({
    required InsulationLayerInput layer1,
    InsulationLayerInput? layer2,
    CoverBoardInput? coverBoard,
    required double taperMinThickness,
    required double taperAvgThickness,
    required double taperMaxThickness,
  }) {
    final r1 = layer1.thickness * rValuePerInch(layer1.materialType);
    final r2 = layer2 != null
        ? layer2.thickness * rValuePerInch(layer2.materialType)
        : 0.0;
    final rCover = coverBoard != null
        ? coverBoard.thickness * rValuePerInch(coverBoard.materialType)
        : 0.0;
    const rMembrane = 0.5;
    const taperRPerInch = 5.7; // All tapered panels are polyiso

    return TaperedAssemblyResult(
      baseLayersR: r1 + r2,
      coverBoardR: rCover,
      membraneR: rMembrane,
      taperMinR: taperMinThickness * taperRPerInch,
      taperAvgR: taperAvgThickness * taperRPerInch,
      taperMaxR: taperMaxThickness * taperRPerInch,
    );
  }

  // ─── IECC 2021 MINIMUM R-VALUE BY CLIMATE ZONE ──────────────────────────────
  // Source: IECC 2021 Table C402.1.3 — Roof/ceiling continuous insulation
  // [Inference] Values below are for standard commercial roof assemblies.
  // Local amendments may require higher R-values — verify with AHJ.

  static const Map<String, double> _iecc2021MinR = {
    'Zone 1': 15.0,
    'Zone 2': 20.0,
    'Zone 3': 20.0,
    'Zone 4': 25.0,
    'Zone 5': 25.0,
    'Zone 6': 25.0,
    'Zone 7': 30.0,
    'Zone 8': 35.0,
  };

  /// Returns the IECC 2021 minimum R-value for a given climate zone string.
  /// Accepts formats like 'Zone 4', 'Zone 4 (estimated)', '4', etc.
  /// Returns null if the zone string cannot be parsed.
  static double? requiredRForZone(String? climateZone) {
    if (climateZone == null || climateZone.isEmpty) return null;

    // Normalize: extract the first digit found in the string
    final match = RegExp(r'\d').firstMatch(climateZone);
    if (match == null) return null;

    final zoneKey = 'Zone ${match.group(0)}';
    return _iecc2021MinR[zoneKey];
  }

  // ─── VALIDATION ──────────────────────────────────────────────────────────────

  /// Returns a list of validation messages for a given assembly.
  /// Empty list = no issues.
  static List<ValidationMessage> validate({
    required InsulationLayerInput layer1,
    InsulationLayerInput? layer2,
    TaperedInsulationInput? tapered,
    CoverBoardInput? coverBoard,
    double? requiredRValue,
  }) {
    final messages = <ValidationMessage>[];

    // Blocker: zero thickness on required layer
    if (layer1.thickness <= 0) {
      messages.add(ValidationMessage(
        type: ValidationMessageType.blocker,
        code: 'MISSING_LAYER1_THICKNESS',
        text: 'Layer 1 thickness must be greater than 0.',
      ));
    }

    // Blocker: unknown material
    if (rValuePerInch(layer1.materialType) == 0.0) {
      messages.add(ValidationMessage(
        type: ValidationMessageType.blocker,
        code: 'UNKNOWN_LAYER1_MATERIAL',
        text: 'Layer 1 material "${layer1.materialType}" is not recognized.',
      ));
    }

    if (layer2 != null) {
      if (layer2.thickness <= 0) {
        messages.add(ValidationMessage(
          type: ValidationMessageType.blocker,
          code: 'MISSING_LAYER2_THICKNESS',
          text: 'Layer 2 is selected but thickness is 0.',
        ));
      }
      if (rValuePerInch(layer2.materialType) == 0.0) {
        messages.add(ValidationMessage(
          type: ValidationMessageType.blocker,
          code: 'UNKNOWN_LAYER2_MATERIAL',
          text: 'Layer 2 material "${layer2.materialType}" is not recognized.',
        ));
      }
    }

    if (tapered != null) {
      if (tapered.minThicknessAtDrain <= 0) {
        messages.add(ValidationMessage(
          type: ValidationMessageType.blocker,
          code: 'MISSING_TAPER_MIN_THICKNESS',
          text: 'Tapered insulation minimum thickness must be greater than 0.',
        ));
      }
      if (tapered.maxThickness <= tapered.minThicknessAtDrain) {
        messages.add(ValidationMessage(
          type: ValidationMessageType.blocker,
          code: 'INVALID_TAPER_RANGE',
          text:
              'Tapered max thickness must be greater than min thickness at drain.',
        ));
      }
    }

    if (coverBoard != null) {
      if (coverBoard.thickness <= 0) {
        messages.add(ValidationMessage(
          type: ValidationMessageType.blocker,
          code: 'MISSING_COVERBOARD_THICKNESS',
          text: 'Cover board is selected but thickness is 0.',
        ));
      }
    }

    // Warning: R-value below code minimum
    if (requiredRValue != null && messages.isEmpty) {
      final result = calculate(
        layer1: layer1,
        layer2: layer2,
        tapered: tapered,
        coverBoard: coverBoard,
        requiredRValue: requiredRValue,
      );
      if (result.meetsCodeRequirement == false) {
        final deficit = requiredRValue - result.totalRValue;
        messages.add(ValidationMessage(
          type: ValidationMessageType.warning,
          code: 'R_VALUE_BELOW_CODE',
          text:
              'Assembly R-${result.totalRValue.toStringAsFixed(1)} is below the required R-${requiredRValue.toStringAsFixed(0)}. '
              'Deficit: R-${deficit.toStringAsFixed(1)}.',
        ));
      }
    }

    return messages;
  }
}

// ─── VALIDATION TYPES ─────────────────────────────────────────────────────────

enum ValidationMessageType { blocker, warning }

class ValidationMessage {
  final ValidationMessageType type;
  final String code;
  final String text;

  const ValidationMessage({
    required this.type,
    required this.code,
    required this.text,
  });

  bool get isBlocker => type == ValidationMessageType.blocker;
  bool get isWarning => type == ValidationMessageType.warning;
}