import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'bom_test_helpers.dart';

void main() {
  test('one line per edge bucket with its own type', () {
    final r = calc(metal: const MetalScope(eaveLF: 200, rakeLF: 100,
        rakeMetalType: 'Gravel Stop', flatDripLF: 0));
    final lines = r.items.where((i) => i.skuKey == 'metal_drip_edge').toList();
    expect(lines.map((l) => l.name), [
      'Eave Edge Metal — TPO-Coated Drip Edge',
      'Rake Edge Metal — Gravel Stop',
    ]);
    expect(lines[1].attributes!['edgeType'], 'Rake Edge');
    expect(lines[0].trace.baseQty, closeTo(20, 0.001));
  });
}
