// Shared by adhesive/nailer/edge BOM tests; not a test file (no main).
import 'package:protpo_app/models/insulation_system.dart';
import 'package:protpo_app/models/project_info.dart';
import 'package:protpo_app/models/roof_geometry.dart';
import 'package:protpo_app/models/section_models.dart';
import 'package:protpo_app/models/system_specs.dart';
import 'package:protpo_app/services/bom_calculator.dart';

RoofGeometry geo100() {
  final g = RoofGeometry(shapes: [
    RoofShape(shapeIndex: 1, edgeLengths: const [100, 100, 100, 100],
        edgeTypes: const ['Eave', 'Flat Drip Edge', 'Eave', 'Flat Drip Edge'])
  ], outsideCorners: 4);
  return g.copyWith(windZones: WindZones.fromDimensions(totalArea: g.totalArea,
      totalPerimeter: g.totalPerimeter, outsideCorners: 4, zoneWidth: 5));
}

BomResult calc({MembraneSystem membrane = const MembraneSystem(),
    ParapetWalls parapet = const ParapetWalls(),
    InsulationSystem insulation = const InsulationSystem(),
    MetalScope metal = const MetalScope(),
    String deck = 'Metal'}) =>
    BomCalculator.calculate(
      projectInfo: ProjectInfo.initial().copyWith(warrantyYears: 20, designWindSpeed: '115 mph'),
      geometry: geo100(), systemSpecs: SystemSpecs(deckType: deck),
      insulation: insulation, membrane: membrane, parapet: parapet,
      penetrations: const Penetrations(), metalScope: metal);

Iterable<BomLineItem> adhesives(BomResult r) =>
    r.items.where((i) => (i.skuKey ?? '').startsWith('adhesive_') && i.hasQuantity);
