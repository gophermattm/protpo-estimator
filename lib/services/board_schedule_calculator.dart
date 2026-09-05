import 'dart:math' as math;

import '../data/board_schedules.dart';

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

class BoardScheduleInput {
  final double distance; // feet from low point to high point
  final String taperRate; // '1/4:12' etc.
  final double minThickness; // inches at drain
  final String manufacturer; // 'Versico' | 'TRI-BUILT'
  final String profileType; // 'standard' | 'extended'
  final double roofWidthFt; // perpendicular width for panel count
  final double panelWidthFt; // default 4.0
  final double wasteFactor; // default 0.10

  const BoardScheduleInput({
    required this.distance,
    required this.taperRate,
    required this.minThickness,
    required this.manufacturer,
    required this.profileType,
    required this.roofWidthFt,
    this.panelWidthFt = 4.0,
    this.wasteFactor = 0.10,
  });
}

// ---------------------------------------------------------------------------
// Board Row
// ---------------------------------------------------------------------------

class BoardRow {
  final int row;
  final double distanceStart;
  final double distanceEnd;
  final double thinEdge;
  final double thickEdge;
  final double flatFillThickness;
  final String panelDesignation;
  final double panelThinEdge;
  final double panelThickEdge;

  const BoardRow({
    required this.row,
    required this.distanceStart,
    required this.distanceEnd,
    required this.thinEdge,
    required this.thickEdge,
    required this.flatFillThickness,
    required this.panelDesignation,
    required this.panelThinEdge,
    required this.panelThickEdge,
  });
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

class BoardScheduleResult {
  final List<BoardRow> rows;
  final double maxThickness;
  final Map<String, int> taperedPanelCounts;
  final Map<double, int> flatFillCounts;
  final int totalTaperedPanels;
  final int totalFlatFillPanels;
  final int totalPanels;
  final int totalPanelsWithWaste;
  final double totalTaperedSF;
  final double totalFlatFillSF;
  final double minThicknessAtDrain;
  final double avgTaperThickness;
  final double maxThicknessAtRidge;
  final List<String> warnings;

  const BoardScheduleResult({
    required this.rows,
    required this.maxThickness,
    required this.taperedPanelCounts,
    required this.flatFillCounts,
    required this.totalTaperedPanels,
    required this.totalFlatFillPanels,
    required this.totalPanels,
    required this.totalPanelsWithWaste,
    required this.totalTaperedSF,
    required this.totalFlatFillSF,
    required this.minThicknessAtDrain,
    required this.avgTaperThickness,
    required this.maxThicknessAtRidge,
    required this.warnings,
  });

  static const empty = BoardScheduleResult(
    rows: [],
    maxThickness: 0,
    taperedPanelCounts: {},
    flatFillCounts: {},
    totalTaperedPanels: 0,
    totalFlatFillPanels: 0,
    totalPanels: 0,
    totalPanelsWithWaste: 0,
    totalTaperedSF: 0,
    totalFlatFillSF: 0,
    minThicknessAtDrain: 0,
    avgTaperThickness: 0,
    maxThicknessAtRidge: 0,
    warnings: [],
  );
}

// ---------------------------------------------------------------------------
// Calculator
// ---------------------------------------------------------------------------

class BoardScheduleCalculator {
  BoardScheduleCalculator._();

  /// Rounds down to the nearest 0.5".
  static double _floorHalf(double v) => (v * 2).floorToDouble() / 2;

  /// Splits a total flat-fill thickness into orderable stock boards, largest
  /// first (e.g. 8.0 → [4.0, 4.0], 4.5 → [4.0, 0.5]). Stock sizes come from
  /// [kFlatStockThicknesses]. Anything below the smallest stock is dropped.
  static List<double> decomposeFlatFill(double thickness) {
    final stock = List<double>.from(kFlatStockThicknesses)
      ..sort((a, b) => b.compareTo(a));
    final out = <double>[];
    var remaining = _floorHalf(thickness);
    while (remaining >= stock.last - 1e-9) {
      final pick = stock.firstWhere((t) => t <= remaining + 1e-9);
      out.add(pick);
      remaining -= pick;
    }
    return out;
  }

