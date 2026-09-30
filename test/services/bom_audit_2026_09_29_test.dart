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
import 'package:protpo_app/data/versico_ma_fastening.dart';
import 'package:protpo_app/data/qxo_pack_sizes.dart';
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
  group('MA membrane fasteners — Versico table + seam-row math', () {
    test('10,000 sf wood (15/32 5-ply), 55 mph, 10\'/6\' sheets', () {
      final r = _calc();
      final f = _item(r, 'fastener_membrane');
      // Table III: 1 perimeter sheet, 12" o.c. Net widths: 10' − 5.5" and 6' − 5.5".
      const fieldNet = 10 - 5.5 / 12, perimNet = 6 - 5.5 / 12;
      const perimArea = 400 * perimNet - 4 * perimNet * perimNet;
      const expected = (10000 - perimArea) / fieldNet + perimArea / perimNet;
      expect(f.trace.baseQty, closeTo(expected, 0.5));
      expect(f.unit, 'cartons');
      // 2.5" stack + 0.75" deck + 1" = 4.25" → 5" HPV, 1,000/carton (QXO)
      expect(f.attributes!['length'], '5"');
      expect(f.trace.packageSize, 1000);
      expect(f.orderQty, 2);
      final p = _item(r, 'plate_seam_stress_3in');
      expect(p.trace.baseQty, closeTo(f.trace.baseQty, 0.01));
      expect(p.orderQty, 2);
    });

    test('8" HPV uses the QXO 500/carton pack', () {
      final r = _calc(insulation: const InsulationSystem(
          numberOfLayers: 2,
          layer2: InsulationLayer(thickness: 2.5)));
      final f = _item(r, 'fastener_membrane');
      // 5" stack + 0.75 + 1 = 6.75" → 8" HPV
      expect(f.attributes!['length'], '8"');
      expect(f.trace.packageSize, 500);
    });

    test('warranty over 20 years warns that Versico approval is needed', () {
      final r = _calc(info: ProjectInfo.initial().copyWith(warrantyYears: 25));
      expect(r.warnings.any((w) => w.contains('up to 20 years')), isTrue);
    });
  });

  group('Versico MA table lookup', () {
    VersicoMaResult look(String deck, int wind, {double h = 30,
        String coast = 'Greater than 7 miles', String field = "10'",
        String perim = "6'", String wood = '15/32" 5-Ply Plywood'}) =>
        versicoMaLookup(deckType: deck, woodDeckGrade: wood,
            windWarrantyMph: wind, buildingHeightFt: h,
            coastlineDistance: coast, fieldRollWidth: field,
            perimeterRollWidth: perim);

    test('steel 72 mph ≤60\' → 2 perimeter sheets, 12" o.c.', () {
      final r = look('Metal', 72);
      expect(r.status, VersicoMaStatus.ok);
      expect(r.perimeterSheets, 2);
      expect(r.spacingIn, 12);
    });
    test('steel 80 mph 10\' sheets → 6" o.c. (HPVX); concrete → 12"', () {
      expect(look('Metal', 80).spacingIn, 6);
      expect(look('Concrete', 80).spacingIn, 12);
      expect(look('Metal', 80, coast: 'Less than 3 miles').perimeterSheets, 4);
    });
    test('steel 55 mph 61–100\' building → 2 sheets, 6" o.c.', () {
      final r = look('Metal', 55, h: 70);
      expect(r.perimeterSheets, 2);
      expect(r.spacingIn, 6);
    });
    test('wood 7/16 OSB 55 mph 10\' → 9" o.c.', () {
      expect(look('Wood', 55, wood: '7/16" OSB').spacingIn, 9);
    });
    test('wood at 80 mph is outside the tables', () {
      expect(look('Wood', 80).status, VersicoMaStatus.contactVersico);
    });
    test('LW concrete 12\' sheets < 3 mi is N/A', () {
      expect(look('LW Concrete', 55, field: "12'", coast: 'Less than 3 miles').status,
          VersicoMaStatus.notAcceptable);
    });
    test('gypsum 8\'/4\' < 3 mi → 4 sheets, 9" o.c.', () {
      final r = look('Gypsum', 55, field: "8'", perim: "4'", coast: 'Less than 3 miles');
      expect(r.perimeterSheets, 4);
      expect(r.spacingIn, 9);
    });
    test('12\' sheets at 80 mph not listed → warning fallback 6"', () {
      final r = look('Metal', 80, field: "12'");
      expect(r.status, VersicoMaStatus.sheetWidthNotListed);
      expect(r.spacingIn, 6);
    });
  });

  test('QXO pack sizes by length', () {
    expect(qxoFastenerPack('Versico HPV', 8), 500);
    expect(qxoFastenerPack('Versico HPV', 6), 1000);
    expect(qxoFastenerPack('Versico HPVX', 4), 1000);
    expect(qxoFastenerPack('Versico HPVX', 5), 500);
    expect(qxoFastenerPack('Versico MP 14-10', 14), 250);
    expect(qxoFastenerPack('Versico CD-10', 4.25), kDefaultFastenerPack);
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
      final r = _calc(geometry: stale,
          membrane: const MembraneSystem(fieldAttachment: 'Fully Adhered'));
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
      expect(both.unit, 'cartons');
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
      // MA: 1 perimeter sheet band (6' − 5.5") around 400 LF
      const perimNet = 6 - 5.5 / 12;
      const perimArea = 400 * perimNet - 4 * perimNet * perimNet;
      final fieldRolls = ((10000 - perimArea) / 1000).ceil();
      expect(tape.trace.baseQty * 100,
          closeTo((fieldRolls - 1) * 100 + perimArea / 6, 0.5));
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
