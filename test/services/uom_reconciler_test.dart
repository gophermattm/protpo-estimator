/// Eval F9 — BOM unit vs QXO UOM reconciliation.
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/uom_reconciler.dart';
import 'package:protpo_app/services/qxo_pricing_service.dart';

void main() {
  group('classifyUnit', () {
    test('maps BOM words and QXO codes to the same classes', () {
      expect(classifyUnit('boxes'), UnitClass.box);
      expect(classifyUnit('BX'), UnitClass.box);
      expect(classifyUnit('CTN'), UnitClass.box);   // carton ≈ box
      expect(classifyUnit('buckets'), UnitClass.bucket);
      expect(classifyUnit('BKT'), UnitClass.bucket);
      expect(classifyUnit('PL'), UnitClass.bucket); // pail ≈ bucket
      expect(classifyUnit('rolls'), UnitClass.roll);
      expect(classifyUnit('RL'), UnitClass.roll);
      expect(classifyUnit('each'), UnitClass.each);
      expect(classifyUnit('EA'), UnitClass.each);
      expect(classifyUnit('PC'), UnitClass.each);
      expect(classifyUnit('boards'), UnitClass.board);
      expect(classifyUnit('SH'), UnitClass.board);  // sheet ≈ board
      expect(classifyUnit('gallons'), UnitClass.gallon);
      expect(classifyUnit('GAL'), UnitClass.gallon);
      expect(classifyUnit('tubes'), UnitClass.tube);
      expect(classifyUnit('cylinders'), UnitClass.cylinder);
      expect(classifyUnit('CYL'), UnitClass.cylinder);
    });
    test('unknown strings classify as unknown, never guessed', () {
      expect(classifyUnit('ZZZ'), UnitClass.unknown);
      expect(classifyUnit(''), UnitClass.unknown);
    });
  });

  group('reconcileUom', () {
    test('same class → match', () {
      expect(reconcileUom(bomUnit: 'boxes', qxoUom: 'BX'), UomStatus.match);
      expect(reconcileUom(bomUnit: 'buckets', qxoUom: 'PL'), UomStatus.match);
      expect(reconcileUom(bomUnit: 'boards', qxoUom: 'SH'), UomStatus.match);
    });
    test('different class → mismatch (the F9 hazard: boxes priced per EA)', () {
      expect(reconcileUom(bomUnit: 'boxes', qxoUom: 'EA'), UomStatus.mismatch);
      expect(reconcileUom(bomUnit: 'rolls', qxoUom: 'EA'), UomStatus.mismatch);
      expect(reconcileUom(bomUnit: 'pails', qxoUom: 'GAL'), UomStatus.mismatch);
    });
    test('missing or unrecognised UOM → unknown, not mismatch', () {
      expect(reconcileUom(bomUnit: 'rolls', qxoUom: null), UomStatus.unknown);
      expect(reconcileUom(bomUnit: 'rolls', qxoUom: 'ZZZ'), UomStatus.unknown);
    });
  });

  group('QxoPricedItem.uomStatus', () {
    test('flags a box line priced per each', () {
      const p = QxoPricedItem(bomName: 'x', qxoItemNumber: '1', qxoProductName: '',
          qxoBrand: '', unitPrice: 1, uom: 'EA', orderQty: 3, bomUnit: 'boxes');
      expect(p.uomStatus, UomStatus.mismatch);
      expect(p.hasUomMismatch, isTrue);
    });
    test('no bomUnit recorded → unknown', () {
      const p = QxoPricedItem(bomName: 'x', qxoItemNumber: '1', qxoProductName: '',
          qxoBrand: '', uom: 'EA');
      expect(p.uomStatus, UomStatus.unknown);
      expect(p.hasUomMismatch, isFalse);
    });
  });
}
