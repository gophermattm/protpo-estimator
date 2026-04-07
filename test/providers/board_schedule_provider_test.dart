import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/drainage_zone.dart';
import 'package:protpo_app/services/board_schedule_calculator.dart';

void main() {
  group('boardScheduleProvider', () {
    test('returns null when taper is disabled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final result = container.read(boardScheduleProvider);
      expect(result, isNull);
    });

    test('returns null when no drains are placed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(estimatorProvider.notifier).setTaperedEnabled(true);
      final result = container.read(boardScheduleProvider);
      expect(result, isNull);
    });

    test('returns BoardScheduleResult when taper enabled and drains placed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(estimatorProvider.notifier);
      notifier.updateRoofGeometry(RoofGeometry(
        shapes: [
          RoofShape(
            shapeIndex: 1,
            shapeType: 'Rectangle',
            edgeLengths: [100, 50, 100, 50],
            edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'],
          ),
        ],
        drainLocations: [DrainLocation(x: 50, y: -25)],
      ));
      notifier.setTaperedEnabled(true);
      final result = container.read(boardScheduleProvider);
      expect(result, isNotNull);
      expect(result!.rows.isNotEmpty, true);
      expect(result.totalTaperedPanels, greaterThan(0));
      expect(result.maxThickness, greaterThan(0));
    });

    test('result updates when taper config changes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(estimatorProvider.notifier);
      notifier.updateRoofGeometry(RoofGeometry(
        shapes: [
          RoofShape(
            shapeIndex: 1,
            shapeType: 'Rectangle',
            edgeLengths: [100, 50, 100, 50],
            edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'],
          ),
        ],
        drainLocations: [DrainLocation(x: 50, y: -25)],
      ));
      notifier.setTaperedEnabled(true);
      final result1 = container.read(boardScheduleProvider);

      notifier.updateTaperDefaults(const TaperDefaults(
        taperRate: '1/2:12',
        minThickness: 1.0,
        manufacturer: 'Versico',
        profileType: 'standard',
        attachmentMethod: 'Mechanically Attached',
      ));
      final result2 = container.read(boardScheduleProvider);
      expect(result2, isNotNull);
      expect(result2!.maxThickness, isNot(equals(result1!.maxThickness)));
    });

    test('rValueResultProvider uses maxThicknessAtRidge from board schedule', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(estimatorProvider.notifier);
      notifier.updateRoofGeometry(RoofGeometry(
        shapes: [
          RoofShape(
            shapeIndex: 1,
            shapeType: 'Rectangle',
            edgeLengths: [100, 50, 100, 50],
            edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'],
          ),
        ],
        drainLocations: [DrainLocation(x: 50, y: -25)],
      ));
      notifier.setTaperedEnabled(true);

      final boardSchedule = container.read(boardScheduleProvider);
      expect(boardSchedule, isNotNull);
      expect(boardSchedule!.maxThicknessAtRidge, greaterThan(0));

      // The R-value provider should now incorporate the tapered max thickness
      final rValue = container.read(rValueResultProvider);
      // With taper enabled and drains placed, it should have a tapered component
      expect(rValue, isNotNull);
    });
  });
}
