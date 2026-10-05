import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/project_info.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/services/bom_calculator.dart';
import 'package:protpo_app/services/validation_engine.dart';
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

  test('Flat Drip Edge label does not double "Edge"', () {
    final r = calc(metal: const MetalScope(flatDripLF: 100, flatDripMetalType: 'Gravel Stop'));
    final line = r.items.singleWhere((i) => i.skuKey == 'metal_drip_edge');
    expect(line.name, 'Flat Drip Edge — Gravel Stop');
  });

  ValidationResult validateMetal(MetalScope metal, {bool stripOverlayment = false}) {
    var bom = calc(metal: metal);
    if (stripOverlayment) {
      bom = BomResult(
        items: bom.items.where((i) => !i.name.toLowerCase().contains('overlayment')
            && !i.name.toLowerCase().contains('cover strip')
            && !i.name.toLowerCase().contains('cover tape')).toList(),
        warnings: bom.warnings, isComplete: bom.isComplete,
      );
    }
    return ValidationEngine.validate(
      projectInfo: ProjectInfo.initial().copyWith(warrantyYears: 20, designWindSpeed: '115 mph'),
      geometry: geo100(), systemSpecs: const SystemSpecs(deckType: 'Metal'),
      insulation: const InsulationSystem(), membrane: const MembraneSystem(),
      parapet: const ParapetWalls(), penetrations: const Penetrations(),
      metalScope: metal, bom: bom);
  }

  bool coverStripCritical(ValidationResult v) =>
      v.missingItems.any((m) => m.isCritical && m.triggerItem == 'Edge Metal');

  test('validation: all non-zero buckets TPO-coated -> no cover-strip item', () {
    final v = validateMetal(const MetalScope(eaveLF: 200, rakeLF: 100,
        rakeMetalType: 'TPO-Coated Drip Edge'), stripOverlayment: true);
    expect(coverStripCritical(v), isFalse);
    expect(v.missingItems.any((m) => m.triggerItem.startsWith('Edge Metal')), isFalse);
  });

  test('validation: non-zero Gravel Stop with no overlayment -> critical item', () {
    final v = validateMetal(const MetalScope(eaveLF: 200, rakeLF: 100,
        rakeMetalType: 'Gravel Stop'), stripOverlayment: true);
    expect(coverStripCritical(v), isTrue);
    expect(v.missingItems.any((m) => m.triggerItem == 'Edge Metal (Gravel Stop)'), isTrue);
  });

  test('validation: zero-LF non-TPO bucket triggers nothing', () {
    final v = validateMetal(const MetalScope(eaveLF: 200, rakeLF: 0,
        rakeMetalType: 'Gravel Stop'), stripOverlayment: true);
    expect(v.missingItems.any((m) => m.triggerItem.startsWith('Edge Metal')), isFalse);
  });
}
