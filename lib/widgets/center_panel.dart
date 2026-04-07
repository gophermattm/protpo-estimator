/// lib/widgets/center_panel.dart
///
/// Center panel — live BOM, Fastening Schedule, Thermal & Code, Scope of Work.
///
/// All data reads from Riverpod providers. Numbers update automatically as
/// inputs change in the left panel.
///
/// Hover math: every BOM row is tappable — tap to expand the full calculation
/// trace showing area → base qty → waste → order qty.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:convert';
import '../theme/app_theme.dart';
import 'ui_polish.dart';
import '../models/building_state.dart';
import '../models/section_models.dart';
import '../models/project_info.dart';
import '../providers/estimator_providers.dart';
import '../services/bom_calculator.dart';
import '../models/insulation_system.dart';
import '../services/platform_utils.dart';
import '../services/r_value_calculator.dart';
import '../widgets/roof_renderer.dart';
import 'package:intl/intl.dart';
import '../services/qxo_pricing_service.dart';
import '../services/sub_instructions_builder.dart';
import '../models/estimator_state.dart';
import '../models/labor_models.dart';

class CenterPanel extends ConsumerStatefulWidget {
  const CenterPanel({super.key});

  @override
  ConsumerState<CenterPanel> createState() => _CenterPanelState();
}

class _CenterPanelState extends ConsumerState<CenterPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// Which BOM row is currently expanded (showing hover math).
  /// Key = "$category:$name".
  final Set<String> _expandedRows = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Stack(children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primary,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            isScrollable: true,
            tabs: const [
              Tab(text: 'Materials Takeoff'),
              Tab(text: 'Fastening Schedule'),
              Tab(text: 'Thermal & Code'),
              Tab(text: 'Scope of Work'),
              Tab(text: 'Install Instructions'),
            ],
          ),
        ),
        // Right fade hint for scrollable tabs
        Positioned(right: 0, top: 0, bottom: 1, width: 24,
          child: IgnorePointer(child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white.withValues(alpha: 0), Colors.white],
              ),
            ),
          )),
        ),
      ]),
      Expanded(
        child: TabBarView(
          controller: _tabController,
          children: [
            _MaterialsTakeoffTab(
              expandedRows: _expandedRows,
              onToggle: (key) => setState(() {
                if (_expandedRows.contains(key)) {
                  _expandedRows.remove(key);
                } else {
                  _expandedRows.add(key);
                }
              }),
            ),
            const _FasteningScheduleTab(),
            const _ThermalCodeTab(),
            const _ScopeOfWorkTab(),
            const _SubInstructionsTab(),
          ],
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MATERIALS TAKEOFF TAB
// ══════════════════════════════════════════════════════════════════════════════

// ─── Materials Takeoff Tab ────────────────────────────────────────────────────
// When project has multiple buildings, shows a selector bar at the top.
// -1 = project total (aggregated BOM); 0..n = individual building BOM.

class _MaterialsTakeoffTab extends ConsumerStatefulWidget {
  final Set<String> expandedRows;
  final ValueChanged<String> onToggle;

  const _MaterialsTakeoffTab({required this.expandedRows, required this.onToggle});

  @override
  ConsumerState<_MaterialsTakeoffTab> createState() => _MaterialsTakeoffTabState();
}

class _MaterialsTakeoffTabState extends ConsumerState<_MaterialsTakeoffTab> {
  // -1 = project total, 0..n = building index
  int _sel = -1;

  // QXO pricing state — maps BOM item name → resolved QXO item with pricing
  Map<String, QxoPricedItem> _pricedItems = {};
  bool _loadingPrices = false;

  Future<void> _fetchPrices(BomResult bom) async {
    final activeItems = bom.activeItems;
    if (activeItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No BOM items to price. Add roof inputs first.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    setState(() => _loadingPrices = true);
    try {
      final bomNames = activeItems.map((item) => item.name).toList();
      final bomQuantities = {
        for (final item in activeItems)
          item.name: item.orderQty.ceil(),
      };
      debugPrint('[QXO] Fetching pricing for ${bomNames.length} items: ${bomNames.take(3)}...');
      final result = await QxoPricingService().fetchBomPricing(
        bomNames,
        bomQuantities: bomQuantities,
      );
      debugPrint('[QXO] Got pricing for ${result.length} items');
      setState(() {
        _pricedItems = result;
        _loadingPrices = false;
      });
      // Store in provider so export service can access pricing data
      ref.read(pricedItemsProvider.notifier).state = result;
      if (mounted && result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No matching QXO items found. Check item names.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[QXO] Pricing error: $e\n$st');
      setState(() => _loadingPrices = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pricing error: ${e.toString().split('\n').first}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMulti   = ref.watch(isMultiBuildingProvider);
    final allBoms   = ref.watch(allBuildingBomsProvider);
    final aggBom    = ref.watch(aggregateBomProvider);
    final buildings = ref.watch(estimatorProvider.select((s) => s.buildings));
    final geo       = ref.watch(roofGeometryProvider);
    final membrane  = ref.watch(membraneSystemProvider);
    final info      = ref.watch(projectInfoProvider);
    final parapet   = ref.watch(parapetWallsProvider);
    final rResult   = ref.watch(rValueResultProvider);

    // Clamp if buildings were removed
    final sel = isMulti ? _sel.clamp(-1, allBoms.length - 1) : 0;

    // Which BOM to display
    final BomResult bom;
    final bool isTotal;
    if (!isMulti) {
      bom = allBoms.isNotEmpty ? allBoms.first : aggBom;
      isTotal = false;
    } else if (sel == -1) {
      bom = aggBom;
      isTotal = true;
    } else {
      bom = allBoms[sel];
      isTotal = false;
    }

    // For summary chips area: include parapet area (adds to material qty)
    final displayArea = isTotal
        ? buildings.fold(0.0, (s, b) => s + b.roofGeometry.totalArea + b.parapetWalls.parapetArea)
        : geo.totalArea + parapet.parapetArea;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Materials Takeoff (BOM)', Icons.list_alt),
          const SizedBox(height: 16),

          // ── Building selector (multi-building only) ─────────────────────────
          if (isMulti) ...[
            _BuildingSelector(
              buildings:  buildings,
              allBoms:    allBoms,
              selected:   sel,
              onSelect:   (i) => setState(() => _sel = i),
            ),
            const SizedBox(height: 16),
          ],

          // ── Project total callout banner ────────────────────────────────────
          if (isTotal) ...[
            _TotalBanner(buildings: buildings, allBoms: allBoms),
            const SizedBox(height: 16),
          ],

          // ── Warnings / blockers ─────────────────────────────────────────────
          if (bom.warnings.isNotEmpty) ...[
            BomWarningList(warnings: bom.warnings),
            const SizedBox(height: 12),
          ],

          // ── Summary chips ────────────────────────────────────────────────────
          _SummaryChips(area: displayArea, membrane: membrane, info: info, totalRValue: rResult?.totalRValue ?? 0.0),
          const SizedBox(height: 12),

          // ── Fetch Pricing button ──────────────────────────────────────────
          Row(children: [
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: _loadingPrices ? null : () => _fetchPrices(bom),
                icon: _loadingPrices
                    ? SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.attach_money, size: 16),
                label: Text(_loadingPrices ? 'Loading...' : 'Fetch Pricing',
                    style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            if (_pricedItems.isNotEmpty) ...[
              const SizedBox(width: 10),
              Icon(Icons.check_circle, size: 16, color: AppTheme.accent),
              const SizedBox(width: 4),
              Text('${_pricedItems.length} items priced',
                  style: TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.w500)),
            ],
          ]),

          // ── Estimate Total Cost & Margin ─────────────────────────────────
          if (_pricedItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            _GlobalMarginInput(),
            const SizedBox(height: 10),
            _ProjectValueCard(pricedItems: _pricedItems),
          ],
          const SizedBox(height: 20),

          // ── Roof renderer (individual building only) ────────────────────────
          if (!isTotal && geo.totalArea > 0) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.roofing, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text('Roof Plan', style: TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const Spacer(),
                  Text('Zone visualization',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ]),
                const SizedBox(height: 12),
                const RoofRenderer(),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ── BOM categories ───────────────────────────────────────────────────
          if (!bom.isComplete && bom.items.isEmpty)
            BomEmptyState(blockers: bom.warnings)
          else
            ...bom.byCategory.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _BomCategoryCard(
                category:    entry.key,
                items:       entry.value,
                expandedRows: widget.expandedRows,
                onToggle:    widget.onToggle,
                pricedItems: _pricedItems,
              ),
            )),

          // Show restore button if items have been deleted
          Builder(builder: (ctx) {
            final deleted = ref.watch(bomDeletedItemsProvider);
            if (deleted.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.visibility_off, size: 16, color: Colors.amber.shade700),
                  const SizedBox(width: 8),
                  Text('${deleted.length} line item(s) hidden',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade800)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(bomDeletedItemsProvider.notifier).state = {},
                    icon: Icon(Icons.restore, size: 14, color: Colors.amber.shade800),
                    label: Text('Restore All',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade800)),
                  ),
                ]),
              ),
            );
          }),
          const SizedBox(height: 8),
          _hoverMathHint(),
        ],
      ),
    );
  }



  Widget _vDivider() => Container(
    width: 1, height: 36, color: AppTheme.border,
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );



  Widget _hoverMathHint() => Row(children: [
    Icon(Icons.touch_app, size: 13, color: AppTheme.textMuted),
    const SizedBox(width: 5),
    Text('Tap any row to see the full calculation breakdown.',
        style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
  ]);

}

// ── Top-level formatting helpers (used by multiple widgets in this file) ───────

String _fmt(double v) {
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
  return v.toStringAsFixed(0);
}

String _pct(double f) => (f * 100).toStringAsFixed(0);

Widget _vDivider() => Container(
  width: 1, height: 28,
  margin: const EdgeInsets.symmetric(horizontal: 6),
  color: AppTheme.primary.withValues(alpha:0.15),
);

Widget _hoverMathHint() => Row(children: [
  Icon(Icons.touch_app, size: 13, color: AppTheme.textMuted),
  const SizedBox(width: 5),
  Text('Tap any row to see the full calculation breakdown.',
      style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
]);

// ── Global Margin Input ───────────────────────────────────────────────────────

class _GlobalMarginInput extends ConsumerWidget {
  const _GlobalMarginInput();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final margin = ref.watch(globalMarginProvider);
    final pct = (margin * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        Icon(Icons.percent, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Text('Project Margin',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const Spacer(),
        SizedBox(width: 120, height: 28, child: Slider(
          value: margin,
          min: 0, max: 0.60,
          divisions: 60,
          onChanged: (v) => ref.read(globalMarginProvider.notifier).state = v,
        )),
        SizedBox(width: 40, child: Text('$pct%',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: AppTheme.primary), textAlign: TextAlign.right)),
      ]),
    );
  }
}

// ── Project Value Card (Cost + Margin = Sell Price) ──────────────────────────

class _ProjectValueCard extends ConsumerWidget {
  final Map<String, QxoPricedItem>? pricedItems;
  const _ProjectValueCard({required this.pricedItems});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final globalMargin = ref.watch(globalMarginProvider);
    final overrides = ref.watch(itemMarginOverridesProvider);
    final laborItems = ref.watch(laborLineItemsProvider);
    final laborEnabled = ref.watch(laborEnabledProvider);
    final deleted = ref.watch(bomDeletedItemsProvider);
    final edits = ref.watch(bomLineEditsProvider);
    final bom = ref.watch(allBuildingBomsProvider);
    final manualItems = ref.watch(bomManualItemsProvider);

    double totalCost = 0;
    double totalValue = 0;
    int unpricedCount = 0;

    // Calculate from live BOM items (respecting deletions and edits)
    for (final bomResult in bom) {
      for (final item in bomResult.activeItems) {
        final itemKey = '${item.category}:${item.name}';
        if (deleted.contains(itemKey)) continue;
        final edit = edits[itemKey];
        final priced = pricedItems?[item.name];
        final unitPrice = edit?.unitPrice ?? priced?.unitPrice;
        final qty = edit?.qty ?? item.orderQty;
        if (unitPrice != null && unitPrice > 0) {
          final lineCost = unitPrice * qty;
          totalCost += lineCost;
          final margin = overrides[item.name] ?? globalMargin;
          totalValue += margin < 1.0 ? lineCost / (1 - margin) : lineCost;
        } else {
          unpricedCount++;
        }
      }
    }

    // Add manual items
    for (final m in manualItems) {
      if (m.unitPrice != null && m.unitPrice! > 0) {
        final lineCost = m.unitPrice! * m.qty;
        totalCost += lineCost;
        totalValue += globalMargin < 1.0 ? lineCost / (1 - globalMargin) : lineCost;
      }
    }

