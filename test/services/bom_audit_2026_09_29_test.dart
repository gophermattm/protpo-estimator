// Regression tests for the 2026-09-29 BOM formula audit.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/services/bom_calculator.dart';
import 'package:protpo_app/services/board_schedule_calculator.dart';
import 'package:protpo_app/models/project_info.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/models/drainage_zone.dart';
import 'package:protpo_app/models/estimate.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/providers/job_providers.dart';
import 'package:protpo_app/services/serialization.dart';
import 'package:protpo_app/services/qxo_pricing_service.dart';

RoofShape _rect(double l, double w) => RoofShape(
    shapeIndex: 1,
    edgeLengths: [l, w, l, w],
    edgeTypes: const ['Eave', 'Eave', 'Eave', 'Eave']);

RoofGeometry _geo({double l = 100, double w = 100, double zone = 5}) {
  final g = RoofGeometry(shapes: [_rect(l, w)], outsideCorners: 4);
  return g.copyWith(
      windZones: WindZones.fromDimensions(
          totalArea: g.totalArea,
          totalPerimeter: g.totalPerimeter,
          outsideCorners: 4,
          zoneWidth: zone));
}

BomResult _calc({
  RoofGeometry? geometry,
  ProjectInfo? info,
  SystemSpecs specs = const SystemSpecs(deckType: 'Wood'),
  InsulationSystem insulation = const InsulationSystem(),
  MembraneSystem membrane = const MembraneSystem(),
  ParapetWalls parapet = const ParapetWalls(),
  Penetrations penetrations = const Penetrations(),
  MetalScope metalScope = const MetalScope(),
  BoardScheduleResult? schedule,
}) =>
    BomCalculator.calculate(
      projectInfo: info ??
          ProjectInfo.initial()
              .copyWith(warrantyYears: 20, designWindSpeed: '115 mph'),
      geometry: geometry ?? _geo(),
      systemSpecs: specs,
      insulation: insulation,
      membrane: membrane,
      parapet: parapet,
      penetrations: penetrations,
      metalScope: metalScope,
      boardSchedule: schedule,
    );

BomLineItem _item(BomResult r, String skuKey) =>
    r.items.firstWhere((i) => i.skuKey == skuKey);

