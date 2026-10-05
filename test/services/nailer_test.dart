import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/section_models.dart';
import 'bom_test_helpers.dart';

void main() {
  const metal = MetalScope(eaveLF: 400, hasNailers: true);

  test('400 LF, 2.5" stack → 2 plies, 55 boards 2x6 × 16\'', () {
    final r = calc(metal: metal); // default layer 1: 2.5" polyiso
    final lum = r.items.singleWhere((i) => i.skuKey == 'lumber_nailer');
    expect(lum.name, 'Pressure-Treated Lumber 2x6 × 16\' — Perimeter Nailer');
    expect(lum.orderQty, (400 * 2 / 16 * (1 + 0.10)).ceil());
    expect(lum.trace.breakdown.any((b) => b.contains('Plies: 2')), true);
  });

  test('fasteners: 2 rows @ 12" o.c. per ply, Needs Validation note', () {
    final r = calc(metal: metal);
    final f = r.items.singleWhere((i) => i.skuKey == 'fastener_nailer');
    expect(f.trace.baseQty, 1600); // 400 × 2 rows × 2 plies
    expect(f.unit, 'cartons');
    expect(f.notes, contains('Needs Validation for nailer fastener spacing'));
  });

  test('taper adds height Needs Validation warning', () {
    final r = calc(metal: metal, insulation: const InsulationSystem().withTaperEnabled());
    expect(r.warnings.any((w) => w.contains('Needs Validation for nailer height at tapered high edges')), true);
  });

  test('off by default', () {
    expect(calc(metal: const MetalScope(eaveLF: 400)).items.any((i) => i.skuKey == 'lumber_nailer'), false);
  });
}
