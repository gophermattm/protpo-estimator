/// Eval F11 — labor line items use their own rate keys and don't emit
/// phantom lines.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/drainage_zone.dart';
import 'package:protpo_app/models/labor_models.dart';

void main() {
  ProviderContainer setup() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(estimatorProvider.notifier);
    n.updateRoofGeometry(RoofGeometry(shapes: [
      const RoofShape(shapeIndex: 1, edgeLengths: [100, 50, 100, 50]),
    ]));
    c.read(laborEnabledProvider.notifier).state = true;
    // Distinct sentinel rates so a wrong key lookup is obvious.
    c.read(laborCrewsProvider.notifier).state = [
      const LaborCrew(name: 'T', rates: {
        'Install Wall Flashing': 11.11,
        'Install Gutter': 22.22,
        'Install Sealant Pockets': 33.33,
        'Install Drip Edge and Tape': 1.01,
        'Install Cap Metal (per foot)': 2.02,
        'Install Custom Curb (exhaust fan)': 3.03,
      }),
    ];
    return c;
  }

  double rateOf(ProviderContainer c, String prefix) => c
      .read(laborLineItemsProvider)
      .firstWhere((i) => i.name.startsWith(prefix))
      .rate;

  test('wall flashing, gutter and sealant pockets use their own crew rates', () {
    final c = setup();
    final n = c.read(estimatorProvider.notifier);
    n.updateMetalScope(const MetalScope(wallFlashingLF: 10, gutterLF: 10));
    n.updatePenetrations(const Penetrations(pitchPanCount: 2));
    expect(rateOf(c, 'Install Wall Flashing'), 11.11);
    expect(rateOf(c, 'Install Gutter'), 22.22);
    expect(rateOf(c, 'Install Sealant Pockets'), 33.33);
  });

  test('tapered-only insulation (0 flat layers) emits no Layer 1 ISO labor', () {
    final c = setup();
    c.read(estimatorProvider.notifier).updateInsulationSystem(
        const InsulationSystem(numberOfLayers: 0, hasTaper: true, taperDefaults: TaperDefaults()));
    final names = c.read(laborLineItemsProvider).map((i) => i.name).toList();
    expect(names.any((n) => n.startsWith('Install ISO Board')), isFalse);
    expect(names, contains('Install Taper System'));
  });
}
