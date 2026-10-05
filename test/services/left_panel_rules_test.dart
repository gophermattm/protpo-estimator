// Pure rules shared by the left panel, the AI actions and the BOM.
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/services/bom_calculator.dart';

void main() {
  group('snapCoverBoardThickness', () {
    test('keeps a thickness offered for the type', () {
      expect(snapCoverBoardThickness('HD Polyiso', 0.625), 0.625);
      expect(snapCoverBoardThickness(kCoverBoardNailbase, 3.0), 3.0);
    });
    test('snaps a standard thickness to the first nailbase thickness', () {
      expect(snapCoverBoardThickness(kCoverBoardNailbase, 0.5), 1.5);
    });
    test('snaps a nailbase thickness back to the first standard thickness', () {
      expect(snapCoverBoardThickness('Gypsum', 2.5), 0.25);
    });
    test('null falls back to the first allowed thickness', () {
      expect(snapCoverBoardThickness('DensDeck', null), 0.25);
    });
  });

  group('wallAdhesiveOmitted', () {
    test('omitted at 12" or less for any termination', () {
      expect(wallAdhesiveOmitted(12, 'TPO Coated Drip Edge'), isTrue);
      expect(wallAdhesiveOmitted(0, 'Termination Bar'), isTrue);
    });
    test('omitted up to 18" with a termination bar only', () {
      expect(wallAdhesiveOmitted(18, 'Termination Bar'), isTrue);
      expect(wallAdhesiveOmitted(18, 'TPO Coated Drip Edge'), isFalse);
    });
    test('required above 18"', () {
      expect(wallAdhesiveOmitted(24, 'Termination Bar'), isFalse);
    });
  });
}
