/// Regression tests for findings in docs/superpowers/reports/2026-09-05-code-evaluation.md
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/bom_calculator.dart';
import 'package:protpo_app/models/project_info.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/drainage_zone.dart';

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
