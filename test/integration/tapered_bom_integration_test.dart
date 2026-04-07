import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/drainage_zone.dart';

void main() {
  group('Tapered insulation end-to-end', () {
    test('47x27 roof with centered drain produces correct BOM and R-values', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(estimatorProvider.notifier);

      // 1. Set up 47×27 roof with drain at center
      notifier.updateRoofGeometry(RoofGeometry(
        shapes: [
          RoofShape(
            shapeIndex: 1,
            shapeType: 'Rectangle',
            edgeLengths: [47, 27, 47, 27],
            edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'],
          ),
        ],
        drainLocations: [DrainLocation(x: 23.5, y: -13.5)],
      ));

      // 2. Configure insulation: 2 layers of polyiso (defaults: 2.5" each)
      notifier.setNumberOfLayers(2);

      // 3. Enable tapered insulation: Versico extended 1/4":12
      notifier.setTaperedEnabled(true);
      notifier.updateTaperDefaults(const TaperDefaults(
        taperRate: '1/4:12',
        minThickness: 1.0,
        manufacturer: 'Versico',
        profileType: 'extended',
        attachmentMethod: 'Mechanically Attached',
      ));

      // 4. Verify board schedule computed
      final schedule = container.read(boardScheduleProvider);
      expect(schedule, isNotNull, reason: 'Board schedule should compute with drain placed');
      expect(schedule!.totalTaperedPanels, greaterThan(0));
      expect(schedule.maxThicknessAtRidge, greaterThan(1.0));

      // 5. Verify R-value includes tapered component
      final rValue = container.read(rValueResultProvider);
      expect(rValue, isNotNull);
      expect(rValue!.tapered, isNotNull, reason: 'Tapered R-value should be calculated');
      expect(rValue.tapered!.averageRValue, greaterThan(0));
      // Total should include base layers + tapered + membrane
      expect(rValue.totalRValue, greaterThan(30),
          reason: '2.5" + 2.5" polyiso + taper avg should exceed R-30');

      // 6. Verify BOM has detailed panel lines
      final bom = container.read(bomProvider);
      final taperItems = bom.items
          .where((i) => i.category == 'Insulation' &&
              (i.name.contains('Tapered') || i.name.contains('Flat Fill')))
          .toList();
      expect(taperItems.length, greaterThan(1),
          reason: 'BOM should have per-panel-type lines from board schedule');
    });

    test('disabling taper removes board schedule and detailed BOM lines', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(estimatorProvider.notifier);

      notifier.updateRoofGeometry(RoofGeometry(
        shapes: [
          RoofShape(
            shapeIndex: 1,
            shapeType: 'Rectangle',
            edgeLengths: [47, 27, 47, 27],
            edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'],
          ),
        ],
        drainLocations: [DrainLocation(x: 23.5, y: -13.5)],
      ));
      notifier.setTaperedEnabled(true);

      // Verify it's on
      expect(container.read(boardScheduleProvider), isNotNull);

      // Turn it off
      notifier.setTaperedEnabled(false);
      expect(container.read(boardScheduleProvider), isNull);

      // BOM should have no tapered panel lines
      final bom = container.read(bomProvider);
      final taperItems = bom.items
          .where((i) => i.name.contains('Tapered') || i.name.contains('Flat Fill'))
          .toList();
      expect(taperItems, isEmpty);
    });
  });
}