    double laborTotal = 0;
    if (laborEnabled) {
      final laborDeleted = ref.watch(laborDeletedItemsProvider);
      final laborEdits = ref.watch(laborLineEditsProvider);
      final laborManual = ref.watch(laborManualItemsProvider);
      for (final li in laborItems) {
        if (laborDeleted.contains(li.name)) continue;
        final le = laborEdits[li.name];
        laborTotal += (le?.qty ?? li.quantity) * (le?.rate ?? li.rate);
      }
      for (final m in laborManual) laborTotal += m.total;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.accent.withValues(alpha:0.08), AppTheme.accent.withValues(alpha:0.03)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accent.withValues(alpha:0.3)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.receipt_long, size: 20, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Material Cost',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              if (unpricedCount > 0)
                Text('$unpricedCount items not yet priced',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
            ],
          )),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(currFmt.format(totalCost),
                key: ValueKey(totalCost),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary)),
          ),
        ]),
        if (laborEnabled && laborTotal > 0) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.engineering, size: 20, color: AppTheme.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text('Total Labor Cost',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(currFmt.format(laborTotal),
                  key: ValueKey(laborTotal),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
            ),
          ]),
        ],
        const Divider(height: 16),
        Row(children: [
          Icon(Icons.trending_up, size: 20, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(child: Text('Total Project Value',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary))),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(currFmt.format(totalValue + laborTotal),
                key: ValueKey(totalValue + laborTotal),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppTheme.accent)),
          ),
        ]),
      ]),
    );
  }
}

// ── Margin Chip (tappable to override per-item margin) ────────────────────────

class _MarginChip extends ConsumerWidget {
  final String itemName;
  final double margin;
  final bool isOverride;

  const _MarginChip({required this.itemName, required this.margin, required this.isOverride});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = (margin * 100).round();
    return GestureDetector(
      onTap: () => _showMarginDialog(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isOverride ? AppTheme.warning.withValues(alpha:0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isOverride ? Border.all(color: AppTheme.warning.withValues(alpha:0.4)) : null,
        ),
        child: Text('$pct%',
            style: TextStyle(fontSize: 11,
                fontWeight: isOverride ? FontWeight.w700 : FontWeight.w400,
                color: isOverride ? AppTheme.warning : AppTheme.textMuted),
            textAlign: TextAlign.right),
      ),
    );
  }

  void _showMarginDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: (margin * 100).round().toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Margin for ${itemName.length > 30 ? '${itemName.substring(0, 30)}...' : itemName}',
            style: const TextStyle(fontSize: 14)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Margin %',
              suffixText: '%',
              hintText: 'e.g. 30',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          if (ref.read(itemMarginOverridesProvider).containsKey(itemName))
            TextButton(
              onPressed: () {
                final overrides = Map<String, double>.from(ref.read(itemMarginOverridesProvider));
                overrides.remove(itemName);
                ref.read(itemMarginOverridesProvider.notifier).state = overrides;
                Navigator.of(ctx).pop();
              },
              child: const Text('Reset to Global'),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val >= 0 && val < 100) {
                final overrides = Map<String, double>.from(ref.read(itemMarginOverridesProvider));
                overrides[itemName] = val / 100;
                ref.read(itemMarginOverridesProvider.notifier).state = overrides;
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

// ── BOM Category Card ──────────────────────────────────────────────────────────

class _BomCategoryCard extends ConsumerWidget {
  final String category;
  final List<BomLineItem> items;
  final Set<String> expandedRows;
  final ValueChanged<String> onToggle;
  final Map<String, QxoPricedItem> pricedItems;

  static const Map<String, IconData> _catIcons = {
    'Membrane':               Icons.texture,
    'Insulation':             Icons.view_in_ar,
    'Fasteners & Plates':     Icons.hardware,
    'Adhesives & Sealants':   Icons.format_paint,
    'Parapet & Termination':  Icons.vertical_align_top,
    'Details & Accessories':  Icons.plumbing,
    'Metal Scope':            Icons.view_day,
    'Consumables':            Icons.construction,
    'Vapor Retarder':         Icons.water_drop,
  };

  const _BomCategoryCard({
    required this.category, required this.items,
    required this.expandedRows, required this.onToggle,
    required this.pricedItems,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon    = _catIcons[category] ?? Icons.list;
    final deleted = ref.watch(bomDeletedItemsProvider);
    final manualItems = ref.watch(bomManualItemsProvider)
        .where((m) => m.category == category).toList();
    final active  = items.where((i) =>
        i.hasQuantity && !deleted.contains('${i.category}:${i.name}')).toList();

    if (active.isEmpty && manualItems.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Category header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: AppTheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(category,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                    color: AppTheme.textPrimary))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${active.length + manualItems.length}', style: TextStyle(
                  fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            _AddLineItemButton(category: category),
          ]),
        ),

        // Column headers + rows — horizontally scrollable on mobile
        LayoutBuilder(builder: (context, constraints) {
          final needsScroll = constraints.maxWidth < 500;
          final content = Column(children: [
            // Column headers
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
              child: Row(children: [
                const SizedBox(width: 28),
                Expanded(flex: 3, child: Text('Item', style: _hdrStyle)),
                Expanded(flex: 3, child: Text('QXO Description', style: _hdrStyle)),
                SizedBox(width: 48, child: Text('Qty', style: _hdrStyle, textAlign: TextAlign.right)),
                SizedBox(width: 48, child: Text('Unit', style: _hdrStyle, textAlign: TextAlign.right)),
                SizedBox(width: 64, child: Text('Cost', style: _hdrStyle, textAlign: TextAlign.right)),
                SizedBox(width: 48, child: Text('Margin', style: _hdrStyle, textAlign: TextAlign.right)),
                SizedBox(width: 68, child: Text('Sell Price', style: _hdrStyle, textAlign: TextAlign.right)),
                SizedBox(width: 72, child: Text('Line Total', style: _hdrStyle, textAlign: TextAlign.right)),
              ]),
            ),
            // Calculated rows
            ...active.map((item) {
              final priced = pricedItems[item.name];
              return _BomRow(
                item: item,
                isExpanded: expandedRows.contains('${item.category}:${item.name}'),
                onToggle: () => onToggle('${item.category}:${item.name}'),
                pricedItem: priced,
              );
            }),
            // Manual rows
            ...manualItems.map((m) => _ManualBomRow(item: m)),
          ]);

          if (!needsScroll) return content;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 700),
              child: IntrinsicWidth(child: content),
            ),
          );
        }),
      ]),
    );
  }

  static TextStyle get _hdrStyle => TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary);
}

// ── BOM Row with hover math ────────────────────────────────────────────────────

class _BomRow extends ConsumerWidget {
  final BomLineItem item;
  final bool isExpanded;
  final VoidCallback onToggle;
  final QxoPricedItem? pricedItem;

  const _BomRow({required this.item, required this.isExpanded, required this.onToggle, this.pricedItem});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final globalMargin = ref.watch(globalMarginProvider);
    final overrides = ref.watch(itemMarginOverridesProvider);
    final itemMargin = overrides[item.name] ?? globalMargin;

    // Calculate sell price and line total — always use live BOM qty
    final costPerUnit = pricedItem?.unitPrice;
    final sellPerUnit = costPerUnit != null && itemMargin < 1.0
        ? costPerUnit / (1 - itemMargin) : costPerUnit;
    final lineTotal = sellPerUnit != null ? sellPerUnit * item.orderQty : null;

    final itemKey = '${item.category}:${item.name}';
    final edits = ref.watch(bomLineEditsProvider);
    final edit = edits[itemKey];

    // Apply overrides — always use live BOM qty (item.orderQty), not stale pricing qty
    final displayName = edit?.description ?? item.name;
    final displayQty = edit?.qty ?? item.orderQty;
    final displayPrice = edit?.unitPrice ?? costPerUnit;
    final displayPart = edit?.partNumber ?? pricedItem?.qxoItemNumber;

    final effectiveSell = displayPrice != null && itemMargin < 1.0
        ? displayPrice / (1 - itemMargin) : displayPrice;
    final effectiveLineTotal = effectiveSell != null ? effectiveSell * displayQty : null;

    return Column(children: [
      // Main row
      InkWell(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: isExpanded ? AppTheme.primary.withValues(alpha:0.03)
                : edit != null ? Colors.amber.withValues(alpha:0.04) : Colors.transparent,
            border: Border(bottom: BorderSide(
                color: isExpanded ? AppTheme.primary.withValues(alpha:0.1) : AppTheme.border.withValues(alpha:0.5))),
          ),
          child: Row(children: [
            // Delete + Edit buttons
            SizedBox(width: 28, child: Row(mainAxisSize: MainAxisSize.min, children: [
              _DeleteItemButton(itemKey: itemKey),
            ])),
            // Name + notes (double-tap to edit)
            Expanded(flex: 3, child: GestureDetector(
              onDoubleTap: () => _showEditDialog(context, ref, itemKey, item, pricedItem, edit),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(child: Text(displayName, style: TextStyle(fontSize: 13, color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500))),
                    if (edit != null) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.edit, size: 10, color: Colors.amber.shade700),
                    ],
                  ]),
                  if (item.notes.isNotEmpty)
                    Text(item.notes, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            )),
            // QXO Description (double-tap to edit)
            Expanded(flex: 3, child: GestureDetector(
              onDoubleTap: () => _showEditDialog(context, ref, itemKey, item, pricedItem, edit),
              child: pricedItem != null || displayPart != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pricedItem?.qxoProductName ?? displayName,
                          style: TextStyle(fontSize: 12, color: AppTheme.accent,
                              fontWeight: FontWeight.w500),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text('${pricedItem?.qxoBrand ?? ''} #${displayPart ?? ''}',
                          style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                    ],
                  )
                : Text('\u2014', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            )),
            // Qty (double-tap to edit)
            SizedBox(width: 48, child: GestureDetector(
              onDoubleTap: () => _showEditDialog(context, ref, itemKey, item, pricedItem, edit),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    displayQty == displayQty.roundToDouble()
                        ? displayQty.toInt().toString()
                        : displayQty.toStringAsFixed(1),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
                    textAlign: TextAlign.right,
                  ),
                  if (edit?.qty != null)
                    Text('was ${item.orderQty.toInt()}',
                        style: TextStyle(fontSize: 8, color: Colors.amber.shade700)),
                ],
              ),
            )),
            // Unit
            SizedBox(width: 48, child: Text(
                edit?.unit ?? pricedItem?.uom ?? item.unit,
                style: TextStyle(fontSize: 11, color: edit?.unit != null ? Colors.amber.shade700 : AppTheme.textSecondary),
                textAlign: TextAlign.right)),
            // Cost (double-tap to edit)
            SizedBox(width: 64, child: GestureDetector(
              onDoubleTap: () => _showEditDialog(context, ref, itemKey, item, pricedItem, edit),
              child: Text(
                displayPrice != null ? '\$${displayPrice.toStringAsFixed(2)}' : '\u2014',
                style: TextStyle(fontSize: 12, color: edit?.unitPrice != null ? Colors.amber.shade700 : AppTheme.textSecondary),
                textAlign: TextAlign.right,
              ),
            )),
            // Margin % — tappable to edit
            SizedBox(width: 48, child: _MarginChip(
              itemName: item.name,
              margin: itemMargin,
              isOverride: overrides.containsKey(item.name),
            )),
            // Sell Price (unit price with margin)
            SizedBox(width: 68, child: Text(
              effectiveSell != null ? '\$${effectiveSell.toStringAsFixed(2)}' : '\u2014',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
              textAlign: TextAlign.right,
            )),
            // Line Total (sell price × qty)
            SizedBox(width: 72, child: Text(
              effectiveLineTotal != null ? '\$${effectiveLineTotal.toStringAsFixed(2)}' : '\u2014',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accent),
              textAlign: TextAlign.right,
            )),
            // Expand chevron
            const SizedBox(width: 8),
            Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 16, color: AppTheme.textMuted),
          ]),
        ),
      ),

      // Hover math expansion
      if (isExpanded)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha:0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withValues(alpha:0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.calculate, size: 13, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text('Calculation Breakdown', style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppTheme.primary, letterSpacing: 0.3)),
              ]),
              const SizedBox(height: 8),
              ...item.trace.breakdown.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(line, style: TextStyle(
                    fontSize: 12,
                    color: line.startsWith('ORDER QTY') ? AppTheme.primary : AppTheme.textSecondary,
                    fontWeight: line.startsWith('ORDER QTY') ? FontWeight.w700 : FontWeight.w400,
                    fontFamily: 'monospace')),
              )),
              if (item.trace.wastePercent > 0) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Container(width: 3, height: 3, decoration: BoxDecoration(
                      color: AppTheme.warning, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(
                    '${(item.trace.baseQty).toStringAsFixed(2)} base '
                    '× ${(item.trace.wastePercent * 100).toStringAsFixed(0)}% waste '
                    '= ${item.trace.withWaste.toStringAsFixed(2)} → '
                    '${item.orderQty.toInt()} ordered',
                    style: TextStyle(fontSize: 11, color: AppTheme.warning),
                  ),
                ]),
              ],
            ],
          ),
        ),
    ]);
  }
}

// ── Edit Dialog for BOM line items ────────────────────────────────────────────

