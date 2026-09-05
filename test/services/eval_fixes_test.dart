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
import 'package:protpo_app/services/r_value_calculator.dart';
import 'package:protpo_app/services/zip_lookup.dart';

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
  _f2f3();
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

void _f2f3() {
  group('F2 — required R-value table (IECC 2021 C402.1.3, above deck)', () {
    test('RValueCalculator.requiredRForZone matches IECC 2021', () {
      expect(RValueCalculator.requiredRForZone('Zone 1'), 20);
      expect(RValueCalculator.requiredRForZone('Zone 2'), 25);
      expect(RValueCalculator.requiredRForZone('Zone 3'), 25);
      expect(RValueCalculator.requiredRForZone('Zone 4A (Mixed-Humid)'), 30);
      expect(RValueCalculator.requiredRForZone('Zone 5'), 30);
      expect(RValueCalculator.requiredRForZone('Zone 6'), 35);
      expect(RValueCalculator.requiredRForZone('Zone 7'), 35);
      expect(RValueCalculator.requiredRForZone('Zone 8'), 35);
    });
    test('ZIP lookup uses the same table (KC 64101 = Zone 4 → R-30)', () {
      final r = ZipLookupService.lookup('64101');
      expect(r.zoneCode, '4');
      expect(r.requiredRValue, RValueCalculator.requiredRForZone('Zone 4'));
      expect(r.requiredRValue, 30);
    });
  });

  group('F3 — BOM uses the assembly R-value it is given', () {
    final taperedOnly = const InsulationSystem(
      numberOfLayers: 0, hasTaper: true, taperDefaults: TaperDefaults());
    BomResult run({double? assemblyR}) => BomCalculator.calculate(
      projectInfo: ProjectInfo(estimateDate: DateTime(2026, 1, 1),
          requiredRValue: 30, climateZone: 'Zone 4'),
      geometry: _rect(100, 50),
      systemSpecs: const SystemSpecs(),
      insulation: taperedOnly,
      membrane: const MembraneSystem(fieldAttachment: 'Fully Adhered'),
      parapet: const ParapetWalls(),
      penetrations: const Penetrations(),
      metalScope: const MetalScope(),
      boardSchedule: null,
      assemblyRValue: assemblyR,
    );
    bool warned(BomResult b) => b.warnings.any((w) => w.contains('may not meet code'));

    test('no R-value provided → no code warning (BOM no longer guesses)', () {
      expect(warned(run()), isFalse);
    });
    test('assembly R-25 vs required R-30 → warning', () {
      expect(warned(run(assemblyR: 25)), isTrue);
    });
    test('assembly R-32 vs required R-30 → no warning', () {
      expect(warned(run(assemblyR: 32)), isFalse);
    });
  });
}
