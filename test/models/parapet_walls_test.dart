import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/services/serialization.dart';

void main() {
  test('hasHeadwall needs height and LF', () {
    expect(const ParapetWalls(headwallHeight: 24).hasHeadwall, false);
    expect(const ParapetWalls(headwallLF: 50).hasHeadwall, false);
    expect(const ParapetWalls(headwallHeight: 24, headwallLF: 50).hasHeadwall, true);
  });

  test('wallTermBarLF adds headwall to parapet term bar', () {
    const p = ParapetWalls(hasParapetWalls: true, parapetHeight: 30, parapetTotalLF: 100,
        headwallHeight: 24, headwallLF: 50);
    expect(p.wallTermBarLF, 150);
    expect(const ParapetWalls(headwallHeight: 24, headwallLF: 50).wallTermBarLF, 50);
  });

  test('copyWith keeps headwall fields', () {
    const p = ParapetWalls(headwallHeight: 24, headwallLF: 50);
    final q = p.copyWith(parapetHeight: 10);
    expect(q.headwallHeight, 24);
    expect(q.headwallLF, 50);
    expect(p.clearTerminationBarOverride().headwallLF, 50);
  });

  test('round trip and legacy default', () {
    const p = ParapetWalls(headwallHeight: 24, headwallLF: 50);
    expect(parapetWallsFromJson(parapetWallsToJson(p)), p);
    expect(parapetWallsFromJson({}).headwallLF, 0);
  });
}
