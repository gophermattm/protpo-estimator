import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/services/bom_calculator.dart';
import 'package:protpo_app/services/sub_instructions_builder.dart';

void main() {
  const hw = ParapetWalls(headwallHeight: 24, headwallLF: 60,
      terminationType: 'Termination Bar');

  test('headwall: LF, height, termination, VersiWeld adhesive, RUSS for MA', () {
    final l = headwallInstructionLines(hw, isMA: true);
    expect(l.first, contains('60 LF'));
    expect(l.first, contains('24" height'));
    expect(l.any((s) => s.contains('RUSS')), isTrue);
    expect(l.any((s) => s.contains('VersiWeld bonding adhesive')), isTrue);
    expect(l.any((s) => s.contains('Terminate with termination bar at 24" height')), isTrue);
  });

  test('headwall: no RUSS when not MA; CAV-Grip when selected', () {
    final l = headwallInstructionLines(
        hw.copyWith(parapetAdhesiveType: kAdhesiveCavGrip), isMA: false);
    expect(l.any((s) => s.contains('RUSS')), isFalse);
    expect(l.any((s) => s.contains('CAV-Grip')), isTrue);
  });

  test('headwall: short wall with term bar omits adhesive, like the BOM', () {
    final short = hw.copyWith(headwallHeight: 18);
    expect(wallAdhesiveOmitted(18, 'Termination Bar'), isTrue);
    final l = headwallInstructionLines(short, isMA: true);
    expect(l.any((s) => s.contains('No wall flashing adhesive')), isTrue);
    expect(l.any((s) => s.contains('Adhere TPO flashing')), isFalse);
  });

  test('edge fastener text constants match the BOM line', () {
    expect(BomCalculator.edgeMetalFastenerSpacingIn, 4.0);
    expect(BomCalculator.edgeMetalFastenerNamePublic('Metal', true), 'Versico HPV');
    expect(BomCalculator.edgeMetalFastenerNamePublic('Metal', false), 'Versico HPVX');
  });
}
