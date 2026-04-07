import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/data/board_schedules.dart';

void main() {
  group('TaperedPanel', () {
    test('constructs with correct properties', () {
      const panel = TaperedPanel(
        letter: 'X',
        thinEdge: 0.5,
        thickEdge: 1.5,
        avgThickness: 1.0,
        rPerInchLTTR: 5.7,
      );
      expect(panel.letter, 'X');
      expect(panel.thinEdge, 0.5);
      expect(panel.thickEdge, 1.5);
      expect(panel.avgThickness, 1.0);
      expect(panel.rPerInchLTTR, 5.7);
    });
  });

  group('PanelSequence', () {
    test('sequenceRise is thickEdge of last minus thinEdge of first', () {
      const panels = [
        TaperedPanel(letter: 'X', thinEdge: 0.5, thickEdge: 1.5, avgThickness: 1.0, rPerInchLTTR: 5.7),
        TaperedPanel(letter: 'Y', thinEdge: 1.5, thickEdge: 2.5, avgThickness: 2.0, rPerInchLTTR: 5.7),
      ];
      const seq = PanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/4:12',
        profileType: 'standard',
        panels: panels,
      );
      expect(seq.sequenceRise, closeTo(2.0, 0.001)); // 2.5 - 0.5
    });
  });

  group('kFlatStockThicknesses', () {
    test('contains expected thicknesses', () {
      expect(kFlatStockThicknesses, [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]);
    });
  });

  group('lookupPanelSequence', () {
    test('Versico 1/4 extended returns X Y Z ZZ (4 panels)', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/4:12',
        profileType: 'extended',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 4);
      expect(seq.panels.map((p) => p.letter).toList(), ['X', 'Y', 'Z', 'ZZ']);
    });

    test('Versico 1/4 standard returns X Y (2 panels)', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/4:12',
        profileType: 'standard',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 2);
      expect(seq.panels.map((p) => p.letter).toList(), ['X', 'Y']);
    });

    test('Versico 1/8 extended returns AA A B C D E F FF (8 panels)', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/8:12',
        profileType: 'extended',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 8);
      expect(seq.panels.map((p) => p.letter).toList(),
          ['AA', 'A', 'B', 'C', 'D', 'E', 'F', 'FF']);
    });

    test('Versico 1/8 standard returns AA A B C (4 panels)', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/8:12',
        profileType: 'standard',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 4);
      expect(seq.panels.map((p) => p.letter).toList(), ['AA', 'A', 'B', 'C']);
    });

    test('Versico 1/2 returns Q (1 panel)', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '1/2:12',
        profileType: 'standard',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 1);
      expect(seq.panels.map((p) => p.letter).toList(), ['Q']);
    });

    test('TRI-BUILT 1/4 standard returns X Y (2 panels)', () {
      final seq = lookupPanelSequence(
        manufacturer: 'TRI-BUILT',
        taperRate: '1/4:12',
        profileType: 'standard',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 2);
      expect(seq.panels.map((p) => p.letter).toList(), ['X', 'Y']);
    });

    test('TRI-BUILT 1/4 extended falls back to standard (2 panels)', () {
      final seq = lookupPanelSequence(
        manufacturer: 'TRI-BUILT',
        taperRate: '1/4:12',
        profileType: 'extended',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 2);
      expect(seq.profileType, 'standard');
    });

    test('TRI-BUILT 1/8 returns AA A B C (4 panels)', () {
      final seq = lookupPanelSequence(
        manufacturer: 'TRI-BUILT',
        taperRate: '1/8:12',
        profileType: 'standard',
      );
      expect(seq, isNotNull);
      expect(seq!.panels.length, 4);
      expect(seq.panels.map((p) => p.letter).toList(), ['AA', 'A', 'B', 'C']);
    });

    test('invalid manufacturer returns null', () {
      final seq = lookupPanelSequence(
        manufacturer: 'UNKNOWN_MFR',
        taperRate: '1/4:12',
        profileType: 'standard',
      );
      expect(seq, isNull);
    });

    test('invalid taper rate returns null', () {
      final seq = lookupPanelSequence(
        manufacturer: 'Versico',
        taperRate: '9/9:12',
        profileType: 'standard',
      );
      expect(seq, isNull);
    });
  });

  group('taperRateToDecimal', () {
    test('1/4:12 returns 0.25', () {
      expect(taperRateToDecimal('1/4:12'), closeTo(0.25, 0.0001));
    });

    test('1/8:12 returns 0.125', () {
      expect(taperRateToDecimal('1/8:12'), closeTo(0.125, 0.0001));
    });

    test('1/2:12 returns 0.5', () {
      expect(taperRateToDecimal('1/2:12'), closeTo(0.5, 0.0001));
    });

    test('3/8:12 returns 0.375', () {
      expect(taperRateToDecimal('3/8:12'), closeTo(0.375, 0.0001));
    });

    test('3/16:12 returns 0.1875', () {
      expect(taperRateToDecimal('3/16:12'), closeTo(0.1875, 0.0001));
    });

    test('invalid string returns 0.0', () {
      expect(taperRateToDecimal('invalid'), closeTo(0.0, 0.0001));
    });
  });

  group('availableProfileTypes', () {
    test('Versico 1/4 has standard and extended', () {
      final types = availableProfileTypes('Versico', '1/4:12');
      expect(types, containsAll(['standard', 'extended']));
      expect(types.length, 2);
    });

    test('TRI-BUILT 1/4 has standard only', () {
      final types = availableProfileTypes('TRI-BUILT', '1/4:12');
      expect(types, ['standard']);
    });
  });

  group('availableTaperRates', () {
    test('Versico has 1/8 1/4 3/8 1/2', () {
      final rates = availableTaperRates('Versico');
      expect(rates, containsAll(['1/8:12', '1/4:12', '3/8:12', '1/2:12']));
      expect(rates.length, 4);
    });

    test('TRI-BUILT has 1/8 1/4 1/2', () {
      final rates = availableTaperRates('TRI-BUILT');
      expect(rates, containsAll(['1/8:12', '1/4:12', '1/2:12']));
      expect(rates.length, 3);
    });
  });
}
