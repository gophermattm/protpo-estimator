import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/project_info.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/services/r_value_calculator.dart';
import 'package:protpo_app/services/serialization.dart';
import 'package:protpo_app/services/validation_engine.dart';
import 'bom_test_helpers.dart';

void main() {
  test('cover board attachment follows membrane', () {
    expect(coverBoardAttachmentFor('Mechanically Attached', 'HD Polyiso'), 'Mechanically Attached');
    expect(coverBoardAttachmentFor('Rhinobond (Induction Welded)', 'Gypsum'), 'Mechanically Attached');
    expect(coverBoardAttachmentFor('Fully Adhered', 'HD Polyiso'), 'Adhered');
    expect(coverBoardAttachmentFor('Fully Adhered', kCoverBoardNailbase), 'Mechanically Attached');
  });

  test('enabling cover board on MA job gives MA cover board and no OlyBond', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(estimatorProvider.notifier).setCoverBoardEnabled(true);
    final ins = c.read(estimatorProvider).activeBuilding.insulationSystem;
    expect(ins.coverBoard!.attachmentMethod, 'Mechanically Attached');
    final r = calc(insulation: ins);
    expect(r.items.where((i) => i.skuKey == 'adhesive_olybond_500_set'), isEmpty);
  });

  test('missing stored attachment loads as MA', () {
    final ins = insulationSystemFromJson({'hasCoverBoard': true, 'coverBoard': {'type': 'HD Polyiso'}});
    expect(ins.coverBoard!.attachmentMethod, 'Mechanically Attached');
  });

  test('nailbase thicknesses and R lookup', () {
    expect(coverBoardThicknessesFor(kCoverBoardNailbase), [1.5, 2.0, 2.5, 3.0, 3.5, 4.0]);
    expect(coverBoardThicknessesFor('HD Polyiso'), kCoverBoardThicknesses);
    final r = RValueCalculator.calculate(
      layer1: const InsulationLayerInput(materialType: 'Polyiso', thickness: 2.0),
      coverBoard: const CoverBoardInput(materialType: kCoverBoardNailbase, thickness: 2.5),
    );
    expect(r.coverBoard!.rValue, 12.0);
  });

  test('nailbase BOM line', () {
    final r = calc(insulation: const InsulationSystem(hasCoverBoard: true,
        coverBoard: CoverBoard(type: kCoverBoardNailbase, thickness: 2.5,
            attachmentMethod: 'Mechanically Attached')));
    final l = r.items.singleWhere((i) => i.skuKey == 'insulation_nailbase');
    expect(l.name, 'Nailbase (Polyiso + 7/16" OSB) 2.5" \u2014 Cover Board');
  });

  test('adhered layer 1 on metal deck warns', () {
    const ins = InsulationSystem(
        layer1: InsulationLayer(attachmentMethod: 'Adhered'));
    final v = ValidationEngine.validate(
      projectInfo: ProjectInfo.initial(),
      geometry: geo100(),
      systemSpecs: const SystemSpecs(deckType: 'Metal'),
      insulation: ins,
      membrane: const MembraneSystem(),
      parapet: const ParapetWalls(),
      penetrations: const Penetrations(),
      metalScope: const MetalScope(),
      bom: calc(insulation: ins),
    );
    expect(v.issues.any((i) => i.message.contains('steel deck')), true);
  });
}
