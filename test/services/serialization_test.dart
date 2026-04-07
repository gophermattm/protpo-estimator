import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/serialization.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/drainage_zone.dart';
import 'package:protpo_app/models/roof_geometry.dart';

void main() {
  group('Schema v2 serialization', () {
    test('InsulationSystem round-trip with taper defaults', () {
      final system = InsulationSystem(
        numberOfLayers: 2,
        layer1: const InsulationLayer(type: 'Polyiso', thickness: 2.5, attachmentMethod: 'Mechanically Attached'),
        layer2: const InsulationLayer(type: 'Polyiso', thickness: 2.0, attachmentMethod: 'Mechanically Attached'),
        hasTaper: true,
        taperDefaults: TaperDefaults.initial(),
        hasCoverBoard: true,
        coverBoard: const CoverBoard(type: 'HD Polyiso', thickness: 0.5, attachmentMethod: 'Adhered'),
      );

      final json = insulationSystemToJson(system);
      final restored = insulationSystemFromJson(json);

      expect(restored.hasTaper, true);
      expect(restored.taperDefaults, isNotNull);
      expect(restored.taperDefaults!.taperRate, '1/4:12');
      expect(restored.taperDefaults!.manufacturer, 'Versico');
      expect(restored.taperDefaults!.profileType, 'extended');
      expect(restored.taperDefaults!.minThickness, 1.0);
      expect(restored.taperDefaults!.attachmentMethod, 'Mechanically Attached');
      expect(restored.zoneOverrides, isEmpty);
      expect(restored.numberOfLayers, 2);
      expect(restored.hasCoverBoard, true);
    });

    test('InsulationSystem round-trip with zone overrides', () {
      final system = InsulationSystem(
        hasTaper: true,
        taperDefaults: TaperDefaults.initial(),
        zoneOverrides: const [
          DrainageZoneOverride(zoneId: 'z1', taperRateOverride: '1/8:12'),
        ],
      );

      final json = insulationSystemToJson(system);
      final restored = insulationSystemFromJson(json);

      expect(restored.zoneOverrides.length, 1);
      expect(restored.zoneOverrides.first.zoneId, 'z1');
      expect(restored.zoneOverrides.first.taperRateOverride, '1/8:12');
      expect(restored.zoneOverrides.first.minThicknessOverride, isNull);
    });

    test('InsulationSystem round-trip without taper', () {
      const system = InsulationSystem(hasTaper: false);
      final json = insulationSystemToJson(system);
      final restored = insulationSystemFromJson(json);
      expect(restored.hasTaper, false);
      expect(restored.taperDefaults, isNull);
    });

    test('RoofGeometry round-trip with scuppers and zones', () {
      final geo = RoofGeometry(
        shapes: [RoofShape.initial(1)],
        scupperLocations: const [ScupperLocation(edgeIndex: 2, position: 0.5)],
        drainageZones: const [
          DrainageZone(id: 'z1', type: 'scupper', lowPointIndex: 0),
        ],
      );

      final json = roofGeometryToJson(geo);
      final restored = roofGeometryFromJson(json);

      expect(restored.scupperLocations.length, 1);
      expect(restored.scupperLocations.first.edgeIndex, 2);
      expect(restored.scupperLocations.first.position, 0.5);
      expect(restored.drainageZones.length, 1);
      expect(restored.drainageZones.first.id, 'z1');
      expect(restored.drainageZones.first.type, 'scupper');
    });
  });

  group('Schema v1 migration', () {
    test('old hasTaperedInsulation migrates to hasTaper', () {
      final oldJson = {
        'numberOfLayers': 1,
        'layer1': {'type': 'Polyiso', 'thickness': 2.5, 'attachmentMethod': 'Mechanically Attached'},
        'hasTaperedInsulation': true,
        'tapered': {
          'boardType': 'VersiCore Tapered',
          'taperSlope': '1/4:12',
          'minThicknessAtDrain': 1.0,
          'maxThickness': 5.0,
          'systemArea': 1000.0,
          'attachmentMethod': 'Mechanically Attached',
        },
        'hasCoverBoard': false,
      };

      final restored = insulationSystemFromJson(oldJson);
      expect(restored.hasTaper, true);
      expect(restored.taperDefaults, isNotNull);
      expect(restored.taperDefaults!.taperRate, '1/4:12');
      expect(restored.taperDefaults!.minThickness, 1.0);
      expect(restored.taperDefaults!.attachmentMethod, 'Mechanically Attached');
    });

    test('old InsulationSystem without taper migrates cleanly', () {
      final oldJson = {
        'numberOfLayers': 1,
        'layer1': {'type': 'Polyiso', 'thickness': 2.5, 'attachmentMethod': 'Mechanically Attached'},
        'hasTaperedInsulation': false,
        'hasCoverBoard': false,
      };

      final restored = insulationSystemFromJson(oldJson);
      expect(restored.hasTaper, false);
      expect(restored.taperDefaults, isNull);
    });

    test('old RoofGeometry without scuppers/zones loads cleanly', () {
      final oldJson = {
        'shapes': [],
        'buildingHeight': 20.0,
        'roofSlope': 'Flat',
        'drainLocations': [{'x': 10.0, 'y': 15.0}],
      };

      final restored = roofGeometryFromJson(oldJson);
      expect(restored.scupperLocations, isEmpty);
      expect(restored.drainageZones, isEmpty);
      expect(restored.drainLocations.length, 1);
    });
  });
}
