/// lib/services/uom_reconciler.dart
///
/// Reconciles the BOM's package unit ("boxes", "rolls", "pails"…) with the
/// unit of measure QXO prices the matched SKU in ("BX", "EA", "RL"…).
///
/// Why: line total = QXO unit price × BOM order qty. If the BOM counts boxes
/// of 500 fasteners and QXO prices per EA, the total is off by 500× and
/// nothing said so (eval F9). This module never converts — it only classifies
/// both sides and reports match / mismatch / unknown so the UI can flag it.
///
/// Unknown codes classify as [UnitClass.unknown] and reconcile as
/// [UomStatus.unknown]: no false alarms on UOM strings we have not seen.
/// Add aliases to [_aliases] as real QXO codes show up.

enum UnitClass {
  each,      // EA, PC, PCS, piece(s), each, set(s), kit(s)
  roll,      // RL, roll(s)
  box,       // BX, box(es), CTN, carton(s), CS, case(s), PK, pack(s)
  bucket,    // BKT, bucket(s), PL, pail(s)
  cylinder,  // CYL, cylinder(s), can(s), aerosol(s)
  gallon,    // GAL, gallon(s)
  tube,      // TB, tube(s), CTG, cartridge(s)
  bottle,    // BT, BTL, bottle(s)
  board,     // BD, board(s), SH, sheet(s)
  unknown,
}

enum UomStatus { match, mismatch, unknown }

const Map<String, UnitClass> _aliases = {
  // each
  'ea': UnitClass.each, 'each': UnitClass.each, 'pc': UnitClass.each,
  'pcs': UnitClass.each, 'piece': UnitClass.each, 'pieces': UnitClass.each,
  'set': UnitClass.each, 'sets': UnitClass.each, 'st': UnitClass.each,
  'kit': UnitClass.each, 'kits': UnitClass.each, 'unit': UnitClass.each,
  // roll
  'rl': UnitClass.roll, 'roll': UnitClass.roll, 'rolls': UnitClass.roll,
  // box / carton / case / pack
  'bx': UnitClass.box, 'box': UnitClass.box, 'boxes': UnitClass.box,
  'ctn': UnitClass.box, 'ct': UnitClass.box, 'carton': UnitClass.box,
  'cartons': UnitClass.box, 'cs': UnitClass.box, 'case': UnitClass.box,
  'cases': UnitClass.box, 'pk': UnitClass.box, 'pack': UnitClass.box,
  'packs': UnitClass.box, 'pkg': UnitClass.box,
  // bucket / pail
  'bkt': UnitClass.bucket, 'bucket': UnitClass.bucket, 'buckets': UnitClass.bucket,
  'pl': UnitClass.bucket, 'pail': UnitClass.bucket, 'pails': UnitClass.bucket,
  // cylinder / can / aerosol
  'cyl': UnitClass.cylinder, 'cylinder': UnitClass.cylinder,
  'cylinders': UnitClass.cylinder, 'can': UnitClass.cylinder,
  'cans': UnitClass.cylinder, 'aerosol': UnitClass.cylinder,
  'aerosols': UnitClass.cylinder,
  // gallon
  'gal': UnitClass.gallon, 'gallon': UnitClass.gallon, 'gallons': UnitClass.gallon,
  // tube / cartridge
  'tb': UnitClass.tube, 'tube': UnitClass.tube, 'tubes': UnitClass.tube,
  'ctg': UnitClass.tube, 'cartridge': UnitClass.tube, 'cartridges': UnitClass.tube,
  // bottle
  'bt': UnitClass.bottle, 'btl': UnitClass.bottle, 'bottle': UnitClass.bottle,
  'bottles': UnitClass.bottle,
  // board / sheet
  'bd': UnitClass.board, 'board': UnitClass.board, 'boards': UnitClass.board,
  'sh': UnitClass.board, 'sheet': UnitClass.board, 'sheets': UnitClass.board,
};

UnitClass classifyUnit(String? raw) {
  if (raw == null) return UnitClass.unknown;
  final key = raw.trim().toLowerCase();
  if (key.isEmpty) return UnitClass.unknown;
  return _aliases[key] ?? UnitClass.unknown;
}

UomStatus reconcileUom({required String? bomUnit, required String? qxoUom}) {
  final a = classifyUnit(bomUnit);
  final b = classifyUnit(qxoUom);
  if (a == UnitClass.unknown || b == UnitClass.unknown) return UomStatus.unknown;
  return a == b ? UomStatus.match : UomStatus.mismatch;
}

/// Short human label for a mismatch, e.g. 'BOM: boxes / QXO: EA'.
String uomMismatchLabel({required String? bomUnit, required String? qxoUom}) =>
    'BOM: ${bomUnit ?? "?"} / QXO: ${qxoUom ?? "?"}';
