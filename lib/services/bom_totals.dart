/// lib/services/bom_totals.dart
///
/// Single source of truth for BOM material cost / sell value totals.
///
/// Used by the in-app pricing summary (center panel) AND the PDF export so
/// the printed grand total always equals the sum of the printed line totals.
/// Before this existed the PDF summed the raw QXO results and ignored qty and
/// price edits, deleted lines and manual lines (eval F10).
///
/// Line semantics (must match the row rendering everywhere):
///   cost  = (edit.unitPrice ?? priced.unitPrice) × (edit.qty ?? item.orderQty)
///   value = cost / (1 − margin)   where margin = override[name] ?? global
///   manual lines: unitPrice × qty, margin = override[description] ?? global
///   lines with no usable price are counted in [BomTotals.unpricedCount].

import '../models/labor_models.dart' show LaborLineItem;
import '../providers/estimator_providers.dart'
    show BomLineEdit, ManualBomItem, LaborLineEdit, ManualLaborItem;
import 'bom_calculator.dart' show BomLineItem;
import 'qxo_pricing_service.dart' show QxoPricedItem;

class BomTotals {
  final double cost;
  final double value;
  final int unpricedCount;
  const BomTotals({required this.cost, required this.value, required this.unpricedCount});

  static const zero = BomTotals(cost: 0, value: 0, unpricedCount: 0);
}

double _sell(double cost, double margin) =>
    margin < 1.0 ? cost / (1 - margin) : cost;

BomTotals computeBomTotals({
  required Iterable<BomLineItem> items,
  required Map<String, QxoPricedItem>? pricedItems,
  required double globalMargin,
  required Map<String, double> itemMarginOverrides,
  required Map<String, BomLineEdit> edits,
  required Set<String> deleted,
  required List<ManualBomItem> manualItems,
  bool includeFasteners = true,
}) {
  double cost = 0;
  double value = 0;
  int unpriced = 0;

  for (final item in items) {
    if (!item.hasQuantity) continue;
    if (!includeFasteners && item.category.toLowerCase().contains('fastener')) continue;
    final key = '${item.category}:${item.name}';
    if (deleted.contains(key)) continue;
    final edit = edits[key];
    final unitPrice = edit?.unitPrice ?? pricedItems?[item.name]?.unitPrice;
    final qty = edit?.qty ?? item.orderQty;
    if (unitPrice == null || unitPrice <= 0) {
      unpriced++;
      continue;
    }
    final lineCost = unitPrice * qty;
    cost += lineCost;
    value += _sell(lineCost, itemMarginOverrides[item.name] ?? globalMargin);
  }

  for (final m in manualItems) {
    final p = m.unitPrice;
    if (p == null || p <= 0) {
      unpriced++;
      continue;
    }
    final lineCost = p * m.qty;
    cost += lineCost;
    value += _sell(lineCost, itemMarginOverrides[m.description] ?? globalMargin);
  }

  return BomTotals(cost: cost, value: value, unpricedCount: unpriced);
}

/// Labor total with the same override semantics the labor table renders:
///   (edit.qty ?? item.quantity) × (edit.rate ?? item.rate), deleted skipped,
///   plus manual lines. Keyed by item name (matches laborLineEditsProvider).
double computeLaborTotal({
  required List<LaborLineItem> items,
  required Map<String, LaborLineEdit> edits,
  required Set<String> deleted,
  required List<ManualLaborItem> manualItems,
}) {
  double total = 0;
  for (final li in items) {
    if (deleted.contains(li.name)) continue;
    final le = edits[li.name];
    total += (le?.qty ?? li.quantity) * (le?.rate ?? li.rate);
  }
  for (final m in manualItems) {
    total += m.total;
  }
  return total;
}
