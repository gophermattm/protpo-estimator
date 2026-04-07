import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/board_schedule_calculator.dart';

void main() {
  // -----------------------------------------------------------------------
  // 47×27 test case — Versico extended 1/4:12, 1.0" min, 27' wide
  // -----------------------------------------------------------------------
  group('47×27 Versico extended 1/4:12', () {
    late BoardScheduleResult result;

    setUp(() {
      result = BoardScheduleCalculator.compute(BoardScheduleInput(
        distance: 47,
        taperRate: '1/4:12',
        minThickness: 1.0,
        manufacturer: 'Versico',
        profileType: 'extended',
        roofWidthFt: 27,
      ));
    });

    test('produces 12 rows', () {
      expect(result.rows.length, 12);
    });

    test('first row is X panel with no flat fill, thinEdge ≈ 1.0, thickEdge ≈ 2.0', () {
      final r = result.rows.first;
      expect(r.panelDesignation, 'X');
      expect(r.flatFillThickness, 0.0);
      expect(r.thinEdge, closeTo(1.0, 0.01));
      expect(r.thickEdge, closeTo(2.0, 0.01));
    });

    test('row 4 (index 3) is ZZ panel with no flat fill', () {
      final r = result.rows[3];
      expect(r.panelDesignation, 'ZZ');
      expect(r.flatFillThickness, 0.0);
    });

    test('row 5 (index 4) resets to X with flat fill > 0', () {
      final r = result.rows[4];
      expect(r.panelDesignation, 'X');
      expect(r.flatFillThickness, greaterThan(0));
    });

    test('maxThickness ≈ 12.75"', () {
      expect(result.maxThickness, closeTo(12.75, 0.01));
    });

    test('panel designation counts are correct', () {
      // 12 rows, 4-panel sequence → each letter appears 3 times
      // 3 × 7 panels wide = 21 each
      expect(result.taperedPanelCounts['X'], 21);
      expect(result.taperedPanelCounts['Y'], 21);
      expect(result.taperedPanelCounts['Z'], 21);
      expect(result.taperedPanelCounts['ZZ'], 21);
    });

    test('total tapered panels = 84', () {
      expect(result.totalTaperedPanels, 84);
    });

    test('flat fill counts by thickness', () {
      // Cycle 1 (rows 4-7): flatFill = 1 × 4.0 = 4.0  → 4 rows × 7 = 28
      // Cycle 2 (rows 8-11): flatFill = 2 × 4.0 = 8.0  → 4 rows × 7 = 28
      expect(result.flatFillCounts[4.0], 28);
      expect(result.flatFillCounts[8.0], 28);
    });

    test('total flat fill panels = 56', () {
      // 8 rows with flat fill × 7 panels wide
      expect(result.totalFlatFillPanels, 56);
    });

    test('total panels = 140', () {
      // 84 tapered + 56 flat fill
      expect(result.totalPanels, 140);
    });

    test('total panels with 10% waste = 154', () {
      // ceil(140 * 1.10) = 154
      expect(result.totalPanelsWithWaste, 154);
    });

    test('warning about max thickness > 8"', () {
      expect(result.warnings, contains(contains('8')));
    });

    test('avgTaperThickness between 5.0 and 8.0', () {
      expect(result.avgTaperThickness, greaterThan(5.0));
      expect(result.avgTaperThickness, lessThan(8.0));
    });

    test('minThicknessAtDrain equals input min', () {
      expect(result.minThicknessAtDrain, 1.0);
    });

    test('maxThicknessAtRidge equals maxThickness', () {
      expect(result.maxThicknessAtRidge, closeTo(12.75, 0.01));
    });

    test('total tapered SF based on panel area', () {
      // 84 panels × 4×4 = 1344 SF
      expect(result.totalTaperedSF, closeTo(84 * 16.0, 0.01));
    });

    test('total flat fill SF based on panel area', () {
      // 56 panels × 4×4 = 896 SF
      expect(result.totalFlatFillSF, closeTo(56 * 16.0, 0.01));
    });
  });

  // -----------------------------------------------------------------------
  // Short run — 8ft, Versico extended 1/4:12
  // -----------------------------------------------------------------------
  group('Short run 8ft Versico extended 1/4:12', () {
    late BoardScheduleResult result;

    setUp(() {
      result = BoardScheduleCalculator.compute(BoardScheduleInput(
        distance: 8,
        taperRate: '1/4:12',
        minThickness: 0.5,
        manufacturer: 'Versico',
        profileType: 'extended',
        roofWidthFt: 20,
      ));
    });

    test('produces 2 rows', () {
      expect(result.rows.length, 2);
    });

    test('first row is X, second is Y', () {
      expect(result.rows[0].panelDesignation, 'X');
      expect(result.rows[1].panelDesignation, 'Y');
    });

    test('no flat fill', () {
      for (final r in result.rows) {
        expect(r.flatFillThickness, 0.0);
      }
    });

    test('no warnings', () {
      expect(result.warnings, isEmpty);
    });
  });

  // -----------------------------------------------------------------------
  // TRI-BUILT 1/4:12 — 8ft (standard, 2-panel sequence X/Y)
  // -----------------------------------------------------------------------
  group('TRI-BUILT 1/4:12 8ft', () {
    late BoardScheduleResult result;

    setUp(() {
      result = BoardScheduleCalculator.compute(BoardScheduleInput(
        distance: 8,
        taperRate: '1/4:12',
        minThickness: 0.5,
        manufacturer: 'TRI-BUILT',
        profileType: 'standard',
        roofWidthFt: 20,
      ));
    });

    test('produces 2 rows: X and Y', () {
      expect(result.rows.length, 2);
      expect(result.rows[0].panelDesignation, 'X');
      expect(result.rows[1].panelDesignation, 'Y');
    });

    test('no flat fill', () {
      for (final r in result.rows) {
        expect(r.flatFillThickness, 0.0);
      }
    });
  });

  // -----------------------------------------------------------------------
  // TRI-BUILT 1/4:12 — 16ft (4 rows, flat fill starts at row 3)
  // -----------------------------------------------------------------------
  group('TRI-BUILT 1/4:12 16ft', () {
    late BoardScheduleResult result;

    setUp(() {
      result = BoardScheduleCalculator.compute(BoardScheduleInput(
        distance: 16,
        taperRate: '1/4:12',
        minThickness: 0.5,
        manufacturer: 'TRI-BUILT',
        profileType: 'standard',
        roofWidthFt: 20,
      ));
    });

    test('produces 4 rows', () {
      expect(result.rows.length, 4);
    });

    test('flat fill starts at row 3 (index 2, cycle 1)', () {
      expect(result.rows[0].flatFillThickness, 0.0);
      expect(result.rows[1].flatFillThickness, 0.0);
      // Row index 2 → cycle 1 (2 ~/ 2 = 1), so flat fill > 0
      expect(result.rows[2].flatFillThickness, greaterThan(0));
      expect(result.rows[3].flatFillThickness, greaterThan(0));
    });
  });

  // -----------------------------------------------------------------------
  // 1/8:12 — Versico extended 32ft (8 rows, exactly one cycle, no flat fill)
  // -----------------------------------------------------------------------
  group('Versico extended 1/8:12 32ft', () {
    late BoardScheduleResult result;

    setUp(() {
      result = BoardScheduleCalculator.compute(BoardScheduleInput(
        distance: 32,
        taperRate: '1/8:12',
        minThickness: 0.5,
        manufacturer: 'Versico',
        profileType: 'extended',
        roofWidthFt: 20,
      ));
    });

    test('produces 8 rows (AA through FF)', () {
      expect(result.rows.length, 8);
    });

    test('panel designations follow extended 1/8 sequence', () {
      expect(result.rows[0].panelDesignation, 'AA');
      expect(result.rows[7].panelDesignation, 'FF');
    });

    test('no flat fill (exactly one cycle)', () {
      for (final r in result.rows) {
        expect(r.flatFillThickness, 0.0);
      }
    });
  });

  // -----------------------------------------------------------------------
  // Edge cases
  // -----------------------------------------------------------------------
  group('Edge cases', () {
    test('distance 0 returns empty result', () {
      final result = BoardScheduleCalculator.compute(BoardScheduleInput(
        distance: 0,
        taperRate: '1/4:12',
        minThickness: 1.0,
        manufacturer: 'Versico',
        profileType: 'extended',
        roofWidthFt: 20,
      ));
      expect(result.rows, isEmpty);
      expect(result.totalPanels, 0);
    });

    test('invalid manufacturer returns empty result', () {
      final result = BoardScheduleCalculator.compute(BoardScheduleInput(
        distance: 47,
        taperRate: '1/4:12',
        minThickness: 1.0,
        manufacturer: 'INVALID',
        profileType: 'extended',
        roofWidthFt: 20,
      ));
      expect(result.rows, isEmpty);
      expect(result.totalPanels, 0);
    });

    test('partial last row (6ft): 2 rows, last row ends at 6.0', () {
      final result = BoardScheduleCalculator.compute(BoardScheduleInput(
        distance: 6,
        taperRate: '1/4:12',
        minThickness: 1.0,
        manufacturer: 'Versico',
        profileType: 'extended',
        roofWidthFt: 20,
      ));
      expect(result.rows.length, 2);
      expect(result.rows.last.distanceEnd, 6.0);
    });
  });
}
