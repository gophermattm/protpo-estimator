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
import 'package:protpo_app/services/bom_totals.dart';
import 'package:protpo_app/providers/estimator_providers.dart' show BomLineEdit, ManualBomItem, LaborLineEdit, ManualLaborItem;
import 'package:protpo_app/models/labor_models.dart';
import 'package:protpo_app/services/serialization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/providers/estimator_providers.dart' show estimatorProvider, boardScheduleProvider;

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
  _f10();
  _f14();
  _f12();
  _f13f15f16();
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
      // 5000 sf × 0.188/sf (20-yr Metal) = 940 → ×1.05 = 987 → 1 carton of 1,000
      // (QXO pack for short HPVX lengths)
      expect(fast.first.orderQty, 1);
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

void _f10() {
  group('F10 — BOM totals honour edits, deletions and manual lines', () {
    BomLineItem li(String cat, String name, double qty) => BomLineItem(
        category: cat, name: name, orderQty: qty, unit: 'each', notes: '',
        trace: BomTrace(baseDescription: '', baseQty: qty, wastePercent: 0,
            withWaste: qty, packageSize: 1, orderQty: qty, breakdown: const []));
    final items = [li('Membrane', 'Roll', 2), li('Fasteners & Plates', 'Screw', 5), li('Metal Scope', 'Coping', 1)];
    final priced = {
      'Roll':   const QxoPricedItem(bomName: 'Roll', qxoItemNumber: '1', qxoProductName: '', qxoBrand: '', unitPrice: 100, orderQty: 2),
      'Screw':  const QxoPricedItem(bomName: 'Screw', qxoItemNumber: '2', qxoProductName: '', qxoBrand: '', unitPrice: 10, orderQty: 5),
      'Coping': const QxoPricedItem(bomName: 'Coping', qxoItemNumber: '3', qxoProductName: '', qxoBrand: '', unitPrice: 40, orderQty: 1),
    };

    test('qty edit, deletion and manual item all flow into cost and value', () {
      final t = computeBomTotals(
        items: items, pricedItems: priced, globalMargin: 0.30,
        itemMarginOverrides: const {},
        edits: {'Membrane:Roll': const BomLineEdit(qty: 3)},
        deleted: {'Metal Scope:Coping'},
        manualItems: [const ManualBomItem(id: 'm', category: 'Misc', description: 'Tarp', qty: 1, unitPrice: 50)],
      );
      // Roll 100×3 + Screw 10×5 + Tarp 50 = 400 ; Coping deleted
      expect(t.cost, closeTo(400, 0.001));
      expect(t.value, closeTo(400 / 0.7, 0.001));
      expect(t.unpricedCount, 0);
    });

    test('per-item margin override and unit-price override apply', () {
      final t = computeBomTotals(
        items: items, pricedItems: priced, globalMargin: 0.30,
        itemMarginOverrides: const {'Roll': 0.5},
        edits: {'Fasteners & Plates:Screw': const BomLineEdit(unitPrice: 20)},
        deleted: const {}, manualItems: const [],
      );
      // Roll 200 @50% → 400 ; Screw 20×5=100 @30% → 142.857 ; Coping 40 @30% → 57.143
      expect(t.cost, closeTo(340, 0.001));
      expect(t.value, closeTo(400 + 100 / 0.7 + 40 / 0.7, 0.001));
    });

    test('fastener lines always count toward the total', () {
      final t = computeBomTotals(
        items: items, pricedItems: priced, globalMargin: 0.0,
        itemMarginOverrides: const {}, edits: const {}, deleted: const {},
        manualItems: const [],
      );
      expect(t.cost, closeTo(290, 0.001)); // 240 + 50 screw line
    });

    test('unpriced lines are counted, not silently skipped', () {
      final t = computeBomTotals(
        items: items, pricedItems: {'Roll': priced['Roll']!}, globalMargin: 0.3,
        itemMarginOverrides: const {}, edits: const {}, deleted: const {}, manualItems: const [],
      );
      expect(t.unpricedCount, 2);
    });
  });
}

void _f14() {
  group('F14 — labor total honours edits, deletions and manual lines', () {
    final items = const [
      LaborLineItem(name: 'Install TPO Membrane', unit: 'SQ', rate: 45, quantity: 50),
      LaborLineItem(name: 'Drains', unit: 'each', rate: 50, quantity: 4),
      LaborLineItem(name: 'Dump Fees', unit: 'each', rate: 450, quantity: 1),
    ];
    test('sums rate × qty with overrides applied', () {
      final t = computeLaborTotal(
        items: items,
        edits: {'Drains': const LaborLineEdit(rate: 60, qty: 5)},
        deleted: {'Dump Fees'},
        manualItems: [const ManualLaborItem(id: 'x', name: 'Crane', rate: 800, quantity: 1)],
      );
      // 45×50 + 60×5 + 800 = 2250 + 300 + 800
      expect(t, closeTo(3350, 0.001));
    });
  });
}

