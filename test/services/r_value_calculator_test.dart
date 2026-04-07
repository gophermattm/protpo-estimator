import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/r_value_calculator.dart';

void main() {
  group('RValueCalculator.calculate (existing behavior)', () {
    test('single layer polyiso 2.5"', () {
      final result = RValueCalculator.calculate(
        layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.5),
      );
      // 2.5 × 5.7 + 0.5 membrane = 14.75
      expect(result.totalRValue, closeTo(14.75, 0.1));
    });
  });

  group('RValueCalculator.calculateTapered', () {
    test('47x27 test case — full assembly R-values', () {
      final result = RValueCalculator.calculateTapered(
        layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.5),
        layer2: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.0),
        coverBoard: const CoverBoardInput(materialType: 'HD Polyiso', thickness: 0.5),
        taperMinThickness: 1.0,
        taperAvgThickness: 6.875,
        taperMaxThickness: 12.75,
      );

      // Base layers: (2.5 + 2.0) × 5.7 = 25.65
      // Cover: 0.5 × 5.7 = 2.85
      // Membrane: 0.5
      // Uniform total: 29.0

      // Min total: 29.0 + 1.0 × 5.7 = 34.7
      expect(result.totalMinR, closeTo(34.7, 0.1));
      // Avg total: 29.0 + 6.875 × 5.7 = 68.19
      expect(result.totalAvgR, closeTo(68.2, 0.2));
      // Max total: 29.0 + 12.75 × 5.7 = 101.68
      expect(result.totalMaxR, closeTo(101.7, 0.2));
    });

    test('no base layers — taper only', () {
      final result = RValueCalculator.calculateTapered(
        layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 0.0),
        taperMinThickness: 1.0,
        taperAvgThickness: 3.0,
        taperMaxThickness: 5.0,
      );
      // Min: 0.5 + 1.0 × 5.7 = 6.2
      expect(result.totalMinR, closeTo(6.2, 0.1));
    });

    test('component R-values are accessible', () {
      final result = RValueCalculator.calculateTapered(
        layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.5),
        taperMinThickness: 1.0,
        taperAvgThickness: 4.0,
        taperMaxThickness: 7.0,
      );
      expect(result.taperMinR, closeTo(5.7, 0.1));
      expect(result.taperAvgR, closeTo(22.8, 0.1));
      expect(result.taperMaxR, closeTo(39.9, 0.1));
      expect(result.baseLayersR, closeTo(14.25, 0.1));
      expect(result.membraneR, 0.5);
    });

    test('uniformR getter sums base + cover + membrane', () {
      final result = RValueCalculator.calculateTapered(
        layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.5),
        layer2: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.0),
        coverBoard: const CoverBoardInput(materialType: 'HD Polyiso', thickness: 0.5),
        taperMinThickness: 1.0,
        taperAvgThickness: 1.0,
        taperMaxThickness: 1.0,
      );
      // (2.5+2.0)×5.7 + 0.5×5.7 + 0.5 = 25.65 + 2.85 + 0.5 = 29.0
      expect(result.uniformR, closeTo(29.0, 0.1));
    });
  });
}