  /// Core computation: builds the board schedule from [input].
  static BoardScheduleResult compute(BoardScheduleInput input) {
    if (input.distance <= 0) return BoardScheduleResult.empty;

    final sequence = lookupPanelSequence(
      manufacturer: input.manufacturer,
      taperRate: input.taperRate,
      profileType: input.profileType,
    );
    if (sequence == null) return BoardScheduleResult.empty;

    final rate = taperRateToDecimal(input.taperRate); // inches per foot
    if (rate == 0) return BoardScheduleResult.empty;

    final panelW = input.panelWidthFt;
    final numRows = (input.distance / panelW).ceil(); // rows are discrete (slope steps)
    // Keep panelsWide as a precise fraction so we ceil ONCE per letter at the end,
    // not on every row. Avoids ~5–10% over-count on roofs whose width isn't a
    // multiple of the panel width (e.g. a 50' roof with 4' panels = 12.5).
    final panelsWidePrecise = input.roofWidthFt / panelW;
    final seqLen = sequence.panels.length;
    final seqRise = sequence.sequenceRise;

    // Base flat fill: manufacturer sequences all start at the first panel's
    // thin edge (0.5" for every sequence in board_schedules.dart). If the
    // design min thickness at the drain is thicker, flat stock goes under
    // every row to make up the difference (eval F6). Rounded down to 0.5".
    final baseFill = _floorHalf(
        math.max(0.0, input.minThickness - sequence.panels.first.thinEdge));

    final rows = <BoardRow>[];
    final taperedCountsPrecise = <String, double>{};
    final flatFillCountsPrecise = <double, double>{};
    // Footprint under flat fill (each row counted once regardless of layers).
    double flatFillFootprintPrecise = 0;

    // For average taper thickness: sum of (avgThickness × panelArea) / totalArea
    double taperThicknessVolumeSum = 0;

    for (int i = 0; i < numRows; i++) {
      final rowStart = i * panelW;
      final rowEnd = math.min((i + 1) * panelW, input.distance);
      final thinEdge = input.minThickness + (rowStart * rate);
      final thickEdge = input.minThickness + (rowEnd * rate);

      final cycleNumber = i ~/ seqLen;
      final seqIndex = i % seqLen;
      final panel = sequence.panels[seqIndex];

      // Flat fill: additional flat stock needed when we cycle past the first
      // sequence. Rounded down to nearest 0.5".
      double flatFill = baseFill;
      if (cycleNumber > 0) {
        flatFill += _floorHalf(cycleNumber * seqRise);
      }

      rows.add(BoardRow(
        row: i + 1,
        distanceStart: rowStart,
        distanceEnd: rowEnd,
        thinEdge: thinEdge,
        thickEdge: thickEdge,
        flatFillThickness: flatFill,
        panelDesignation: panel.letter,
        panelThinEdge: panel.thinEdge,
        panelThickEdge: panel.thickEdge,
      ));

      // Accumulate fractional counts (ceiling applied per-letter after the loop)
      taperedCountsPrecise[panel.letter] =
          (taperedCountsPrecise[panel.letter] ?? 0) + panelsWidePrecise;

      if (flatFill > 0) {
        // Decompose into orderable stock thicknesses (eval F7): an 8.0" fill
        // is two 4.0" boards, not a single 8.0" board that does not exist.
        for (final layer in decomposeFlatFill(flatFill)) {
          flatFillCountsPrecise[layer] =
              (flatFillCountsPrecise[layer] ?? 0) + panelsWidePrecise;
        }
        flatFillFootprintPrecise += panelsWidePrecise;
      }

      // Volume accumulation for average thickness
      final rowAvg = (thinEdge + thickEdge) / 2;
      taperThicknessVolumeSum += rowAvg;
    }

    // Ceil per-letter (one rounding) instead of per-row (numRows roundings)
    final taperedCounts = <String, int>{
      for (final e in taperedCountsPrecise.entries) e.key: e.value.ceil(),
    };
    final flatFillCounts = <double, int>{
      for (final e in flatFillCountsPrecise.entries) e.key: e.value.ceil(),
    };

    final totalTapered =
        taperedCounts.values.fold<int>(0, (a, b) => a + b);
    final totalFlatFillPanels =
        flatFillCounts.values.fold<int>(0, (a, b) => a + b);
    final totalPanels = totalTapered + totalFlatFillPanels;
    final totalWithWaste = (totalPanels * (1 + input.wasteFactor)).ceil();

    final panelArea = panelW * panelW; // sq ft per panel (4×4 = 16)
    // Compute SF from the precise (pre-ceil) fractional counts so square-footage
    // reflects the actual roof area under tapered/flat-fill, not the ceiled overage.
    final taperedPanelsPrecise =
        taperedCountsPrecise.values.fold<double>(0, (a, b) => a + b);
    final totalTaperedSF = taperedPanelsPrecise * panelArea;
    final totalFlatFillSF = flatFillFootprintPrecise * panelArea;

    final maxThick = input.minThickness + (input.distance * rate);
    final avgTaper =
        numRows > 0 ? taperThicknessVolumeSum / numRows : 0.0;

    final warnings = <String>[];
    if (maxThick > 8.0) {
      warnings.add(
        'Max thickness ${maxThick.toStringAsFixed(2)}" exceeds 8.0". '
        'Consider multiple drain lines or a higher taper rate.',
      );
    }

    return BoardScheduleResult(
      rows: rows,
      maxThickness: maxThick,
      taperedPanelCounts: taperedCounts,
      flatFillCounts: flatFillCounts,
      totalTaperedPanels: totalTapered,
      totalFlatFillPanels: totalFlatFillPanels,
      totalPanels: totalPanels,
      totalPanelsWithWaste: totalWithWaste,
      totalTaperedSF: totalTaperedSF,
      totalFlatFillSF: totalFlatFillSF,
      minThicknessAtDrain: input.minThickness,
      avgTaperThickness: avgTaper,
      maxThicknessAtRidge: maxThick,
      warnings: warnings,
    );
  }
}
