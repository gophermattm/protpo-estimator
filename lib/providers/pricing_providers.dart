/// lib/providers/pricing_providers.dart
///
/// Project-level money totals derived from the live BOM, QXO pricing,
/// user edits and labor. Kept out of estimator_providers.dart because
/// bom_totals.dart imports that file (avoids an import cycle).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/bom_totals.dart';
import 'estimator_providers.dart';

/// Material totals (cost / sell value / unpriced count) across all buildings.
final projectBomTotalsProvider = Provider<BomTotals>((ref) {
  final boms = ref.watch(allBuildingBomsProvider);
  return computeBomTotals(
    items: boms.expand((b) => b.activeItems),
    pricedItems: ref.watch(pricedItemsProvider),
    globalMargin: ref.watch(globalMarginProvider),
    itemMarginOverrides: ref.watch(itemMarginOverridesProvider),
    edits: ref.watch(bomLineEditsProvider),
    deleted: ref.watch(bomDeletedItemsProvider),
    manualItems: ref.watch(bomManualItemsProvider),
  );
});

/// Labor total (0 when labor is disabled).
final projectLaborTotalProvider = Provider<double>((ref) {
  if (!ref.watch(laborEnabledProvider)) return 0.0;
  return computeLaborTotal(
    items: ref.watch(laborLineItemsProvider),
    edits: ref.watch(laborLineEditsProvider),
    deleted: ref.watch(laborDeletedItemsProvider),
    manualItems: ref.watch(laborManualItemsProvider),
  );
});

/// Sell value of materials (with margin) plus labor — what an estimate is
/// worth. Persisted as Estimate.totalValue on save (was hardcoded 0, eval F14).
final projectTotalValueProvider = Provider<double>((ref) =>
    ref.watch(projectBomTotalsProvider).value + ref.watch(projectLaborTotalProvider));
