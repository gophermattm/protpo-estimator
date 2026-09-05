/// Regression tests for findings in docs/superpowers/reports/2026-09-05-code-evaluation.md
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/bom_calculator.dart';
import 'package:protpo_app/models/project_info.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/drainage_zone.dart';
import 'package:protpo_app/services/qxo_pricing_service.dart';

RoofGeometry _rect(double w, double h) => RoofGeometry(shapes: [
      RoofShape(shapeIndex: 1, edgeLengths: [w, h, w, h],
          edgeTypes: const ['Eave', 'Eave', 'Eave', 'Eave']),
    ]);

BomResult _bom({
  required InsulationSystem insulation,
  RoofGeometry? geometry,
  MembraneSystem? membrane,
}) =>
    BomCalculator.calculate(
      projectInfo: ProjectInfo(estimateDate: DateTime(2026, 1, 1)),
      geometry: geometry ?? _rect(100, 50),
      systemSpecs: const SystemSpecs(),
      insulation: insulation,
      membrane: membrane ?? const MembraneSystem(fieldAttachment: 'Fully Adhered'),
      parapet: const ParapetWalls(),
      penetrations: const Penetrations(),
      metalScope: const MetalScope(),
      boardSchedule: null,
    );

void main() {
  _f8();
  group('F1 — tapered MA without board schedule', () {
    final ins = const InsulationSystem(
      numberOfLayers: 0,
      hasTaper: true,
      taperDefaults: TaperDefaults(attachmentMethod: 'Mechanically Attached'),
    );

    test('still emits insulation fasteners and plates over the roof area', () {
      final bom = _bom(insulation: ins);
      final fast = bom.items.where((i) => i.skuKey == 'fastener_insulation').toList();
      final plates = bom.items.where((i) => i.skuKey == 'plate_3in_insulation').toList();
      expect(fast, hasLength(1));
      expect(fast.first.orderQty, greaterThan(0));
      // 5000 sf × 0.188/sf (20-yr Metal) = 940 → ×1.05 = 987 → 2 boxes of 500
      expect(fast.first.orderQty, 2);
      expect(plates, hasLength(1));
      expect(plates.first.orderQty, 1);
    });

    test('warns that fastener length is estimated until drains are placed', () {
      final bom = _bom(insulation: ins);
      expect(bom.warnings.any((w) => w.contains('fastener length') && w.contains('drain')), isTrue);
    });
  });
}

// ── F8 ──────────────────────────────────────────────────────────────────────

void _f8() {
  group('F8 — QXO pack adjustment', () {
    test('raw unit count is divided by QXO pack size', () {
      expect(QxoPricingService.packAdjustedOrderQty(
          bomQty: 987, qxoPackQty: 500, bomPackageSize: 1), 2);
    });
    test('BOM quantity already in packages is NOT divided again', () {
      // BOM says 2 boxes (500/box). QXO item packs 500. Order 2, not ceil(2/500)=1.
      expect(QxoPricingService.packAdjustedOrderQty(
          bomQty: 2, qxoPackQty: 500, bomPackageSize: 500), 2);
    });
    test('no QXO pack info passes quantity through', () {
      expect(QxoPricingService.packAdjustedOrderQty(
          bomQty: 7, qxoPackQty: null, bomPackageSize: 1), 7);
    });
  });
}
