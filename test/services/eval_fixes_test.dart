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
import 'package:protpo_app/services/validation_engine.dart';
import 'package:protpo_app/services/board_schedule_calculator.dart';
import 'package:protpo_app/data/board_schedules.dart';

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
  _f4f5();
  _f6f7();
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

void _f4f5() {
  group('F4 — multi-shape geometry', () {
    final geo = RoofGeometry(shapes: [
      const RoofShape(shapeIndex: 1, edgeLengths: [100, 50, 100, 50]),
      const RoofShape(shapeIndex: 2, edgeLengths: [40, 40, 40, 40]),
    ]);
    test('totalPerimeter sums every Add shape', () {
      expect(geo.totalArea, 6600);
      expect(geo.totalPerimeter, 460);
    });
    test('Subtract shapes do not add perimeter', () {
      final g = RoofGeometry(shapes: [
        const RoofShape(shapeIndex: 1, edgeLengths: [100, 50, 100, 50]),
        const RoofShape(shapeIndex: 2, operation: 'Subtract', edgeLengths: [10, 10, 10, 10]),
      ]);
      expect(g.totalArea, 4900);
      expect(g.totalPerimeter, 300);
    });
    test('validation warns that tapered schedule uses the first shape only', () {
      final ins = const InsulationSystem(hasTaper: true, taperDefaults: TaperDefaults());
      final bom = _bom(insulation: ins, geometry: geo);
      final v = ValidationEngine.validate(
        projectInfo: ProjectInfo(estimateDate: DateTime(2026, 1, 1), projectName: 'x'),
        geometry: geo, systemSpecs: const SystemSpecs(), insulation: ins,
        membrane: const MembraneSystem(), parapet: const ParapetWalls(),
        penetrations: const Penetrations(), metalScope: const MetalScope(), bom: bom);
      expect(v.issues.any((i) => i.category == 'Geometry' &&
          i.message.contains('first shape')), isTrue);
    });
  });

  group('F5 — wind zone areas', () {
    test('perimeter zone excludes corner squares; field = total − corners − perimeter', () {
      final z = WindZones.fromDimensions(
          totalArea: 10000, totalPerimeter: 400, outsideCorners: 4, zoneWidth: 5);
      expect(z.cornerZoneArea, 100);     // 4 × 5²
      expect(z.perimeterZoneArea, 1800); // 400×5 − 2×4×5²
      expect(z.fieldZoneArea, 8100);
      expect(z.totalArea, 10000);
    });
  });
}

void _f6f7() {
  BoardScheduleResult run(double minT, {double distance = 47}) =>
      BoardScheduleCalculator.compute(BoardScheduleInput(
        distance: distance, taperRate: '1/4:12', minThickness: minT,
        manufacturer: 'Versico', profileType: 'extended', roofWidthFt: 27));

  group('F6 — base flat fill honours minThickness at drain', () {
    test('min 1.0" over an X panel (0.5" thin edge) adds 0.5" base fill on every row', () {
      final r = run(1.0);
      expect(r.rows.first.flatFillThickness, 0.5);
      expect(r.rows[3].flatFillThickness, 0.5);
      // installed thickness = panel thin edge + fill = reported thinEdge
      expect(r.rows.first.panelThinEdge + r.rows.first.flatFillThickness,
          closeTo(r.rows.first.thinEdge, 0.001));
    });
    test('min 0.5" matches the panel thin edge → no base fill', () {
      expect(run(0.5).rows.first.flatFillThickness, 0.0);
    });
  });

  group('F7 — flat fill decomposed into stock thicknesses', () {
    test('decomposeFlatFill splits into ≤4.0" boards, largest first', () {
      expect(BoardScheduleCalculator.decomposeFlatFill(8.0), [4.0, 4.0]);
      expect(BoardScheduleCalculator.decomposeFlatFill(4.5), [4.0, 0.5]);
      expect(BoardScheduleCalculator.decomposeFlatFill(2.5), [2.5]);
      expect(BoardScheduleCalculator.decomposeFlatFill(0.0), isEmpty);
    });
    test('47ft run, min 0.5": cycle 2 rows (8.0" fill) count as two 4.0" boards', () {
      final r = run(0.5);
      // rows 4–7 fill 4.0 (1 board), rows 8–11 fill 8.0 (2 boards): (4 + 8) × 6.75 = 81
      expect(r.flatFillCounts.keys, everyElement(isIn(kFlatStockThicknesses)));
      expect(r.flatFillCounts[4.0], 81);
      expect(r.flatFillCounts.containsKey(8.0), isFalse);
      expect(r.totalFlatFillPanels, 81);
      // footprint SF counts each row once: 8 rows × 6.75 × 16
      expect(r.totalFlatFillSF, closeTo(864, 0.01));
    });
  });
}