void _showEditDialog(BuildContext context, WidgetRef ref, String itemKey,
    BomLineItem item, QxoPricedItem? pricedItem, BomLineEdit? existingEdit) {
  final descCtrl = TextEditingController(text: existingEdit?.description ?? item.name);
  final partCtrl = TextEditingController(text: existingEdit?.partNumber ?? pricedItem?.qxoItemNumber ?? '');
  final qtyCtrl = TextEditingController(text: (existingEdit?.qty ?? item.orderQty).toStringAsFixed(
      (existingEdit?.qty ?? item.orderQty) == (existingEdit?.qty ?? item.orderQty).roundToDouble() ? 0 : 1));
  final priceCtrl = TextEditingController(
      text: (existingEdit?.unitPrice ?? pricedItem?.unitPrice)?.toStringAsFixed(2) ?? '');
  final unitCtrl = TextEditingController(text: existingEdit?.unit ?? pricedItem?.uom ?? item.unit);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(Icons.edit, size: 20, color: AppTheme.primary),
        const SizedBox(width: 8),
        const Text('Edit Line Item', style: TextStyle(fontSize: 16)),
        const Spacer(),
        if (existingEdit != null)
          TextButton.icon(
            icon: Icon(Icons.undo, size: 14, color: Colors.red.shade400),
            label: Text('Reset', style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
            onPressed: () {
              ref.read(bomLineEditsProvider.notifier).update((m) {
                final copy = Map<String, BomLineEdit>.from(m);
                copy.remove(itemKey);
                return copy;
              });
              Navigator.pop(ctx);
            },
          ),
      ]),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: descCtrl,
            decoration: const InputDecoration(labelText: 'Description', isDense: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: partCtrl,
            decoration: const InputDecoration(labelText: 'Part # / QXO Item Number', isDense: true),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity', isDense: true),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: unitCtrl,
              decoration: const InputDecoration(labelText: 'Unit', isDense: true),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Unit Price (\$)', isDense: true),
            )),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final newDesc = descCtrl.text != item.name ? descCtrl.text : null;
            final newPart = partCtrl.text.isNotEmpty && partCtrl.text != (pricedItem?.qxoItemNumber ?? '')
                ? partCtrl.text : null;
            final newQty = double.tryParse(qtyCtrl.text);
            final qtyOverride = newQty != null && newQty != item.orderQty ? newQty : null;
            final newPrice = double.tryParse(priceCtrl.text);
            final priceOverride = newPrice != null ? newPrice : null;
            final origUnit = pricedItem?.uom ?? item.unit;
            final unitOverride = unitCtrl.text.isNotEmpty && unitCtrl.text != origUnit
                ? unitCtrl.text : null;

            final edit = BomLineEdit(
              description: newDesc,
              partNumber: newPart,
              qty: qtyOverride,
              unitPrice: priceOverride,
              unit: unitOverride,
            );
            if (edit.hasOverrides) {
              ref.read(bomLineEditsProvider.notifier).update((m) =>
                  {...m, itemKey: edit});
            }
            Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// ── Delete item button ────────────────────────────────────────────────────────

class _DeleteItemButton extends ConsumerWidget {
  final String itemKey;
  const _DeleteItemButton({required this.itemKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
        padding: EdgeInsets.zero,
        iconSize: 14,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(Icons.close, color: Colors.red.shade300),
        tooltip: 'Remove line item',
        onPressed: () {
          ref.read(bomDeletedItemsProvider.notifier).update((s) => {...s, itemKey});
        },
      );
  }
}

// ── Add line item button ──────────────────────────────────────────────────────

class _AddLineItemButton extends ConsumerWidget {
  final String category;
  const _AddLineItemButton({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 24,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(Icons.add, size: 14, color: AppTheme.accent),
        label: Text('Add', style: TextStyle(fontSize: 11, color: AppTheme.accent)),
        onPressed: () => _showAddDialog(context, ref, category),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref, String category) {
    final descCtrl = TextEditingController();
    final partCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final unitCtrl = TextEditingController(text: 'each');
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.add_circle, size: 20, color: AppTheme.accent),
          const SizedBox(width: 8),
          Text('Add to $category', style: const TextStyle(fontSize: 16)),
        ]),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Description *', isDense: true),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: partCtrl,
              decoration: const InputDecoration(labelText: 'Part # (optional)', isDense: true),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity', isDense: true),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: unitCtrl,
                decoration: const InputDecoration(labelText: 'Unit', isDense: true),
              )),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Unit Price (\$, optional)', isDense: true),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (descCtrl.text.isEmpty) return;
              final newItem = ManualBomItem(
                id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
                category: category,
                description: descCtrl.text,
                partNumber: partCtrl.text,
                qty: double.tryParse(qtyCtrl.text) ?? 1.0,
                unit: unitCtrl.text.isEmpty ? 'each' : unitCtrl.text,
                unitPrice: double.tryParse(priceCtrl.text),
              );
              ref.read(bomManualItemsProvider.notifier).update((list) => [...list, newItem]);
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ── Manual BOM row (user-added items) ─────────────────────────────────────────

class _ManualBomRow extends ConsumerWidget {
  final ManualBomItem item;
  const _ManualBomRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final globalMargin = ref.watch(globalMarginProvider);
    final sellPrice = item.unitPrice != null && globalMargin < 1.0
        ? item.unitPrice! / (1 - globalMargin) : item.unitPrice;
    final lineTotal = sellPrice != null ? sellPrice * item.qty : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha:0.03),
        border: Border(bottom: BorderSide(color: AppTheme.border.withValues(alpha:0.5))),
      ),
      child: Row(children: [
        // Delete
        SizedBox(width: 44, child: IconButton(
            padding: EdgeInsets.zero, iconSize: 14,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(Icons.close, color: Colors.red.shade300),
            onPressed: () {
              ref.read(bomManualItemsProvider.notifier).update(
                  (list) => list.where((m) => m.id != item.id).toList());
            },
          ),
        ),
        // Description
        Expanded(flex: 3, child: Row(children: [
          Icon(Icons.person_add, size: 10, color: AppTheme.accent),
          const SizedBox(width: 4),
          Flexible(child: Text(item.description, style: TextStyle(fontSize: 13,
              color: AppTheme.textPrimary, fontWeight: FontWeight.w500))),
        ])),
        // Part #
        Expanded(flex: 3, child: item.partNumber.isNotEmpty
            ? Text('#${item.partNumber}', style: TextStyle(fontSize: 12, color: AppTheme.accent))
            : Text('\u2014', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
        // Qty
        SizedBox(width: 48, child: Text(
          item.qty == item.qty.roundToDouble() ? item.qty.toInt().toString() : item.qty.toStringAsFixed(1),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
          textAlign: TextAlign.right,
        )),
        // Unit
        SizedBox(width: 48, child: Text(item.unit,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary), textAlign: TextAlign.right)),
        // Cost
        SizedBox(width: 64, child: Text(
          item.unitPrice != null ? '\$${item.unitPrice!.toStringAsFixed(2)}' : '\u2014',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary), textAlign: TextAlign.right)),
        // Margin
        SizedBox(width: 48, child: Text('${(globalMargin * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted), textAlign: TextAlign.right)),
        // Sell Price
        SizedBox(width: 68, child: Text(
          sellPrice != null ? '\$${sellPrice.toStringAsFixed(2)}' : '\u2014',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
          textAlign: TextAlign.right)),
        // Line Total
        SizedBox(width: 72, child: Text(
          lineTotal != null ? '\$${lineTotal.toStringAsFixed(2)}' : '\u2014',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accent),
          textAlign: TextAlign.right)),
        const SizedBox(width: 24), // align with expand chevron space
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FASTENING SCHEDULE TAB
// ══════════════════════════════════════════════════════════════════════════════

// ─── Multi-building selector ──────────────────────────────────────────────────

class _BuildingSelector extends StatelessWidget {
  final List<BuildingState> buildings;
  final List<BomResult> allBoms;
  final int selected;          // -1 = total
  final ValueChanged<int> onSelect;

  const _BuildingSelector({
    required this.buildings,
    required this.allBoms,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _chip(
            label: 'Project Total',
            sub:   '${allBoms.fold(0, (s, b) => s + b.activeItems.length)} items',
            icon:  Icons.account_balance,
            idx:   -1,
            isTotal: true,
          ),
          const SizedBox(width: 4),
          ...List.generate(buildings.length, (i) {
            final b    = buildings[i];
            final area = b.roofGeometry.totalArea;
            final ok   = i < allBoms.length && allBoms[i].activeItems.isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _chip(
                label: b.buildingName,
                sub:   area > 0 ? '${area.toStringAsFixed(0)} sf' : 'No area',
                icon:  Icons.roofing,
                idx:   i,
                isTotal: false,
                warn:  !ok,
              ),
            );
          }),
        ]),
      ),
    );
  }

  Widget _chip({
    required String label,
    required String sub,
    required IconData icon,
    required int idx,
    required bool isTotal,
    bool warn = false,
  }) {
    final active = selected == idx;
    final bg = active ? (isTotal ? AppTheme.primaryDark : AppTheme.primary) : Colors.white;
    final fg = active ? Colors.white : AppTheme.textPrimary;
    final sg = active ? Colors.white.withValues(alpha:0.75) : AppTheme.textMuted;

    return GestureDetector(
      onTap: () => onSelect(idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
          border: active ? null : Border.all(color: AppTheme.border.withValues(alpha:0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 7),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: fg)),
            Text(sub, style: TextStyle(fontSize: 10, color: sg)),
          ]),
          if (warn && !active) ...[
            const SizedBox(width: 5),
            Container(width: 6, height: 6,
              decoration: BoxDecoration(color: AppTheme.warning, shape: BoxShape.circle)),
          ],
        ]),
      ),
    );
  }
}

// ─── Project total banner ─────────────────────────────────────────────────────

class _TotalBanner extends StatelessWidget {
  final List<BuildingState> buildings;
  final List<BomResult> allBoms;

  const _TotalBanner({required this.buildings, required this.allBoms});

  @override
  Widget build(BuildContext context) {
    final totalItems  = allBoms.fold(0, (s, b) => s + b.activeItems.length);
    final anyInc      = allBoms.any((b) => !b.isComplete);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary.withValues(alpha:0.08), AppTheme.primary.withValues(alpha:0.03)],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha:0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text('Project Total — ${buildings.length} Buildings',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppTheme.primary)),
          const Spacer(),
          Text('$totalItems line items combined',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ]),
        const SizedBox(height: 10),
        // Per-building mini-cards
        if (buildings.isNotEmpty)
          Row(children: List.generate(buildings.length, (i) {
            final b    = buildings[i];
            final area = b.roofGeometry.totalArea;
            final cnt  = i < allBoms.length ? allBoms[i].activeItems.length : 0;
            return Expanded(child: Container(
              margin: EdgeInsets.only(right: i < buildings.length - 1 ? 8 : 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.buildingName,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(area > 0 ? '${area.toStringAsFixed(0)} sf' : '—',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: AppTheme.primary)),
                Text('$cnt items',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              ]),
            ));
          })),
        if (anyInc) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.info_outline, size: 13, color: AppTheme.warning),
            const SizedBox(width: 5),
            Expanded(child: Text(
              'Some buildings have incomplete inputs — project total may be partial.',
              style: TextStyle(fontSize: 10, color: AppTheme.warning),
            )),
          ]),
        ],
      ]),
    );
  }
}

// ─── Summary chips row ────────────────────────────────────────────────────────

class _SummaryChips extends StatelessWidget {
  final double area;
  final MembraneSystem membrane;
  final ProjectInfo info;
  final double totalRValue;

  const _SummaryChips({required this.area, required this.membrane, required this.info, required this.totalRValue});

  @override
  Widget build(BuildContext context) {
    final sq   = area > 0 ? (area / 100).toStringAsFixed(1) : '—';
    final aStr = area > 0 ? _fmt(area) : '—';
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 500;

    final chips = [
      _chipData('Total Area',   '$aStr sf',                                Icons.crop_square),
      _chipData('Squares',      sq,                                        Icons.grid_4x4),
      _chipData('Membrane',     '${membrane.thickness} ${membrane.membraneType}', Icons.texture),
      _chipData('Attachment',   membrane.fieldAttachment == 'Mechanically Attached' ? 'Mech. Att.' : membrane.fieldAttachment == 'Fully Adhered' ? 'Fully Adh.' : 'Rhinobond', Icons.link),
      _chipData('R-Value',      totalRValue > 0 ? 'R-${totalRValue.toStringAsFixed(0)}' : '—', Icons.thermostat),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha:0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha:0.15)),
      ),
      child: isNarrow
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: chips.map((c) => SizedBox(
                width: (screenWidth - 56) / 3, // 3 per row on narrow
                child: _chip(c.$1, c.$2, c.$3),
              )).toList(),
            )
          : Row(children: [
              for (int i = 0; i < chips.length; i++) ...[
                if (i > 0) _vDivider(),
                Expanded(child: _chip(chips[i].$1, chips[i].$2, chips[i].$3)),
              ],
            ]),
    );
  }

  (String, String, IconData) _chipData(String label, String value, IconData icon) =>
      (label, value, icon);

  Widget _chip(String label, String value, IconData icon) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppTheme.primary.withValues(alpha:0.7)),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
          overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      Text(label,
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
          overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
    ],
  );
}

class _FasteningScheduleTab extends ConsumerWidget {
  const _FasteningScheduleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geo      = ref.watch(roofGeometryProvider);
    final membrane = ref.watch(membraneSystemProvider);
    final specs    = ref.watch(systemSpecsProvider);
    final insul    = ref.watch(insulationSystemProvider);
    final info     = ref.watch(projectInfoProvider);