void _f12() {
  ValidationResult validate({
    required MembraneSystem membrane,
    ParapetWalls parapet = const ParapetWalls(),
    Penetrations penetrations = const Penetrations(),
    int warrantyYears = 20,
    String? wind,
  }) {
    final info = ProjectInfo(estimateDate: DateTime(2026, 1, 1), projectName: 'x',
        warrantyYears: warrantyYears, designWindSpeed: wind);
    final geo = _rect(100, 50);
    const ins = InsulationSystem();
    final bom = BomCalculator.calculate(
      projectInfo: info, geometry: geo, systemSpecs: const SystemSpecs(),
      insulation: ins, membrane: membrane, parapet: parapet,
      penetrations: penetrations, metalScope: const MetalScope(), boardSchedule: null);
    return ValidationEngine.validate(
      projectInfo: info, geometry: geo, systemSpecs: const SystemSpecs(),
      insulation: ins, membrane: membrane, parapet: parapet,
      penetrations: penetrations, metalScope: const MetalScope(), bom: bom);
  }

  group('F12 — validation false positives', () {
    test('pre-molded pipe boots satisfy the clamping-ring requirement', () {
      final v = validate(membrane: const MembraneSystem(),
          penetrations: const Penetrations(smallPipeCount: 3));
      expect(v.missingItems.any((m) => m.missingItem.contains('Clamping')), isFalse);
    });

    test('CAV-PRIME primer on the BOM satisfies every "TPO Primer" companion check', () {
      final v = validate(
        membrane: const MembraneSystem(primerType: 'CAV-PRIME Spray (1,760 sf/cyl)', seamType: 'Tape'),
        parapet: const ParapetWalls(hasParapetWalls: true, parapetHeight: 24, parapetTotalLF: 300),
      );
      expect(v.missingItems.where((m) => m.missingItem == 'TPO Primer'), isEmpty);
    });

    test('scupper detail is an info note, not a permanent missing-item penalty', () {
      final v = validate(membrane: const MembraneSystem(),
          penetrations: const Penetrations(scupperCount: 2));
      expect(v.missingItems.any((m) => m.triggerItem == 'Scuppers'), isFalse);
      expect(v.issues.any((i) => i.severity == IssueSeverity.info && i.message.contains('Scupper')), isTrue);
    });
  });

  group('F12 — RUSS fastener spacing follows warranty / wind', () {
    BomLineItem russFast(int warranty, String? wind) {
      final bom = BomCalculator.calculate(
        projectInfo: ProjectInfo(estimateDate: DateTime(2026, 1, 1),
            warrantyYears: warranty, designWindSpeed: wind),
        geometry: _rect(100, 50), systemSpecs: const SystemSpecs(),
        insulation: const InsulationSystem(), membrane: const MembraneSystem(),
        parapet: const ParapetWalls(hasParapetWalls: true, parapetHeight: 24, parapetTotalLF: 100),
        penetrations: const Penetrations(), metalScope: const MetalScope(), boardSchedule: null);
      return bom.items.firstWhere((i) => i.skuKey == 'fastener_russ_strip');
    }
    test('20-yr, 85 mph → 12" o.c. → 100 fasteners per 100 LF', () {
      expect(russFast(20, '85 mph').trace.baseQty, 100);
    });
    test('25-yr → 6" o.c. → 200 fasteners per 100 LF', () {
      expect(russFast(25, '85 mph').trace.baseQty, 200);
    });
    test('20-yr, 115 mph → 6" o.c.', () {
      expect(russFast(20, '115 mph').trace.baseQty, 200);
    });
  });
}

void _f13f15f16() {
  group('F13 — edge types survive save/load', () {
    test('roofGeometry JSON round-trip preserves edgeTypes', () {
      final geo = RoofGeometry(shapes: [
        const RoofShape(shapeIndex: 1, shapeType: 'Rectangle',
            edgeLengths: [100, 50, 100, 50],
            edgeTypes: ['Parapet', 'Rake Edge', 'Eave', 'Headwall']),
      ]);
      final back = roofGeometryFromJson(roofGeometryToJson(geo));
      expect(back.shapes.first.edgeTypes, ['Parapet', 'Rake Edge', 'Eave', 'Headwall']);
    });
    test('old documents without edgeTypes load with per-edge defaults', () {
      final j = roofGeometryToJson(RoofGeometry(shapes: [
        const RoofShape(shapeIndex: 1, edgeLengths: [10, 10, 10, 10]),
      ]));
      (j['shapes'] as List).first.remove('edgeTypes');
      final back = roofGeometryFromJson(j);
      expect(back.shapes.first.edgeTypes, hasLength(4));
    });
  });

  group('F15 — board schedule waste follows project waste', () {
    test('multi-zone aggregate uses ProjectInfo.wasteMaterial, not 10%', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(estimatorProvider.notifier);
      n.updateProjectInfo(ProjectInfo(estimateDate: DateTime(2026, 1, 1), wasteMaterial: 0.15));
      n.updateRoofGeometry(RoofGeometry(
        shapes: [const RoofShape(shapeIndex: 1, edgeLengths: [100, 50, 100, 50])],
        drainLocations: const [DrainLocation(x: 25, y: -25), DrainLocation(x: 75, y: -25)],
      ));
      n.setTaperedEnabled(true);
      final r = c.read(boardScheduleProvider)!;
      expect(r.totalPanelsWithWaste, (r.totalPanels * 1.15).ceil());
    });
  });

  group('F16 — one seam-length estimate', () {
    test('membrane cleaner and cut-edge sealant quote the same seam LF', () {
      // Fully adhered: no MA perimeter-sheet band, so all 5,000 sf is field sheets.
      final bom = _bom(insulation: const InsulationSystem(),
          membrane: const MembraneSystem(fieldAttachment: 'Fully Adhered'));
      final cleaner = bom.items.firstWhere((i) => i.skuKey == 'cleaner_weathered_membrane');
      final cutEdge = bom.items.firstWhere((i) => i.skuKey == 'sealant_cut_edge');
      // 5000 sf ÷ 1000 sf/roll = 5 rolls → (5 − 1) × 100' = 400 LF field seams
      expect(cutEdge.trace.breakdown.any((l) => l.contains('= 400 LF')), isTrue);
      expect(cleaner.trace.breakdown.any((l) => l.contains('400 LF')), isTrue);
    });
  });
}
