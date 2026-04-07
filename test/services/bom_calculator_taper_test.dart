import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/services/bom_calculator.dart';
import 'package:protpo_app/services/board_schedule_calculator.dart';
import 'package:protpo_app/models/project_info.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/models/drainage_zone.dart';

void main() {
  group('BOM — tapered insulation with board schedule', () {
    late BoardScheduleResult schedule;

    setUp(() {
      schedule = BoardScheduleCalculator.compute(const BoardScheduleInput(
        distance: 47,
        taperRate: '1/4:12',
        minThickness: 1.0,
        manufacturer: 'Versico',
        profileType: 'extended',
        roofWidthFt: 27,
      ));
    });

    test('produces per-panel BOM lines instead of placeholder', () {
      final result = BomCalculator.calculate(
        projectInfo: ProjectInfo.initial(),
        geometry: RoofGeometry(
          shapes: [RoofShape(shapeIndex: 1, edgeLengths: [47, 27, 47, 27],
              edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'])],
          drainLocations: [DrainLocation(x: 23.5, y: -13.5)],
        ),
        systemSpecs: SystemSpecs.initial(),
        insulation: InsulationSystem(
          hasTaper: true,
          taperDefaults: const TaperDefaults(
            taperRate: '1/4:12',
            minThickness: 1.0,
            manufacturer: 'Versico',
            profileType: 'extended',
          ),
        ),
        membrane: MembraneSystem.initial(),
        parapet: ParapetWalls.initial(),
        penetrations: Penetrations.initial(),
        metalScope: MetalScope.initial(),
        boardSchedule: schedule,
      );

      final insulItems = result.items
          .where((i) => i.category == 'Insulation' && i.name.contains('Tapered'))
          .toList();
      expect(insulItems.length, greaterThan(1),
          reason: 'Should have multiple tapered panel lines, not one placeholder');

      final flatFillItems = result.items
          .where((i) => i.category == 'Insulation' && i.name.contains('Flat Fill'))
          .toList();
      expect(flatFillItems.length, greaterThan(0));
    });

    test('falls back to placeholder when no board schedule provided', () {
      final result = BomCalculator.calculate(
        projectInfo: ProjectInfo.initial(),
        geometry: RoofGeometry(
          shapes: [RoofShape(shapeIndex: 1, edgeLengths: [47, 27, 47, 27],
              edgeTypes: ['Eave', 'Rake Edge', 'Eave', 'Rake Edge'])],
        ),
        systemSpecs: SystemSpecs.initial(),
        insulation: InsulationSystem(
          hasTaper: true,
          taperDefaults: const TaperDefaults(),
        ),
        membrane: MembraneSystem.initial(),
        parapet: ParapetWalls.initial(),
        penetrations: Penetrations.initial(),
        metalScope: MetalScope.initial(),
      );

      final taperItems = result.items
          .where((i) => i.category == 'Insulation' && i.name.contains('Tapered'))
          .toList();
      expect(taperItems.length, 1);
    });
  });
}