    final isMA        = membrane.fieldAttachment == 'Mechanically Attached';
    final isRhinobond = membrane.fieldAttachment == 'Rhinobond (Induction Welded)';
    final isFA        = membrane.fieldAttachment == 'Fully Adhered';
    final hasZones    = geo.windZones.perimeterZoneWidth > 0;
    final wAcc        = info.wasteAccessory;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Fastening Schedule', Icons.grid_on),
        const SizedBox(height: 20),

        // Attachment method badge
        _attachmentBadge(membrane.fieldAttachment),
        const SizedBox(height: 20),

        if (isMA || isRhinobond) ...[
          // Zone fastening table
          _card(child: Column(children: [
            _cardHeader('Membrane ${isRhinobond ? "Plate" : "Fastener"} Schedule',
                Icons.grid_on, showWarning: !hasZones,
                warning: hasZones ? null : 'Wind zone widths not set — enter building height to auto-calculate.'),
            const SizedBox(height: 4),
            _fasteningTable(geo, isRhinobond, wAcc, info.warrantyYears, info.designWindSpeed),
          ])),
          const SizedBox(height: 16),
        ],

        if (isFA) ...[
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _cardHeader('Fully Adhered — No Mechanical Fasteners in Membrane', Icons.format_paint),
            const SizedBox(height: 8),
            _row('Bonding adhesive required', 'Yes'),
            _row('Coverage rate', '~60 sf/gal'),
            _row('Apply to', 'Substrate + membrane underside'),
            const SizedBox(height: 8),
            _warnBox('Check climate zone temperature limits before specifying adhesive.',
                AppTheme.warning),
          ])),
          const SizedBox(height: 16),
        ],

        // Insulation attachment
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cardHeader('Insulation Attachment', Icons.view_in_ar),
          const SizedBox(height: 4),
          _insAttachTable(insul, specs),
        ])),
        const SizedBox(height: 16),

        // Fastener lengths summary
        if ((isMA || isRhinobond) && specs.deckType.isNotEmpty) ...[
          _fastenerLengthCard(insul, specs.deckType),
          const SizedBox(height: 16),
        ],

        // Fastener compatibility
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cardHeader('Deck–Fastener Compatibility', Icons.check_circle_outline),
          const SizedBox(height: 8),
          _deckFastenerMatrix(specs.deckType),
        ])),
      ]),
    );
  }

  Widget _attachmentBadge(String method) {
    Color c;
    IconData icon;
    switch (method) {
      case 'Mechanically Attached':       c = AppTheme.primary; icon = Icons.hardware; break;
      case 'Fully Adhered':               c = AppTheme.accent;  icon = Icons.format_paint; break;
      case 'Rhinobond (Induction Welded)':c = AppTheme.secondary; icon = Icons.bolt; break;
      default:                            c = AppTheme.textSecondary; icon = Icons.help_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(color: c.withValues(alpha:0.08), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha:0.25))),
      child: Row(children: [
        Icon(icon, color: c, size: 18), const SizedBox(width: 10),
        Flexible(child: Text.rich(TextSpan(children: [
          TextSpan(text: 'Attachment: ', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          TextSpan(text: method, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
        ]), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  Widget _fasteningTable(geo, bool rhinobond, double wAcc, int warrantyYears, String? designWindSpeed) {
    final zones = geo.windZones;
    final hasData = zones.fieldZoneArea > 0;

    // Apply wind speed adjustment — same logic as BOM calculator.
    // ≥90 mph: bump one warranty tier; ≥130 mph: bump two tiers.
    final windMph = _parseWindMph(designWindSpeed);
    final effectiveWarranty = _windAdjustedWarranty(warrantyYears, windMph);

    // Fastening densities driven by effective warranty tier (wind-adjusted).
    final densities     = rhinobond
        ? _rbDensities(effectiveWarranty)
        : _maDensities(effectiveWarranty);
    final fieldDensity  = densities.$1;
    final perimDensity  = densities.$2;
    final cornerDensity = densities.$3;

    final fieldQty  = hasData ? (zones.fieldZoneArea  * fieldDensity  * (1 + wAcc)).ceil() : null;
    final perimQty  = hasData ? (zones.perimeterZoneArea * perimDensity  * (1 + wAcc)).ceil() : null;
    final cornerQty = hasData ? (zones.cornerZoneArea * cornerDensity * (1 + wAcc)).ceil() : null;

    final windNote = windMph >= 90
        ? '  Wind ${windMph.toInt()} mph: using ${effectiveWarranty}-year densities (base ${warrantyYears}-year)'
        : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (windNote != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(Icons.air, size: 14, color: Colors.orange.shade700),
            const SizedBox(width: 4),
            Text(windNote, style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w500)),
          ]),
        ),
      Table(
        border: TableBorder.all(color: AppTheme.border, borderRadius: BorderRadius.circular(7)),
        columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.2), 3: FlexColumnWidth(1.2), 4: FlexColumnWidth(1.2)},
        children: [
          TableRow(
            decoration: BoxDecoration(color: AppTheme.surfaceAlt),
            children: ['Zone', 'Area (sf)', 'Density', 'Pattern', rhinobond ? 'Plates' : 'Fasteners']
                .map(_th).toList(),
          ),
          _fRow('Field',     _nf(zones.fieldZoneArea),     '${fieldDensity.toStringAsFixed(3)}/sf',  '24"x24"', fieldQty,  AppTheme.primary.withValues(alpha:0.05)),
          _fRow('Perimeter', _nf(zones.perimeterZoneArea), '${perimDensity.toStringAsFixed(3)}/sf',  '12"x12"', perimQty,  AppTheme.primary.withValues(alpha:0.10)),
          _fRow('Corner',    _nf(zones.cornerZoneArea),    '${cornerDensity.toStringAsFixed(3)}/sf', '8"x12"',  cornerQty, AppTheme.primary.withValues(alpha:0.16)),
        ],
      ),
    ]);
  }

  Widget _fastenerLengthCard(InsulationSystem insul, String deckType) {
    final l1t  = insul.layer1.thickness;
    final l2t  = (insul.numberOfLayers == 2 ? insul.layer2?.thickness : null) ?? 0.0;
    final cbt  = (insul.hasCoverBoard ? insul.coverBoard?.thickness : null) ?? 0.0;
    final full = l1t + l2t + cbt;
    final deckT = _deckThicknessIn(deckType);
    final penIn = _deckPenetrationIn(deckType);
    final name  = _fastenerName(deckType);

    String pick(double stack) {
      final minNeeded = stack + deckT + penIn;
      final avail     = _fastenerLengthsIn(deckType);
      for (final len in avail) {
        if (len >= minNeeded) {
          return len == len.truncateToDouble()
              ? '${len.toInt()}"'
              : '${len.toStringAsFixed(1)}"';
        }
      }
      final longest = avail.last;
      return '${longest == longest.truncateToDouble() ? longest.toInt() : longest.toStringAsFixed(1)}" (verify)';
    }

    final fullStack = l1t + l2t + cbt;
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardHeader('Membrane Fastener Lengths', Icons.straighten),
      const SizedBox(height: 10),
      _row('Deck type', deckType),
      _row('Insulation stack', '${fullStack.toStringAsFixed(2)}"'),
      if (deckT > 0) _row('Deck thickness', '${deckT.toStringAsFixed(2)}"'),
      _row('Min penetration into deck', '${penIn.toStringAsFixed(2)}"'),
      _row('Total min length', '${(fullStack + deckT + penIn).toStringAsFixed(2)}"'),
      const Divider(height: 16),
      _row('Membrane fastener ($name)', pick(full)),
      if (insul.layer1.attachmentMethod == 'Mechanically Attached')
        _row('L1 insulation ($name)', pick(l1t)),
      if (insul.numberOfLayers == 2 &&
          (insul.layer2?.attachmentMethod == 'Mechanically Attached' ?? false))
        _row('L2 insulation ($name)', pick(l1t + l2t)),
      if (insul.hasCoverBoard &&
          (insul.coverBoard?.attachmentMethod == 'Mechanically Attached' ?? false))
        _row('Cover board ($name)', pick(full)),
    ]));
  }

  TableRow _fRow(String zone, String area, String density, String pattern, int? qty, Color bg) {
    return TableRow(
      decoration: BoxDecoration(color: bg),
      children: [
        _td(zone, bold: true),
        _td(area),
        _td(density),
        _td(pattern),
        _td(qty != null ? qty.toString() : '—',
            color: qty != null ? AppTheme.primary : AppTheme.textMuted, bold: qty != null),
      ],
    );
  }

  Widget _insAttachTable(insul, specs) {
    final rows = <Widget>[];
    void addRow(String layer, String method, String rate) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(flex: 2, child: Text(layer, style: TextStyle(fontSize: 12,
              color: AppTheme.textPrimary, fontWeight: FontWeight.w500))),
          Expanded(flex: 2, child: Text(method, style: TextStyle(fontSize: 12,
              color: AppTheme.textSecondary))),
          Expanded(child: Text(rate, style: TextStyle(fontSize: 12,
              color: AppTheme.textSecondary), textAlign: TextAlign.right)),
        ]),
      ));
      rows.add(Divider(height: 1, color: AppTheme.border));
    }

    // Compute per-layer stack thicknesses for fastener length display
    final l1t   = insul.layer1.thickness;
    final l2t   = (insul.numberOfLayers == 2 ? insul.layer2?.thickness : null) ?? 0.0;
    final cbt   = (insul.hasCoverBoard ? insul.coverBoard?.thickness : null) ?? 0.0;
    final deckT = _deckThicknessIn(specs.deckType);
    final penIn = _deckPenetrationIn(specs.deckType);

    String fastLen(double stackIn) {
      final minNeeded = stackIn + deckT + penIn;
      final avail     = _fastenerLengthsIn(specs.deckType);
      for (final len in avail) {
        if (len >= minNeeded) {
          return len == len.truncateToDouble()
              ? '${len.toInt()}"'
              : '${len.toStringAsFixed(1)}"';
        }
      }
      final longest = avail.last;
      return '${longest == longest.truncateToDouble() ? longest.toInt() : longest.toStringAsFixed(1)}" (verify)';
    }

    final l1MA = insul.layer1.attachmentMethod == 'Mechanically Attached';
    final l2MA = insul.numberOfLayers == 2 &&
        (insul.layer2?.attachmentMethod == 'Mechanically Attached' ?? false);
    final cbMA = insul.hasCoverBoard &&
        (insul.coverBoard?.attachmentMethod == 'Mechanically Attached' ?? false);

    addRow(
      'Layer 1 (${insul.layer1.type} ${l1t == l1t.truncateToDouble() ? l1t.toInt() : l1t}")',
      insul.layer1.attachmentMethod,
      l1MA ? '4/board — ${fastLen(l1t)} ${_fastenerName(specs.deckType)}' : 'Full coverage',
    );
    if (insul.numberOfLayers == 2 && insul.layer2 != null) {
      addRow(
        'Layer 2 (${insul.layer2!.type} ${l2t == l2t.truncateToDouble() ? l2t.toInt() : l2t}")',
        insul.layer2!.attachmentMethod,
        l2MA ? '4/board — ${fastLen(l1t + l2t)} ${_fastenerName(specs.deckType)} (thru L1+L2)' : 'Full coverage',
      );
    }
    if (insul.hasCoverBoard && insul.coverBoard != null) {
      final cbt2 = insul.coverBoard!.thickness;
      addRow(
        'Cover Board (${insul.coverBoard!.type} ${cbt2 == cbt2.truncateToDouble() ? cbt2.toInt() : cbt2}")',
        insul.coverBoard!.attachmentMethod,
        cbMA ? '4/board — ${fastLen(l1t + l2t + cbt2)} ${_fastenerName(specs.deckType)} (full stack)' : 'Full coverage',
      );
    }
    if (rows.isEmpty) {
      return Text('No insulation configured.', style: TextStyle(color: AppTheme.textMuted));
    }
    return Column(children: rows);
  }

  Widget _deckFastenerMatrix(String deckType) {
    final matrix = {
      'Metal':       ('#14 HP or #15 HP', true),
      'Concrete':    ('Concrete anchors (pre-drill required)', true),
      'Wood':        ('Wood screws', true),
      'Gypsum':      ('Gypsum-specific fasteners', true),
      'Tectum':      ('Tectum-specific fasteners', true),
      'LW Concrete': ('LW concrete anchors', true),
    };

    return Column(
      children: matrix.entries.map((e) {
        final isActive = e.key == deckType;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.accent.withValues(alpha:0.08) : AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: isActive ? AppTheme.accent.withValues(alpha:0.3) : AppTheme.border),
          ),
          child: Row(children: [
            Icon(isActive ? Icons.check_circle : Icons.circle_outlined,
                color: isActive ? AppTheme.accent : AppTheme.textMuted, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(e.key, style: TextStyle(fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary))),
            Text(e.value.$1, style: TextStyle(fontSize: 11,
                color: isActive ? AppTheme.textPrimary : AppTheme.textMuted)),
          ]),
        );
      }).toList(),
    );
  }

  Widget _th(String t) => Padding(padding: const EdgeInsets.all(10),
      child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary)));
  Widget _td(String t, {Color? color, bool bold = false}) => Padding(
      padding: const EdgeInsets.all(10),
      child: Text(t, style: TextStyle(fontSize: 12,
          color: color ?? AppTheme.textPrimary,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400)));
  Widget _row(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(l, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
      Text(v, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
    ]),
  );
  static String _nf(double v) => v > 0 ? v.toStringAsFixed(0) : '—';

  // ── Fastener length helpers (mirrors bom_calculator.dart logic) ─────────────
  static String _fastenerName(String deckType) {
    switch (deckType) {
      case 'Metal':       return '#14 HP';
      case 'Concrete':    return 'Conc. Anchor';
      case 'Wood':        return 'Wood Screw';
      case 'Gypsum':      return 'Gyp. Fastener';
      case 'Tectum':      return 'Tectum Fastener';
      case 'LW Concrete': return 'LW Anchor';
      default:            return 'Fastener';
    }
  }

  static double _deckThicknessIn(String deckType) {
    switch (deckType) {
      case 'Wood': return 0.75;
      default:     return 0.0;
    }
  }

  static double _deckPenetrationIn(String deckType) {
    switch (deckType) {
      case 'Metal':       return 1.00;
      case 'Wood':        return 1.00;
      case 'Concrete':    return 1.25;
      case 'LW Concrete': return 1.50;
      case 'Gypsum':      return 1.50;
      case 'Tectum':      return 1.50;
      default:            return 1.00;
    }
  }

  static List<double> _fastenerLengthsIn(String deckType) {
    switch (deckType) {
      case 'Metal':       return [3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0];
      case 'Wood':        return [2.5, 3.5, 4.5, 6.0, 8.0, 10.0, 12.0];
      case 'Concrete':    return [2.25, 3.25, 4.25];
      case 'LW Concrete': return [3.25, 4.25, 5.25];
      case 'Gypsum':
      case 'Tectum':      return [3.0, 4.0, 5.0, 6.0, 8.0, 10.0];
      default:            return [3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0];
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// THERMAL & CODE TAB
// ══════════════════════════════════════════════════════════════════════════════

class _ThermalCodeTab extends ConsumerWidget {
  const _ThermalCodeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rResult   = ref.watch(rValueResultProvider);
    final rWarnings = ref.watch(rValueValidationProvider);
    final info      = ref.watch(projectInfoProvider);
    final insul     = ref.watch(insulationSystemProvider);

    final totalR     = rResult?.totalRValue ?? 0;
    final required   = info.requiredRValue;
    final passes     = required == null ? null : totalR >= required;
    final hasZip     = info.zipCode.length == 5;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Thermal & Code Compliance', Icons.thermostat),
        const SizedBox(height: 20),

        // R-value hero
        _rValueHero(totalR, required, passes, hasZip),
        const SizedBox(height: 20),

        // R-value breakdown
        if (rResult != null) ...[
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _cardHeader('R-Value Breakdown', Icons.layers),
            const SizedBox(height: 8),
            _rRow('Layer 1 (${insul.layer1.type} ${_ins(insul.layer1.thickness)})',
                rResult.layer1.rValue),
            if ((rResult.layer2?.rValue ?? 0) > 0)
              _rRow('Layer 2 (${insul.layer2?.type ?? ''} ${_ins(insul.layer2?.thickness ?? 0)})',
                  (rResult.layer2?.rValue ?? 0)),
            if ((rResult.tapered?.averageRValue ?? 0) > 0)
              _rRow('Tapered Insulation', (rResult.tapered?.averageRValue ?? 0)),
            if ((rResult.coverBoard?.rValue ?? 0) > 0)
              _rRow('Cover Board (${insul.coverBoard?.type ?? ''})',
                  (rResult.coverBoard?.rValue ?? 0)),
            _rRow('Membrane', rResult.membraneContribution),
            const Divider(height: 16),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text('R-${totalR.toStringAsFixed(1)}',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16,
                          color: passes == false ? AppTheme.error : AppTheme.primary)),
                ],
              ),
            ),
          ])),
          const SizedBox(height: 16),
        ],

        // Code requirements
        if (hasZip) ...[
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _cardHeader('Code Requirements — ${info.climateZone ?? 'ZIP entered'}',
                Icons.policy),
            const SizedBox(height: 8),
            if (required != null) ...[
              _codeRow('IECC 2021 Minimum', 'R-${required.toStringAsFixed(0)}',
                  totalR >= required),
              _codeRow('ASHRAE 90.1 Minimum', 'R-${required.toStringAsFixed(0)}',
                  totalR >= required),
              _codeRow('Project Assembly', 'R-${totalR.toStringAsFixed(1)}',
                  totalR >= required),
            ] else
              Text('Enter ZIP code to load climate zone requirements.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ])),
          const SizedBox(height: 16),
        ] else ...[
          _warnBox('Enter ZIP code to load climate zone and R-value requirements.',
              AppTheme.warning),
          const SizedBox(height: 16),
        ],

        // Validation messages
        if (rWarnings.isNotEmpty) ...[
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _cardHeader('Validation Notices', Icons.info_outline),
            const SizedBox(height: 8),
            ...rWarnings.map((v) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(_sevIcon(v.type), size: 14, color: _sevColor(v.type)),
                const SizedBox(width: 7),
                Expanded(child: Text(v.text,
                    style: TextStyle(fontSize: 12, color: _sevColor(v.type)))),
              ]),
            )),
          ])),
        ],
      ]),
    );
  }

  Widget _rValueHero(double totalR, double? required, bool? passes, bool hasZip) {
    final color = passes == null ? AppTheme.primary
        : passes ? AppTheme.accent : AppTheme.error;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.primaryDark],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Total Assembly R-Value',
              style: TextStyle(color: Colors.white.withValues(alpha:0.8), fontSize: 13)),
          const SizedBox(height: 6),
          Text(totalR > 0 ? 'R-${totalR.toStringAsFixed(1)}' : '—',
              style: const TextStyle(color: Colors.white, fontSize: 44,
                  fontWeight: FontWeight.w800)),
          if (required != null)
            Text('Required: R-${required.toStringAsFixed(0)}',
                style: TextStyle(color: Colors.white.withValues(alpha:0.75), fontSize: 12)),
        ])),
        if (passes != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(passes ? Icons.check_circle : Icons.cancel,
                  color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(passes ? 'IECC Compliant' : 'Below Required',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
      ]),
    );
  }

  Widget _rRow(String label, double value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
      Text('R-${value.toStringAsFixed(1)}',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: AppTheme.textPrimary)),
    ]),
  );

  Widget _codeRow(String label, String value, bool passes) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(passes ? Icons.check_circle : Icons.cancel,
          color: passes ? AppTheme.accent : AppTheme.error, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(fontSize: 12))),
      Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12,
          color: passes ? AppTheme.accent : AppTheme.error)),
    ]),
  );

  static String _ins(double t) =>
      '${t == t.roundToDouble() ? t.toInt() : t}"';
  static IconData _sevIcon(ValidationMessageType type) {
    switch (type) {
      case ValidationMessageType.blocker: return Icons.block;
      case ValidationMessageType.warning: return Icons.warning_amber;
    }
  }
  static Color _sevColor(ValidationMessageType type) {
    switch (type) {
      case ValidationMessageType.blocker: return AppTheme.error;
      case ValidationMessageType.warning: return AppTheme.warning;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SCOPE OF WORK TAB
// ══════════════════════════════════════════════════════════════════════════════

class _ScopeOfWorkTab extends ConsumerStatefulWidget {
  const _ScopeOfWorkTab();

  @override
  ConsumerState<_ScopeOfWorkTab> createState() => _ScopeOfWorkTabState();
}

class _ScopeOfWorkTabState extends ConsumerState<_ScopeOfWorkTab> {
  static const List<(String, String)> _sections = [
    ('general',     'General'),
    ('tearoff',     'Tear-Off'),
    ('recover',     'Existing Roof Preparation'),
    ('deck',        'Deck Preparation'),
    ('insulation',  'Insulation'),
    ('membrane',    'Membrane'),
    ('parapet',     'Parapet Wall Flashings'),
    ('penetration', 'Penetration Flashings'),
    ('metal',       'Sheet Metal'),
    ('drainage',    'Drainage'),
    ('cleanup',     'Cleanup & Protection'),
    ('warranty',    'Warranty'),
  ];

  @override
  Widget build(BuildContext context) {
    final geo      = ref.watch(roofGeometryProvider);
    final specs    = ref.watch(systemSpecsProvider);
    final insul    = ref.watch(insulationSystemProvider);
    final membrane = ref.watch(membraneSystemProvider);
    final parapet  = ref.watch(parapetWallsProvider);
    final metal    = ref.watch(metalScopeProvider);
    final info     = ref.watch(projectInfoProvider);
    final pen      = ref.watch(penetrationsProvider);
    final overrides = ref.watch(sowOverridesProvider);

    final area      = geo.totalArea;
    final perimeter = geo.totalPerimeter;
    final drains    = geo.numberOfDrains;

    final projectTitle = info.projectName.isNotEmpty ? info.projectName : 'SCOPE OF WORK';
    final projectSub   = specs.projectType.isNotEmpty ? specs.projectType : 'Commercial Roof Work';
    final dateStr      = '${info.estimateDate.month}/${info.estimateDate.day}/${info.estimateDate.year}';
    final hasHeader    = info.projectName.isNotEmpty || info.projectAddress.isNotEmpty
                         || info.customerName.isNotEmpty;

    final Map<String, String> autoText = _buildAutoText(
        geo, specs, insul, membrane, parapet, metal, info, pen, area, perimeter, drains);
    final hasAnyOverride = overrides.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _sectionHeader('Scope of Work', Icons.description),
          const Spacer(),
          if (hasAnyOverride)
            TextButton.icon(
              onPressed: () => ref.read(estimatorProvider.notifier).clearAllSowOverrides(),
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Reset All', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () async {
              final state = ref.read(estimatorProvider);
              final bom = ref.read(bomProvider);
              final rValue = ref.read(rValueResultProvider);
              final profile = ref.read(companyProfileProvider);
              final sowOvr = ref.read(sowOverridesProvider);
              await _exportSingleDocPdf(
                state: state, title: 'Scope of Work', filename: 'scope_of_work',
                profile: profile,
                buildContent: () {
                  final widgets = <pw.Widget>[];
                  final effectiveText = <String, String>{...autoText};
                  for (final e in sowOvr.entries) effectiveText[e.key] = e.value;
                  for (final entry in effectiveText.entries) {
                    if (entry.value.trim().isEmpty) continue;
                    widgets.add(pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(entry.key.replaceAll('_', ' ').toUpperCase(),
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                                color: _pdfBlue, letterSpacing: 0.5)),
                        pw.SizedBox(height: 3),
                        pw.Text(_sanitizePdf(entry.value),
                            style: pw.TextStyle(fontSize: 9, color: _pdfSlate700, lineSpacing: 1.3)),
                      ]),
                    ));
                  }
                  return widgets;
                },
              );
            },
            icon: const Icon(Icons.download, size: 14),
            label: const Text('Export PDF', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
          ),
        ]),

        if (hasAnyOverride) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha:0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha:0.2))),
            child: Row(children: [
              const Icon(Icons.auto_awesome, size: 13, color: Color(0xFF7C3AED)),
              const SizedBox(width: 6),
              Text('${overrides.length} section${overrides.length > 1 ? "s" : ""} edited by AI',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF7C3AED),
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],

        const SizedBox(height: 20),

        _card(child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(projectTitle.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800,
                        fontSize: 16, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(projectSub,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Date: $dateStr',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                if (info.estimatorName.isNotEmpty)
                  Text('Estimator: ${info.estimatorName}',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ]),
            ]),

            if (hasHeader) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (info.customerName.isNotEmpty)
                    _headerRow('Customer', info.customerName),
                  if (info.projectAddress.isNotEmpty)
                    _headerRow('Address', info.projectAddress),
                  if (info.zipCode.isNotEmpty)
                    _headerRow('Location',
                        info.zipCode +
                        (info.climateZone != null ? '  ·  ${info.climateZone}' : '') +
                        (info.designWindSpeed != null ? '  ·  ${info.designWindSpeed}' : '')),
                ]),
              ),
            ],

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            for (final section in _sections) ...[
              if (autoText.containsKey(section.$1))
                _scopeSection(
                  context:     context,
                  sectionKey:  section.$1,
                  title:       section.$2,
                  autoText:    autoText[section.$1]!,
                  overrideText: overrides[section.$1],
                  autoContext: autoText,
                  info:        info,
                  specs:       specs,
                ),
            ],
          ]),
        )),
      ]),
    );
  }

  // ── Auto-generated text ───────────────────────────────────────────────────

  Map<String, String> _buildAutoText(geo, specs, insul, membrane, parapet,
      metal, info, pen, double area, double perimeter, int drains) {
    final map = <String, String>{};

    map['general'] = 'Furnish all labor, materials, equipment, and supervision necessary '
        'to complete the roofing work as specified herein.'
        '${area > 0 ? ' Work area approximately ${area.toStringAsFixed(0)} square feet'
            '${perimeter > 0 ? ', ${perimeter.toStringAsFixed(0)} LF perimeter' : ''}.' : ''}';

    if (specs.projectType == 'Tear-off & Replace')
      map['tearoff'] = 'Remove and dispose of existing'
          '${specs.existingRoofType.isNotEmpty ? ' ${specs.existingRoofType}' : ''}'
          '${specs.existingLayers > 0 ? ' roof system (${specs.existingLayers} layer(s))' : ' roof system'}'
          ' down to the structural deck. Dispose of all debris in accordance with local '
          'regulations. Inspect structural deck for deterioration, deflection, or damage; '
          'report findings and obtain written approval before proceeding.';

    if (specs.projectType == 'Recover')
      map['recover'] = 'Prepare existing'
          '${specs.existingRoofType.isNotEmpty ? ' ${specs.existingRoofType}' : ''}'
          ' surface to receive recover system. Perform electronic or nuclear moisture survey. '
          'Remove and replace all wet or deteriorated insulation. Address all blisters, '
          'ridges, and surface deficiencies prior to new membrane installation.';

    map['deck'] = 'Clean and prepare '
        '${specs.deckType.isNotEmpty ? '${specs.deckType.toLowerCase()} structural deck' : 'structural deck'}'
        ' to receive new roofing system.'
        '${specs.vaporRetarder != 'None' && specs.vaporRetarder.isNotEmpty ? ' Install ${specs.vaporRetarder.toLowerCase()} vapor retarder per Versico specifications.' : ''}';

    map['insulation'] = _insulationScope(insul);

    map['membrane'] = 'Install Versico '
        '${membrane.thickness.isNotEmpty ? membrane.thickness : ''} '
        '${membrane.membraneType.isNotEmpty ? membrane.membraneType : 'TPO'} membrane, '
        '${_attachmentDesc(membrane.fieldAttachment)}. '
        '${membrane.seamType == 'Tape' ? 'Seams sealed with factory-applied seam tape.' : 'All field seams hot-air welded, minimum 1.5" width.'} '
        'Membrane color: ${membrane.color.isNotEmpty ? membrane.color : 'white'}.';

    if (parapet.hasParapetWalls)
      map['parapet'] = 'Install TPO membrane wall flashings at all '
          '${parapet.wallType.isNotEmpty ? parapet.wallType.toLowerCase() : ''}'
          ' parapet walls (${parapet.parapetTotalLF > 0 ? '${parapet.parapetTotalLF.toStringAsFixed(0)} LF' : 'see drawings'}). '
          'Flashing height: ${parapet.parapetHeight > 0 ? '${parapet.parapetHeight.toStringAsFixed(0)}"' : 'minimum 8"'} above finished membrane surface. '
          'Secure at termination with ${parapet.terminationType.isNotEmpty ? parapet.terminationType.toLowerCase() : 'termination bar'} '
          'and ${parapet.anchorType.isNotEmpty ? parapet.anchorType.toLowerCase() : 'appropriate anchors'}.';

    map['penetration'] = _penetrationScope(pen, drains);

    if (metal.copingLF > 0 || metal.edgeMetalLF > 0 || metal.gutterLF > 0)
      map['metal'] = _metalScope(metal);

    if (metal.gutterLF > 0)
      map['drainage'] = '${metal.gutterLF.toStringAsFixed(0)} LF of '
          '${metal.gutterSize.isNotEmpty ? metal.gutterSize : ''} gutters'
          '${metal.downspoutCount > 0 ? ' with ${metal.downspoutCount} downspout${metal.downspoutCount > 1 ? 's' : ''}' : ''}. '
          'All drainage components to be installed per manufacturer specifications.';

    map['cleanup'] = 'Contractor shall maintain a clean and orderly work area throughout '
        'the project. Protect all rooftop equipment, walls, and adjacent surfaces from damage. '
        'Remove all debris, equipment, and surplus materials upon completion.';

    map['warranty'] = 'Upon satisfactory completion and final inspection, contractor shall provide: '
        '(1) Versico ${info.warrantyYears > 0 ? '${info.warrantyYears}-year' : 'manufacturer'} '
        'NDL roofing system warranty'
        '${info.climateZone != null ? ', climate ${info.climateZone}' : ''}'
        '${info.designWindSpeed != null ? ', design wind ${info.designWindSpeed}' : ''}; '
        '(2) Contractor 2-year workmanship warranty covering defects in materials and labor.';

    return map;
  }

  // ── Editable scope section ────────────────────────────────────────────────

  Widget _scopeSection({
    required BuildContext context,
    required String sectionKey,
    required String title,
    required String autoText,
    String? overrideText,
    required Map<String, String> autoContext,
    required info,
    required specs,
  }) {
    final isEdited    = overrideText != null;
    final displayText = overrideText ?? autoText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Row(children: [
            Text(title.toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11,
                    color: isEdited ? const Color(0xFF7C3AED) : AppTheme.primary,
                    letterSpacing: 1)),
            if (isEdited) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('AI EDITED',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700,
                        color: Color(0xFF7C3AED), letterSpacing: 0.5)),
              ),
            ],
          ])),

          Row(mainAxisSize: MainAxisSize.min, children: [
            if (isEdited)
              GestureDetector(
                onTap: () => ref.read(estimatorProvider.notifier).clearSowSection(sectionKey),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                      color: AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.border)),
                  child: Text('Reset',
                      style: TextStyle(fontSize: 9, color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            GestureDetector(
              onTap: () => _openEditSheet(
                  context, sectionKey, title, displayText, autoText, autoContext, info, specs),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha:0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha:0.25))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 9, color: Color(0xFF7C3AED)),
                  SizedBox(width: 3),
                  Text('Edit with AI',
                      style: TextStyle(fontSize: 9, color: Color(0xFF7C3AED),
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ]),

        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Text(displayText,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.6)),
        ),
      ]),
    );
  }

  void _openEditSheet(BuildContext context, String key, String title,
      String currentText, String autoText, Map<String, String> allSections,
      info, specs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _SowEditSheet(
        sectionKey:   key,
        sectionTitle: title,
        currentText:  currentText,
        autoText:     autoText,
        allSections:  allSections,
        onSave: (newText) =>
            ref.read(estimatorProvider.notifier).updateSowSection(key, newText),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _headerRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary))),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary))),
    ]),
  );

  String _attachmentDesc(String method) {
    switch (method) {
      case 'Mechanically Attached': return 'mechanically attached per Versico fastening schedule';
      case 'Fully Adhered': return 'fully adhered with Versico-approved bonding adhesive';
      case 'Rhinobond (Induction Welded)': return 'attached via Versico Rhinobond induction weld system';
      default: return method.toLowerCase();
    }
  }

  String _penetrationScope(pen, int drains) {
    final parts = <String>[];
    if (pen.rtuTotalLF > 0) parts.add('RTU curbs (${pen.rtuTotalLF.toStringAsFixed(0)} LF)');
    if (drains > 0) parts.add('$drains roof drain${drains > 1 ? 's' : ''}');
    if (pen.smallPipeCount > 0) parts.add('${pen.smallPipeCount} small pipe${pen.smallPipeCount > 1 ? 's' : ''} (1-4" dia.)');
    if (pen.largePipeCount > 0) parts.add('${pen.largePipeCount} large pipe${pen.largePipeCount > 1 ? 's' : ''} (4-12" dia.)');
    if (pen.skylightCount > 0) parts.add('${pen.skylightCount} skylight${pen.skylightCount > 1 ? 's' : ''}');
    if (pen.scupperCount > 0) parts.add('${pen.scupperCount} scupper${pen.scupperCount > 1 ? 's' : ''}');
    if (pen.expansionJointLF > 0) parts.add('expansion joints (${pen.expansionJointLF.toStringAsFixed(0)} LF)');
    if (pen.pitchPanCount > 0) parts.add('${pen.pitchPanCount} pitch pan${pen.pitchPanCount > 1 ? 's' : ''}');
    if (parts.isEmpty) return 'Install TPO membrane flashings at all penetrations per Versico specifications.';
    return 'Install Versico TPO flashings at all penetrations including: ${parts.join(', ')}. All flashings per Versico installation specifications.';
  }

  String _metalScope(metal) {
    final parts = <String>[];
    if (metal.copingLF > 0) parts.add('${metal.copingLF.toStringAsFixed(0)} LF of ${metal.copingWidth} coping cap');
    if (metal.edgeMetalLF > 0) parts.add('${metal.edgeMetalLF.toStringAsFixed(0)} LF of ${metal.edgeMetalType} edge metal');
    if (parts.isEmpty) return '';
    return 'Install prefinished ${parts.join(' and ')}. All sheet metal 24-gauge minimum, lapped and sealed per SMACNA standards.';
  }

  String _insulationScope(insul) {
    final parts = <String>[];
    final l1 = insul.layer1;
    if (l1.thickness > 0)
      parts.add('${l1.thickness}" ${l1.type} insulation, Layer 1, ${l1.attachmentMethod.toLowerCase()}');
    if (insul.numberOfLayers == 2 && insul.layer2 != null) {
      final l2 = insul.layer2!;
      if (l2.thickness > 0)
        parts.add('${l2.thickness}" ${l2.type}, Layer 2, ${l2.attachmentMethod.toLowerCase()}');
    }
    if (insul.hasTaper) parts.add('tapered insulation system (slope-to-drain)');
    if (insul.hasCoverBoard && insul.coverBoard != null) {
      final cb = insul.coverBoard!;
      parts.add('${cb.thickness}" ${cb.type} cover board, ${cb.attachmentMethod.toLowerCase()}');
    }
    if (parts.isEmpty) return 'Install insulation system per manufacturer specifications.';
    return 'Install: ${parts.join('; ')}.';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SOW EDIT BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _SowEditSheet extends StatefulWidget {
  final String sectionKey;
  final String sectionTitle;
  final String currentText;
  final String autoText;
  final Map<String, String> allSections;
  final void Function(String) onSave;

  const _SowEditSheet({
    required this.sectionKey,
    required this.sectionTitle,
    required this.currentText,
    required this.autoText,
    required this.allSections,
    required this.onSave,
  });

  @override
  State<_SowEditSheet> createState() => _SowEditSheetState();
}

class _SowEditSheetState extends State<_SowEditSheet> {
  late TextEditingController _textCtrl;
  late TextEditingController _promptCtrl;
  bool   _isLoading = false;
  String? _error;

  static const _quickPrompts = [
    'Make more formal',
    'Make more concise',
    'Add safety language',
    'Add fire stopping note',
  ];

  @override
  void initState() {
    super.initState();
    _textCtrl   = TextEditingController(text: widget.currentText);
    _promptCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _rewriteWithAI(String instruction) async {
    if (instruction.trim().isEmpty) return;
    setState(() { _isLoading = true; _error = null; });

    final otherContext = widget.allSections.entries
        .where((e) => e.key != widget.sectionKey)
        .take(3)
        .map((e) => '${e.key}: ${e.value.substring(0, e.value.length.clamp(0, 100))}')
        .join('\n');

    final systemMsg = 'You are a professional commercial roofing contractor writing a Scope of Work. '
        'Rewrite the given SOW section based on the instruction. '
        'Keep it concise (1-3 sentences), professional contractor language, no headers or bullet points. '
        'Return ONLY the rewritten text.';

    final userMsg = 'Section: "${widget.sectionTitle}"\n\n'
        'Current text:\n"${_textCtrl.text}"\n\n'
        'Instruction: "${instruction}"\n\n'
        'Other sections for context:\n$otherContext';

    try {
      final response = await http.post(
        Uri.parse('https://us-central1-tpo-pro-245d1.cloudfunctions.net/askVersico'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': {
          'mode': 'sow',
          'system': systemMsg,
          'prompt': userMsg,
        }}),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Firebase on_call wraps: {"result":{"result":{"result":"text"}}}
        final r1 = data['result'];
        final r2 = r1 is Map ? r1['result'] : r1;
        final r3 = r2 is Map ? r2['result'] : r2;
        final newText = (r3?.toString() ?? '').trim();
        if (newText.isNotEmpty) {
          setState(() { _textCtrl.text = newText; _promptCtrl.clear(); });
        } else {
          setState(() => _error = 'Empty response. Try again.');
        }
      } else {
        setState(() => _error = 'AI error (${response.statusCode}).');
      }
    } catch (e) {
      setState(() => _error = 'Connection error: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Edit: ${widget.sectionTitle}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const Text('AI rewrite or edit manually below',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ])),
          IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 20)),
        ]),

        const SizedBox(height: 16),

        // AI prompt area
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha:0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI Instruction',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: Color(0xFF7C3AED))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _promptCtrl,
                  enabled: !_isLoading,
                  decoration: const InputDecoration(
                    hintText: 'e.g. "make it more formal", "add note about fire stopping"',
                    hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                    filled: true, fillColor: Colors.white,
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (v) => _rewriteWithAI(v),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
                    borderRadius: BorderRadius.circular(8)),
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white)))
                    : IconButton(
                        onPressed: () => _rewriteWithAI(_promptCtrl.text),
                        icon: const Icon(Icons.auto_awesome,
                            color: Colors.white, size: 18),
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints()),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final q in _quickPrompts)
                GestureDetector(
                  onTap: () { _promptCtrl.text = q; _rewriteWithAI(q); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF7C3AED).withValues(alpha:0.3))),
                    child: Text(q,
                        style: const TextStyle(fontSize: 10,
                            color: Color(0xFF7C3AED), fontWeight: FontWeight.w500)),
                  ),
                ),
              GestureDetector(
                onTap: () => setState(() => _textCtrl.text = widget.autoText),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border)),
                  child: Text('Reset to auto',
                      style: TextStyle(fontSize: 10, color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500)),
                ),
              ),
            ]),
          ]),
        ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
        ],

        const SizedBox(height: 14),

        const Text('Section Text',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: Color(0xFF64748B))),
        const SizedBox(height: 6),
        TextField(
          controller: _textCtrl,
          maxLines: 5,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.border)),
            filled: true, fillColor: Colors.white,
          ),
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),

        const SizedBox(height: 16),

        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(vertical: 12)),
            child: const Text('Cancel'),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () {
              widget.onSave(_textCtrl.text.trim());
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0),
            child: const Text('Save Section'),
          )),
        ]),
      ]),
    );
  }
}



