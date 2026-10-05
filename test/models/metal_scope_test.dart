import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/services/serialization.dart';

void main() {
  test('dripEdgeLF sums the three buckets', () {
    const m = MetalScope(eaveLF: 100, rakeLF: 50, flatDripLF: 25);
    expect(m.dripEdgeLF, 175);
    expect(m.nailerLF, 175);
  });

  test('defaults', () {
    const m = MetalScope();
    expect(m.eaveMetalType, 'TPO-Coated Drip Edge');
    expect(m.hasNailers, false);
    expect(m.nailerWidth, '2x6');
  });

  test('legacy dripEdgeLF/edgeMetalType migrate to eave + all types', () {
    final m = metalScopeFromJson({'dripEdgeLF': 300.0, 'edgeMetalType': 'Gravel Stop'});
    expect(m.eaveLF, 300);
    expect(m.rakeLF, 0);
    expect(m.eaveMetalType, 'Gravel Stop');
    expect(m.rakeMetalType, 'Gravel Stop');
    expect(m.flatDripMetalType, 'Gravel Stop');
  });

  test('round trip', () {
    const m = MetalScope(eaveLF: 10, rakeLF: 20, flatDripLF: 30,
        rakeMetalType: 'ES-1 (Low Profile)', hasNailers: true, nailerWidth: '2x8');
    expect(metalScopeFromJson(metalScopeToJson(m)), m);
  });
}
