import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/section_models.dart';
import 'bom_test_helpers.dart';

void main() {
  test('options are VersiWeld pails (default) and CAV-GRIP', () {
    expect(kAdhesiveTypes, [kAdhesiveVersiWeldPails, kAdhesiveCavGrip]);
    expect(const MembraneSystem().adhesiveType, kAdhesiveVersiWeldPails);
    expect(const ParapetWalls().parapetAdhesiveType, kAdhesiveVersiWeldPails);
  });

  test('legacy and unknown values normalize to pails', () {
    expect(normalizeAdhesiveType('VersiWeld TPO Bonding Adhesive'), kAdhesiveVersiWeldPails);
    expect(normalizeAdhesiveType(null), kAdhesiveVersiWeldPails);
    expect(normalizeAdhesiveType('CAV-GRIP 3V Spray'), kAdhesiveCavGrip);
  });

  test('REGRESSION: MA, metal deck, eave/drip edges only, no cover board → no adhesive', () {
    expect(adhesives(calc()), isEmpty);
  });

  test('FA 10,000 sf orders VersiWeld 5-gal pails', () {
    final r = calc(membrane: const MembraneSystem(fieldAttachment: 'Fully Adhered'));
    final a = adhesives(r).single;
    expect(a.skuKey, 'adhesive_versiweld_bonding');
    expect(a.unit, 'pails');
    expect(a.trace.packageSize, 5);
    expect(a.orderQty, ((10000 / 60) * 1.05 / 5).ceil());
    expect(a.orderQty, inInclusiveRange(35, 36));
  });

  test('FA with CAV-GRIP orders cylinders + UN-TACK', () {
    final r = calc(membrane: const MembraneSystem(
        fieldAttachment: 'Fully Adhered', adhesiveType: kAdhesiveCavGrip));
    expect(adhesives(r).single.skuKey, 'adhesive_cavgrip_3v_40lb');
    expect(r.items.any((i) => i.skuKey == 'cleaner_untack_8oz_aerosol'), true);
  });
}