// ══════════════════════════════════════════════════════════════════════════════
// SHARED HELPERS (file-level)
// ══════════════════════════════════════════════════════════════════════════════

Widget _sectionHeader(String title, IconData icon) => Row(children: [
  Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)),
    child: Icon(icon, color: AppTheme.primary, size: 22),
  ),
  const SizedBox(width: 12),
  Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
      color: AppTheme.textPrimary)),
]);

Widget _card({required Widget child}) => Container(
  decoration: BoxDecoration(
    color: Colors.white, borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppTheme.border),
  ),
  padding: const EdgeInsets.all(16),
  child: child,
);

Widget _cardHeader(String title, IconData icon,
    {bool showWarning = false, String? warning}) {
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Icon(icon, size: 16, color: AppTheme.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w600,
          fontSize: 14, color: AppTheme.textPrimary))),
    ]),
    if (showWarning && warning != null) ...[
      const SizedBox(height: 8),
      _warnBox(warning, AppTheme.warning),
    ],
  ]);
}

Widget _warnBox(String msg, Color color) => Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(color: color.withValues(alpha:0.08), borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withValues(alpha:0.25))),
  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(Icons.info_outline, color: color, size: 14), const SizedBox(width: 7),
    Expanded(child: Text(msg, style: TextStyle(fontSize: 11, color: color))),
  ]),
);