void main() {
  group('MA membrane fasteners — seam-row math', () {
    test('10,000 sf roof, 10\' field / 6\' perimeter sheets, 12" o.c.', () {
      final r = _calc();
      final f = _item(r, 'fastener_membrane');
      // field 8,100 sf ÷ (9.5' × 1') = 852.6
      // perim+corner 1,900 sf ÷ (5.5' × 1') = 345.5
      expect(f.trace.baseQty, closeTo(852.6 + 345.5, 1.0));
      expect(f.orderQty, 3); // 1,258 with 5% waste ÷ 500/box
      final p = _item(r, 'plate_seam_stress_3in');
      expect(p.trace.baseQty, closeTo(f.trace.baseQty, 0.01));
      expect(p.orderQty, 2); // ÷ 1,000/box
    });
  });

  group('membrane rolls', () {
    test('perimeter roll "None" puts perimeter + corner area on field rolls',
        () {
      final r = _calc(
          membrane: const MembraneSystem(perimeterRollWidth: 'None'));
      final field = _item(r, 'tpo_membrane_field');
      expect(field.trace.baseQty, closeTo(10.0, 0.01)); // 10,000 sf ÷ 1,000
    });

    test('stale zone areas (pushed before dimensions) are recomputed', () {
      final stale = RoofGeometry(
        shapes: [_rect(100, 100)],
        outsideCorners: 4,
        windZones: const WindZones(perimeterZoneWidth: 5, cornerZoneWidth: 5),
      );
      final r = _calc(geometry: stale);
      final field = _item(r, 'tpo_membrane_field');
      expect(field.trace.baseQty, closeTo(8.1, 0.01));
    });
  });

  group('tapered insulation', () {
    const taper = InsulationSystem(
      numberOfLayers: 0,
      hasTaper: true,
      taperDefaults: TaperDefaults(minThickness: 1.0),
    );

    test('empty board schedule still emits tapered MA fasteners', () {
      final r = _calc(insulation: taper, schedule: BoardScheduleResult.empty);
      final f = r.items.where((i) =>
          i.skuKey == 'fastener_insulation' && i.name.contains('Tapered'));
      expect(f, isNotEmpty);
      expect(f.first.trace.baseQty, closeTo(10000 * 0.188, 1));
    });

    test('no-schedule fallback counts 4x4 (16 sf) panels', () {
      final r = _calc(insulation: taper);
      final t = r.items.firstWhere((i) =>
          i.skuKey == 'iso_polyiso_tapered_panel');
      expect(t.trace.baseQty, closeTo(10000 / 16, 0.01));
    });
  });

  test('RUSS fastener reaches the deck through the insulation stack', () {
    final r = _calc(
      parapet: const ParapetWalls(
          hasParapetWalls: true, parapetHeight: 24, parapetTotalLF: 400),
    );
    final russ = _item(r, 'fastener_russ_strip');
    final memb = _item(r, 'fastener_membrane');
    expect(russ.attributes!['length'], memb.attributes!['length']);
  });

  group('multi-building aggregate', () {
    test('package items stay in packages and keep skuKey', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(estimatorProvider.notifier);
      for (var b = 0; b < 2; b++) {
        if (b > 0) n.addBuilding();
        n.updateShape(0, _rect(100, 100));
      }
      final single = c.read(allBuildingBomsProvider).first;
      final agg = c.read(aggregateBomProvider);
      final one = _item(single, 'fastener_membrane');
      final both = agg.items.firstWhere((i) => i.name == one.name);
      expect(both.skuKey, 'fastener_membrane');
      expect(both.unit, 'boxes');
      expect(both.orderQty,
          (2 * one.trace.withWaste / one.trace.packageSize).ceil());
    });
  });

  group('job switching', () {
    test('loading an empty (new) estimate resets the estimator', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(estimatorProvider.notifier).updateShape(0, _rect(100, 100));
      final ok = loadEstimateIntoEditor(
          c, Estimate(id: 'e2', name: 'Initial Estimate'), 'job-2');
      expect(ok, isTrue);
      expect(c.read(roofGeometryProvider).totalArea, 0);
      expect(c.read(activeJobIdProvider), 'job-2');
    });

    test('loading another estimate clears BOM edits, deletions and prices',
        () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(bomLineEditsProvider.notifier).state = {
        'Membrane:x': const BomLineEdit(qty: 0),
      };
      c.read(bomDeletedItemsProvider.notifier).state = {'Membrane:y'};
      final state = stateToJson(c.read(estimatorProvider), 'p');
      loadEstimateIntoEditor(
          c, Estimate(id: 'e3', name: 'E', estimatorState: state), 'job-3');
      expect(c.read(bomLineEditsProvider), isEmpty);
      expect(c.read(bomDeletedItemsProvider), isEmpty);
      expect(c.read(pricedItemsProvider), isNull);
    });
  });

  group('round 2 decisions (2026-09-29)', () {
    test('counted items order exactly — no spare', () {
      final r = _calc(
          penetrations: const Penetrations(
              smallPipeCount: 1, skylightCount: 1, scupperCount: 1));
      for (final name in ['Pipe Boot — Small', 'Skylight', 'Scupper']) {
        final i = r.items.firstWhere((i) => i.name.startsWith(name));
        expect(i.orderQty, 1, reason: name);
      }
    });

    test('Rhinobond: no separate insulation fasteners or plates', () {
      final r = _calc(
          membrane: const MembraneSystem(
              fieldAttachment: 'Rhinobond (Induction Welded)'));
      expect(r.items.where((i) => i.skuKey == 'fastener_insulation'), isEmpty);
      expect(r.items.where((i) => i.name.contains('Insulation Plates')), isEmpty);
      expect(r.items.where((i) => i.skuKey == 'plate_rhinobond'), isNotEmpty);
    });

    test('edge metal fasteners 4" o.c. on roof edges only', () {
      final r = _calc(
          metalScope: const MetalScope(dripEdgeLF: 400, wallFlashingLF: 100));
      final f = _item(r, 'fastener_edge_metal');
      expect(f.trace.baseQty, closeTo(400 * 12 / 4, 0.01));
    });

    test('CAV-GRIP 3V field spray ~2,000 sf per cylinder', () {
      final r = _calc(
          membrane: const MembraneSystem(
              fieldAttachment: 'Fully Adhered',
              adhesiveType: 'CAV-GRIP 3V Spray'));
      final c = _item(r, 'adhesive_cavgrip_3v_40lb');
      expect(c.trace.baseQty, closeTo(10000 / 2000, 0.01));
    });

    test('VersiWeld 5-gal pail option never switches to 15-gal', () {
      final r = _calc(
          membrane: const MembraneSystem(
              fieldAttachment: 'Fully Adhered',
              adhesiveType: kAdhesiveVersiWeldPails));
      final a = _item(r, 'adhesive_versiweld_bonding');
      expect(a.unit, 'pails');
      expect(a.trace.packageSize, 5);
    });

    test('seam LF includes perimeter half-sheet seams', () {
      final r = _calc(membrane: const MembraneSystem(seamType: 'Tape'));
      final tape = _item(r, 'tape_tpo_seam_3in');
      // field: ceil(8,100/1,000)=9 rolls → 800 LF; perimeter: 1,900 sf ÷ 6' ≈ 316.7 LF
      expect(tape.trace.baseQty * 100, closeTo(800 + 1900 / 6, 0.5));
    });
  });

  test('BOM/labor overrides survive a save → load round trip', () {
    final a = ProviderContainer();
    addTearDown(a.dispose);
    a.read(estimatorProvider.notifier).updateShape(0, _rect(50, 40));
    a.read(bomLineEditsProvider.notifier).state = {
      'Membrane:x': const BomLineEdit(qty: 12, unitPrice: 99.5),
    };
    a.read(bomDeletedItemsProvider.notifier).state = {'Consumables:y'};
    a.read(bomManualItemsProvider.notifier).state = [
      const ManualBomItem(id: 'm1', category: 'Misc', description: 'Crane', qty: 1),
    ];
    a.read(itemMarginOverridesProvider.notifier).state = {'Membrane:x': 0.25};
    final saved = buildEstimateDraft(a, 'e1', 'E')!;

    final b = ProviderContainer();
    addTearDown(b.dispose);
    b.read(bomDeletedItemsProvider.notifier).state = {'stale'};
    expect(loadEstimateIntoEditor(b, saved, 'job-1'), isTrue);
    expect(b.read(roofGeometryProvider).totalArea, 2000);
    expect(b.read(bomLineEditsProvider)['Membrane:x']!.qty, 12);
    expect(b.read(bomLineEditsProvider)['Membrane:x']!.unitPrice, 99.5);
    expect(b.read(bomDeletedItemsProvider), {'Consumables:y'});
    expect(b.read(bomManualItemsProvider).single.description, 'Crane');
    expect(b.read(itemMarginOverridesProvider)['Membrane:x'], 0.25);
  });

  test('QXO prices are saved with the estimate and restored', () {
    final a = ProviderContainer();
    addTearDown(a.dispose);
    a.read(estimatorProvider.notifier).updateShape(0, _rect(50, 40));
    a.read(pricedItemsProvider.notifier).state = {
      'Roll': const QxoPricedItem(
          bomName: 'Roll', qxoItemNumber: '262671',
          qxoProductName: 'TPO 60 mil', qxoBrand: 'Versico',
          unitPrice: 1032.56, uom: 'RL', packQty: null, orderQty: 3,
          confidence: 0.9, bomUnit: 'rolls'),
    };
    final saved = buildEstimateDraft(a, 'e1', 'E')!;
    final b = ProviderContainer();
    addTearDown(b.dispose);
    loadEstimateIntoEditor(b, saved, 'job-1');
    final p = b.read(pricedItemsProvider)!['Roll']!;
    expect(p.unitPrice, 1032.56);
    expect(p.uom, 'RL');
    expect(p.qxoItemNumber, '262671');
    expect(p.bomUnit, 'rolls');
  });
}
