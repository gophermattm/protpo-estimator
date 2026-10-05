// test/services/wall_flashing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'bom_test_helpers.dart';

void main() {
  test('headwall 24" × 50 LF: flashing, adhesive (Headwall), term bar, RUSS', () {
    final r = calc(parapet: const ParapetWalls(headwallHeight: 24, headwallLF: 50,
        terminationType: 'Termination Bar'));
    final adh = r.items.singleWhere((i) => i.name.contains('(Headwall)'));
    // (24/12 + 0.33) × 50 = 116.5 sf ÷ 60 × 1.05 = 2.04 gal → 1 pail
    expect(adh.orderQty, 1);
    expect(adh.trace.baseQty, closeTo(116.5 / 60, 0.01));
    final tb = r.items.firstWhere((i) => i.name.toLowerCase().contains('termination bar'));
    expect(tb.trace.baseQty, closeTo(5, 0.001)); // 50 LF ÷ 10'
    expect(r.items.any((i) => i.name.contains('RUSS')), true); // MA default
  });

  test('headwall 12" → adhesive omitted with warning', () {
    final r = calc(parapet: const ParapetWalls(headwallHeight: 12, headwallLF: 50));
    expect(r.items.where((i) => i.name.contains('(Headwall)') && i.category == 'Adhesives & Sealants'), isEmpty);
    expect(r.warnings.any((w) => w.contains('Headwall adhesive omitted')), true);
  });

  test('parapet with LF and 0 height: no adhesive, no crash', () {
    final r = calc(parapet: const ParapetWalls(hasParapetWalls: true, parapetTotalLF: 100));
    expect(r.items.where((i) => (i.skuKey ?? '').startsWith('adhesive_')), isEmpty);
  });

  test('parapet 30" keeps its own (Parapet) line', () {
    final r = calc(parapet: const ParapetWalls(hasParapetWalls: true, parapetHeight: 30,
        parapetTotalLF: 100));
    final adh = r.items.where((i) => i.name.endsWith('(Parapet)')).toList();
    expect(adh.length, 1);
    expect(adh.single.trace.baseQty, closeTo((30 / 12 + 0.33) * 100 / 60, 0.01));
  });

  test('no walls → no RUSS, no term bar', () {
    final r = calc();
    expect(r.items.any((i) => i.name.contains('RUSS')), false);
    expect(r.items.any((i) => i.name.toLowerCase().contains('termination bar')), false);
  });

  test('headwall-only: flashing membrane includes headwall area once', () {
    bool isFlash(i) => i.name.contains('Flashing (');
    final base = calc().items.firstWhere(isFlash);
    final r = calc(parapet: const ParapetWalls(headwallHeight: 24, headwallLF: 50));
    final f = r.items.firstWhere(isFlash);
    final diffSf = (f.trace.baseQty - base.trace.baseQty);
    expect(diffSf, greaterThan(0));
    // diff * rollCoverage == 116.5; recover coverage from name "(6x100' roll, N sf)"
    final m = RegExp(r'(\d+) sf\)').firstMatch(f.name)!;
    expect(diffSf * double.parse(m.group(1)!), closeTo(116.5, 0.5));
    expect(f.trace.breakdown.any((l) => l.contains('headwall')), true);
  });

  test('headwall with CAV-GRIP: cylinder + UN-TACK both (Headwall)', () {
    final r = calc(parapet: const ParapetWalls(headwallHeight: 30, headwallLF: 100,
        parapetAdhesiveType: kAdhesiveCavGrip));
    final cyl = r.items.singleWhere((i) => i.name.contains('CAV-GRIP') && i.name.endsWith('(Headwall)'));
    final un = r.items.singleWhere((i) => i.name.contains('UN-TACK') && i.name.endsWith('(Headwall)'));
    expect(cyl.orderQty, un.orderQty);
    expect(cyl.orderQty, greaterThan(0));
  });

  test('parapet + headwall: separate adhesive, shared term bar and RUSS', () {
    final r = calc(parapet: const ParapetWalls(hasParapetWalls: true, parapetHeight: 30,
        parapetTotalLF: 100, headwallHeight: 24, headwallLF: 50,
        terminationType: 'Termination Bar'));
    expect(r.items.where((i) => i.name.endsWith('(Parapet)')).length, 1);
    expect(r.items.where((i) => i.name.endsWith('(Headwall)')).length, 1);
    final tb = r.items.firstWhere((i) => i.name.toLowerCase().contains('termination bar'));
    expect(tb.trace.baseQty, closeTo(15, 0.001));
    final russ = r.items.firstWhere((i) => i.name.contains('RUSS Strip'));
    expect(russ.trace.baseQty, closeTo(1.5, 0.001)); // 150 LF / 100'
  });
}