// ══════════════════════════════════════════════════════════════════════════════
// SUBCONTRACTOR INSTALLATION INSTRUCTIONS TAB
// ══════════════════════════════════════════════════════════════════════════════

class _SubInstructionsTab extends ConsumerStatefulWidget {
  const _SubInstructionsTab();

  @override
  ConsumerState<_SubInstructionsTab> createState() => _SubInstructionsTabState();
}

class _SubInstructionsTabState extends ConsumerState<_SubInstructionsTab> {
  static const List<(String, String)> _sections = [
    ('overview',       'System Overview'),
    ('deck_prep',      'Deck Preparation'),
    ('insulation',     'Insulation Installation'),
    ('membrane',       'Membrane Installation'),
    ('parapet',        'Parapet Wall Flashings'),
    ('penetrations',   'Penetration Flashings'),
    ('metal',          'Sheet Metal & Edge Details'),
    ('accessories',    'Accessories & Sealants'),
    ('quality',        'Quality & Compliance'),
  ];

  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final geo = ref.watch(roofGeometryProvider);
    final specs = ref.watch(systemSpecsProvider);
    final insul = ref.watch(insulationSystemProvider);
    final membrane = ref.watch(membraneSystemProvider);
    final parapet = ref.watch(parapetWallsProvider);
    final metal = ref.watch(metalScopeProvider);
    final info = ref.watch(projectInfoProvider);
    final pen = ref.watch(penetrationsProvider);
    final overrides = ref.watch(subInstructionOverridesProvider);

    final area = geo.totalArea;
    final autoText = _buildSubAutoText(geo, specs, insul, membrane, parapet, metal, info, pen, area);
    final hasAnyOverride = overrides.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionHeader('Subcontractor Installation Instructions', Icons.engineering),
          const Spacer(),
          if (hasAnyOverride)
            TextButton.icon(
              onPressed: () => ref.read(subInstructionOverridesProvider.notifier).state = {},
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Reset All', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            ),
          const SizedBox(width: 8),
          _isExporting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : ElevatedButton.icon(
                  onPressed: () => _exportPdf(context),
                  icon: const Icon(Icons.download, size: 14),
                  label: const Text('Export PDF', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                ),
        ]),
        const SizedBox(height: 6),
        Text('Field-level installation guide for roofing crews. Tap any section to edit or enhance with AI.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        const SizedBox(height: 16),

        ..._sections.map((s) {
          final key = s.$1;
          final title = s.$2;
          final auto = autoText[key] ?? '';
          if (auto.isEmpty && overrides[key] == null) return const SizedBox.shrink();
          return _editableSection(
            context: context,
            sectionKey: key,
            title: title,
            autoText: auto,
            overrideText: overrides[key],
            allSections: autoText,
            isSubInstruction: true,
          );
        }),
      ]),
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    setState(() => _isExporting = true);
    try {
      final state = ref.read(estimatorProvider);
      final bom = ref.read(bomProvider);
      final rValue = ref.read(rValueResultProvider);
      final profile = ref.read(companyProfileProvider);
      final overrides = ref.read(subInstructionOverridesProvider);
      await _exportSubInstructionsPdf(state, bom, rValue, profile, overrides);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _editableSection({
    required BuildContext context,
    required String sectionKey,
    required String title,
    required String autoText,
    String? overrideText,
    required Map<String, String> allSections,
    required bool isSubInstruction,
  }) {
    final isEdited = overrideText != null;
    final displayText = overrideText ?? autoText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Row(children: [
            Text(title.toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11,
                    color: isEdited ? const Color(0xFF7C3AED) : AppTheme.primary,
                    letterSpacing: 1)),
            if (isEdited) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('EDITED', style: TextStyle(fontSize: 8,
                    fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
              ),
            ],
          ])),
          InkWell(
            onTap: () => _openEditSheet(context, sectionKey, title, displayText, allSections),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha:0.06),
                  borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome, size: 12, color: AppTheme.primary),
                const SizedBox(width: 4),
                Text('Edit with AI', style: TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w600, color: AppTheme.primary)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isEdited ? const Color(0xFF7C3AED).withValues(alpha:0.03) : AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isEdited
                ? const Color(0xFF7C3AED).withValues(alpha:0.15)
                : AppTheme.border),
          ),
          child: Text(displayText,
              style: TextStyle(fontSize: 12, color: AppTheme.textPrimary, height: 1.5)),
        ),
      ]),
    );
  }

  void _openEditSheet(BuildContext context, String key, String title,
      String currentText, Map<String, String> allSections) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _SubEditSheet(
        sectionKey: key,
        sectionTitle: title,
        currentText: currentText,
        allSections: allSections,
        onSave: (newText) {
          ref.read(subInstructionOverridesProvider.notifier).update((m) =>
              {...m, key: newText});
        },
        onReset: () {
          ref.read(subInstructionOverridesProvider.notifier).update((m) {
            final copy = Map<String, String>.from(m);
            copy.remove(key);
            return copy;
          });
        },
      ),
    );
  }

  Map<String, String> _buildSubAutoText(geo, specs, insul, membrane, parapet,
      metal, info, pen, double area) {
    final map = <String, String>{};
    final isMA = membrane.fieldAttachment == 'Mechanically Attached';
    final isFA = membrane.fieldAttachment == 'Fully Adhered';
    final isRB = membrane.fieldAttachment == 'Rhinobond (Induction Welded)';
    final zones = geo.windZones;
    final hasZones = zones.perimeterZoneWidth > 0;

    map['overview'] = 'Project: ${info.projectName}. '
        'Type: ${specs.projectType}. Deck: ${specs.deckType}. '
        'Membrane: Versico ${membrane.thickness} ${membrane.membraneType}, ${membrane.color}, ${membrane.fieldAttachment}. '
        'Warranty: ${info.warrantyYears}-year NDL. '
        '${info.designWindSpeed != null ? "Design wind: ${info.designWindSpeed}. " : ""}'
        'Total area: ${area.toStringAsFixed(0)} SF.';

    if (specs.projectType == 'Tear-off & Replace') {
      map['deck_prep'] = 'Remove existing ${specs.existingRoofType} (${specs.existingLayers} layers) to structural ${specs.deckType.toLowerCase()} deck. '
          'Inspect for damage, deflection, deterioration. Report all findings before proceeding. '
          '${specs.existingRoofType == "BUR" || specs.existingRoofType == "Modified Bitumen" ? "Apply substrate primer to bituminous residue before insulation." : ""}'
          '${specs.vaporRetarder != "None" ? " Install ${specs.vaporRetarder.toLowerCase()} vapor retarder over deck." : ""}';
    } else {
      map['deck_prep'] = 'Verify ${specs.deckType.toLowerCase()} deck is clean, dry, free of debris. '
          '${specs.vaporRetarder != "None" ? "Install ${specs.vaporRetarder.toLowerCase()} vapor retarder over deck." : ""}';
    }

    final l1 = insul.layer1;
    var insulText = 'Layer 1: ${l1.type} ${l1.thickness}" - ${l1.attachmentMethod}. ';
    if (l1.attachmentMethod == 'Mechanically Attached') {
      final l1Len = BomCalculator.selectFastenerLenPublic(specs.deckType,
          BomCalculator.stackThicknessPublic(insul, 1));
      insulText += 'Fastener: ${BomCalculator.fastenerNamePublic(specs.deckType)} $l1Len with 3" insulation plate, 4 per 4\'x8\' board. ';
    }
    if (insul.numberOfLayers == 2 && insul.layer2 != null) {
      final l2 = insul.layer2!;
      insulText += 'Layer 2: ${l2.type} ${l2.thickness}" - ${l2.attachmentMethod}. Offset joints min 6" from Layer 1. ';
      if (l2.attachmentMethod == 'Mechanically Attached') {
        final l2Len = BomCalculator.selectFastenerLenPublic(specs.deckType,
            BomCalculator.stackThicknessPublic(insul, 2));
        insulText += 'Fastener: ${BomCalculator.fastenerNamePublic(specs.deckType)} $l2Len (through L1+L2) with 3" plate. ';
      }
    }
    if (insul.hasCoverBoard && insul.coverBoard != null) {
      final cb = insul.coverBoard!;
      insulText += 'Cover Board: ${cb.type} ${cb.thickness}" - ${cb.attachmentMethod}. ';
    }
    insulText += 'Stagger all joints. No aligned joints between layers.';
    map['insulation'] = insulText;

    // Membrane
    var memText = '';
    if (isMA) {
      memText = 'MECHANICALLY ATTACHED: Install ${membrane.thickness} ${membrane.membraneType} ${membrane.rollWidth}x100\' field rolls. ';
      if (hasZones) {
        final windMph = _parseWindMph(info.designWindSpeed);
        final effW = _windAdjustedWarranty(info.warrantyYears, windMph);
        final d = _maDensities(effW);
        memText += 'Fastening densities (${effW}-year${effW != info.warrantyYears ? ", wind-adjusted" : ""}): '
            'Field ${d.$1.toStringAsFixed(2)}/SF, Perimeter ${d.$2.toStringAsFixed(2)}/SF, Corner ${d.$3.toStringAsFixed(2)}/SF. '
            'Zone width: ${zones.perimeterZoneWidth.toStringAsFixed(1)}\'. ';
      }
      final stackIn = BomCalculator.stackThicknessPublic(insul, 3);
      final memLen = BomCalculator.selectFastenerLenPublic(specs.deckType, stackIn);
      memText += 'Membrane fastener: ${BomCalculator.fastenerNamePublic(specs.deckType)} $memLen (${stackIn.toStringAsFixed(1)}" stack to deck) with 3" stress plate. ';
    } else if (isFA) {
      memText = 'FULLY ADHERED: Apply Cav-Grip III adhesive (~60 SF/gal) to substrate and membrane back. Roll into adhesive while tacky. ';
    } else if (isRB) {
      memText = 'RHINOBOND: Install induction weld plates at specified density. Lay membrane and weld with induction equipment. No through-membrane fasteners. ';
    }
    memText += 'Seam: ${membrane.seamType}. '
        '${membrane.seamType == "Hot Air Welded" ? "Min 1.5\" weld width, probe-test every 100 LF." : "Apply TPO primer before tape."} '
        'Cut-edge sealant on all reinforced membrane cut edges.';
    map['membrane'] = memText;

    if (parapet.hasParapetWalls && parapet.parapetTotalLF > 0) {
      map['parapet'] = '${parapet.parapetTotalLF.toStringAsFixed(0)} LF parapet walls, '
          '${parapet.parapetHeight.toStringAsFixed(0)}" height, ${parapet.wallType} construction. '
          '${isMA ? "Install RUSS strip (6\" wide) at wall/deck transition, fasten 12\" O.C. " : ""}'
          'Adhere TPO flashing with CAV-Grip 3v spray (40lb cyl, ~400 SF/cyl). '
          'Pair with UN-TACK cleaner (8lb cyl, 1:1). '
          'Extend from field membrane (min 4\" lap, welded) up wall to termination. '
          'Apply TPO primer at all pressure-sensitive transitions. '
          'Terminate with ${parapet.terminationType.toLowerCase()} at ${parapet.parapetHeight.toStringAsFixed(0)}" height. '
          'Water cut-off mastic under bar, single-ply sealant at top edge. '
          'Term bar fasteners: ${_termFastDesc(parapet)} at 8" O.C.';
    }

    final details = <String>[];
    if (pen.rtuDetails.isNotEmpty) details.add('RTU curbs: ${pen.rtuDetails.length} units, ${pen.rtuTotalLF.toStringAsFixed(0)} LF. Flash with 6\'x100\' TPO, 4 curb wrap corners/unit.');
    if (pen.smallPipeCount > 0) details.add('Small pipe boots (1-4"): ${pen.smallPipeCount} - pre-molded TPO with clamping ring.');
    if (pen.largePipeCount > 0) details.add('Large pipe boots (4-12"): ${pen.largePipeCount} - pre-molded TPO with clamping ring.');
    if (pen.pitchPanCount > 0) details.add('Sealant pockets: ${pen.pitchPanCount} - Versico TPO molded.');
    if (pen.skylightCount > 0) details.add('Skylights: ${pen.skylightCount} - flash per Versico curb detail.');
    if (pen.scupperCount > 0) details.add('Scuppers: ${pen.scupperCount} - EPDM pressure-sensitive flashing.');
    if (geo.numberOfDrains > 0) details.add('Roof drains: ${geo.numberOfDrains} - TPO flash, mastic under clamping ring.');
    if (pen.expansionJointLF > 0) details.add('Expansion joints: ${pen.expansionJointLF.toStringAsFixed(0)} LF.');
    map['penetrations'] = details.isNotEmpty ? details.join(' ') : 'No penetrations specified.';

    final metalParts = <String>[];
    if (metal.copingLF > 0) metalParts.add('Coping: ${metal.copingLF.toStringAsFixed(0)} LF, ${metal.copingWidth}, 10\' sections.');
    if (metal.wallFlashingLF > 0) metalParts.add('Wall flashing: ${metal.wallFlashingLF.toStringAsFixed(0)} LF.');
    if (metal.dripEdgeLF > 0) metalParts.add('Drip edge (${metal.edgeMetalType}): ${metal.dripEdgeLF.toStringAsFixed(0)} LF.');
    if (metal.gutterLF > 0) metalParts.add('Gutter (${metal.gutterSize}): ${metal.gutterLF.toStringAsFixed(0)} LF, ${metal.downspoutCount} downspout(s).');
    metalParts.add('Edge fasteners: ${BomCalculator.fastenerNamePublic(specs.deckType)} at 12" O.C.');
    map['metal'] = metalParts.join(' ');

    map['accessories'] = 'Inside corners: ${geo.insideCorners} prefab (TPO primer required). '
        'Outside corners: ${geo.outsideCorners} prefab (TPO primer required). '
        'T-joint covers at all 3-way intersections (TPO primer required). '
        'Lap sealant at T-joint edges, tape overlaps, flashing edges. '
        'Cut-edge sealant on all reinforced TPO cuts (1/8" bead). '
        'Water block sealant at T-joints, laps, penetrations.'
        '${pen.rtuDetails.isNotEmpty ? " Install heat-weldable TPO walkway pads at HVAC access paths." : ""}';

    map['quality'] = 'All work per Versico VersiWeld TPO Installation Guide and Detail Manual. '
        'Probe-test all welds every 100 LF minimum. '
        'No exposed fasteners through finished membrane (except termination bars). '
        'Protect completed work from traffic, debris, weather. '
        'Versico manufacturer inspection required before warranty issuance. '
        '${info.warrantyYears}-year NDL warranty.';

    return map;
  }

  String _termFastDesc(ParapetWalls p) {
    switch (p.wallType) {
      case 'Wood': return 'Wood screws 1-5/8"';
      case 'Metal Stud': return 'TEK screws 1"';
      default: return 'Masonry anchors 1-1/4"';
    }
  }
}

// ── Sub Instructions Edit Sheet ──────────────────────────────────────────────

class _SubEditSheet extends StatefulWidget {
  final String sectionKey;
  final String sectionTitle;
  final String currentText;
  final Map<String, String> allSections;
  final ValueChanged<String> onSave;
  final VoidCallback onReset;

  const _SubEditSheet({
    required this.sectionKey, required this.sectionTitle,
    required this.currentText, required this.allSections,
    required this.onSave, required this.onReset,
  });

  @override
  State<_SubEditSheet> createState() => _SubEditSheetState();
}

class _SubEditSheetState extends State<_SubEditSheet> {
  late TextEditingController _textCtrl;
  final _promptCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.currentText);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _rewriteWithAI(String instruction) async {
    if (instruction.trim().isEmpty) return;
    setState(() { _isLoading = true; _error = null; });

    final otherContext = widget.allSections.entries
        .where((e) => e.key != widget.sectionKey)
        .take(3)
        .map((e) => '${e.key}: ${e.value.substring(0, e.value.length.clamp(0, 100))}')
        .join('\n');

    final systemMsg = 'You are a commercial roofing field superintendent writing subcontractor installation instructions. '
        'Rewrite the given section based on the instruction. '
        'Use clear, direct field language. Include specific measurements, fastener specs, and patterns. '
        'Return ONLY the rewritten text.';

    final userMsg = 'Section: "${widget.sectionTitle}"\n\n'
        'Current text:\n"${_textCtrl.text}"\n\n'
        'Instruction: "$instruction"\n\n'
        'Other sections for context:\n$otherContext';

    try {
      final response = await http.post(
        Uri.parse('https://us-central1-tpo-pro-245d1.cloudfunctions.net/askVersico'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': {
          'mode': 'sow',
          'system': systemMsg,
          'prompt': userMsg,
        }}),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Firebase on_call wraps: {"result":{"result":{"result":"text"}}}
        final r1 = data['result'];
        final r2 = r1 is Map ? r1['result'] : r1;
        final r3 = r2 is Map ? r2['result'] : r2;
        final newText = (r3?.toString() ?? '').trim();
        if (newText.isNotEmpty) {
          setState(() { _textCtrl.text = newText; _promptCtrl.clear(); });
        } else {
          setState(() => _error = 'Empty response.');
        }
      } else {
        setState(() => _error = 'AI error (${response.statusCode}).');
      }
    } catch (e) {
      setState(() => _error = 'Connection error.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.engineering, size: 16, color: Color(0xFF7C3AED)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Edit: ${widget.sectionTitle}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const Text('AI rewrite or edit manually',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ])),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20)),
        ]),
        const SizedBox(height: 12),
        // AI prompt
        Row(children: [
          Expanded(child: TextField(
            controller: _promptCtrl,
            decoration: InputDecoration(
              hintText: 'e.g. "add more detail about weld testing" or "make it shorter"',
              hintStyle: const TextStyle(fontSize: 12),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: const TextStyle(fontSize: 13),
            onSubmitted: _rewriteWithAI,
          )),
          const SizedBox(width: 8),
          _isLoading
              ? const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  onPressed: () => _rewriteWithAI(_promptCtrl.text),
                  icon: const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED)),
                  tooltip: 'Enhance with AI',
                ),
        ]),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11))),
        const SizedBox(height: 12),
        // Manual edit
        TextField(
          controller: _textCtrl,
          maxLines: 6,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true, fillColor: Colors.grey.shade50,
          ),
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () { widget.onReset(); Navigator.pop(context); },
              child: const Text('Reset to Auto')),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () { widget.onSave(_textCtrl.text); Navigator.pop(context); },
            child: const Text('Save'),
          ),
        ]),
      ]),
    );
  }
}

// ── Export helper for sub instructions PDF ────────────────────────────────────

Future<void> _exportSubInstructionsPdf(EstimatorState state, BomResult bom,
    RValueResult? rValue, CompanyProfile profile,
    Map<String, String> overrides) async {
  // ignore: avoid_web_libraries_in_flutter
  await _exportSingleDocPdf(
    state: state,
    title: 'Installation Instructions',
    filename: 'install_instructions',
    profile: profile,
    buildContent: () {
      // If overrides exist, build from overrides; else use auto-generated
      final widgets = <pw.Widget>[];
      for (final entry in overrides.entries) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(entry.key.replaceAll('_', ' ').toUpperCase(),
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                    color: _pdfBlue, letterSpacing: 0.5)),
            pw.SizedBox(height: 3),
            pw.Text(_sanitizePdf(entry.value),
                style: pw.TextStyle(fontSize: 9, color: _pdfSlate700, lineSpacing: 1.3)),
          ]),
        ));
      }
      if (widgets.isEmpty) {
        // Use auto-generated content from the builder
        final autoWidgets = buildSubInstructions(state, bom, rValue: rValue);
        widgets.addAll(autoWidgets);
      }
      return widgets;
    },
  );
}

Future<void> _exportSingleDocPdf({
  required EstimatorState state,
  required String title,
  required String filename,
  required CompanyProfile profile,
  required List<pw.Widget> Function() buildContent,
}) async {
  final doc = pw.Document(title: '${state.projectInfo.projectName} - $title');
  final fmt = PdfPageFormat.letter;
  final content = buildContent();

  pw.ImageProvider? logoImg;
  if (profile.hasLogo) {
    logoImg = pw.MemoryImage(Uint8List.fromList(profile.logoBytes!));
  }

  for (var i = 0; i < content.length; i += 28) {
    final chunk = content.sublist(i, (i + 28).clamp(0, content.length));
    doc.addPage(pw.Page(
      pageFormat: fmt,
      margin: pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfSimpleHeader(title, state, logoImg, profile),
          pw.SizedBox(height: 12),
          ...chunk,
          pw.Spacer(),
          _pdfSimpleFooter(ctx),
        ],
      ),
    ));
  }

  final bytes = await doc.save();
  final fn = '${state.projectInfo.projectName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_$filename.pdf';

  // Web download
  downloadBytes(bytes, fn, mimeType: 'application/pdf');
}

pw.Widget _pdfSimpleHeader(String section, EstimatorState state,
    pw.ImageProvider? logo, CompanyProfile profile) =>
  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Row(children: [
        if (logo != null) ...[
          pw.Container(height: 28, constraints: const pw.BoxConstraints(maxWidth: 120),
              child: pw.Image(logo, fit: pw.BoxFit.contain)),
          pw.SizedBox(width: 8),
        ],
        pw.Text(_sanitizePdf(profile.hasName ? profile.companyName : 'ProTPO'),
            style: pw.TextStyle(fontSize: 9, color: _pdfSlate500, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Text(_sanitizePdf('${state.projectInfo.projectName} - $section'),
          style: pw.TextStyle(fontSize: 8, color: _pdfSlate500)),
    ]),
    pw.SizedBox(height: 4),
    pw.Divider(color: _pdfSlate200, thickness: 0.5),
  ]);

pw.Widget _pdfSimpleFooter(pw.Context ctx) => pw.Column(children: [
  pw.Divider(color: _pdfSlate200, thickness: 0.5),
  pw.SizedBox(height: 4),
  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
    pw.Text('Generated by ProTPO', style: pw.TextStyle(fontSize: 7, color: _pdfSlate500)),
    pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
        style: pw.TextStyle(fontSize: 7, color: _pdfSlate500)),
  ]),
]);

const _pdfBlue = PdfColor(0.12, 0.23, 0.37);
const _pdfSlate700 = PdfColor(0.20, 0.25, 0.33);
const _pdfSlate500 = PdfColor(0.39, 0.45, 0.55);
const _pdfSlate200 = PdfColor(0.89, 0.91, 0.94);

String _sanitizePdf(String v) => v
    .replaceAll('\u2014', '-').replaceAll('\u2013', '-')
    .replaceAll('\u2018', "'").replaceAll('\u2019', "'")
    .replaceAll('\u201C', '"').replaceAll('\u201D', '"')
    .replaceAll('\u00D7', 'x').replaceAll('\u00AE', '(R)')
    .replaceAll('\u00A0', ' ')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '');

// ─── Fastening density helpers (mirrors bom_calculator — keep in sync) ────────

(double, double, double) _maDensities(int warrantyYears) {
  switch (warrantyYears) {
    case 10: return (0.20, 0.40, 0.60);
    case 15: return (0.25, 0.50, 0.75);
    case 20: return (0.50, 1.00, 1.49);
    case 25: return (0.75, 1.49, 2.00);
    case 30: return (1.00, 2.00, 2.99);
    default: return (0.50, 1.00, 1.49);
  }
}

(double, double, double) _rbDensities(int warrantyYears) {
  switch (warrantyYears) {
    case 10: return (0.100, 0.200, 0.300);
    case 15: return (0.125, 0.250, 0.375);
    case 20: return (0.167, 0.333, 0.500);
    case 25: return (0.250, 0.500, 0.750);
    case 30: return (0.333, 0.667, 1.000);
    default: return (0.167, 0.333, 0.500);
  }
}

/// Parse wind speed string (e.g. "115 mph") to double.
double _parseWindMph(String? windSpeed) {
  if (windSpeed == null || windSpeed.isEmpty) return 0.0;
  final match = RegExp(r'(\d+)').firstMatch(windSpeed);
  return match != null ? double.tryParse(match.group(1)!) ?? 0.0 : 0.0;
}

/// Bump warranty tier for wind speed — mirrors BomCalculator._windAdjustedWarranty.
int _windAdjustedWarranty(int warrantyYears, double windSpeedMph) {
  const tiers = [10, 15, 20, 25, 30];
  var idx = tiers.indexOf(warrantyYears);
  if (idx < 0) idx = 2;
  if (windSpeedMph >= 130) {
    idx = (idx + 2).clamp(0, tiers.length - 1);
  } else if (windSpeedMph >= 90) {
    idx = (idx + 1).clamp(0, tiers.length - 1);
  }
  return tiers[idx];
}
