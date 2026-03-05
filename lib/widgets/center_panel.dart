/// lib/widgets/center_panel.dart
///
/// Center panel — live BOM, Fastening Schedule, Thermal & Code, Scope of Work.
///
/// All data reads from Riverpod providers. Numbers update automatically as
/// inputs change in the left panel.
///
/// Hover math: every BOM row is tappable — tap to expand the full calculation
/// trace showing area → base qty → waste → order qty.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import 'ui_polish.dart';
import '../models/building_state.dart';
import '../models/section_models.dart';
import '../models/project_info.dart';
import '../providers/estimator_providers.dart';
import '../services/bom_calculator.dart';
import '../models/insulation_system.dart';
import '../services/r_value_calculator.dart';
import '../widgets/roof_renderer.dart';

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
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
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
          ],
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final isMulti   = ref.watch(isMultiBuildingProvider);
    final allBoms   = ref.watch(allBuildingBomsProvider);
    final aggBom    = ref.watch(aggregateBomProvider);
    final buildings = ref.watch(estimatorProvider).buildings;
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
              ),
            )),

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
  color: AppTheme.primary.withOpacity(0.15),
);

Widget _hoverMathHint() => Row(children: [
  Icon(Icons.touch_app, size: 13, color: AppTheme.textMuted),
  const SizedBox(width: 5),
  Text('Tap any row to see the full calculation breakdown.',
      style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
]);

// ── BOM Category Card ──────────────────────────────────────────────────────────

class _BomCategoryCard extends StatelessWidget {
  final String category;
  final List<BomLineItem> items;
  final Set<String> expandedRows;
  final ValueChanged<String> onToggle;

  static const Map<String, IconData> _catIcons = {
    'Membrane':               Icons.texture,
    'Insulation':             Icons.view_in_ar,
    'Fasteners & Plates':     Icons.hardware,
    'Adhesives & Sealants':   Icons.format_paint,
    'Parapet & Termination':  Icons.vertical_align_top,
    'Details & Accessories':  Icons.plumbing,
    'Metal Scope':            Icons.view_day,
    'Consumables':            Icons.construction,
  };

  const _BomCategoryCard({
    required this.category, required this.items,
    required this.expandedRows, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final icon    = _catIcons[category] ?? Icons.list;
    final active  = items.where((i) => i.hasQuantity).toList();
    if (active.isEmpty) return const SizedBox.shrink();

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
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${active.length}', style: TextStyle(
                  fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),

        // Column headers
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: Row(children: [
            Expanded(flex: 4, child: Text('Item', style: _hdrStyle)),
            SizedBox(width: 52, child: Text('Qty', style: _hdrStyle, textAlign: TextAlign.right)),
            SizedBox(width: 56, child: Text('Unit', style: _hdrStyle, textAlign: TextAlign.right)),
          ]),
        ),

        // Rows
        ...active.map((item) => _BomRow(
          item: item,
          isExpanded: expandedRows.contains('${item.category}:${item.name}'),
          onToggle: () => onToggle('${item.category}:${item.name}'),
        )),
      ]),
    );
  }

  static TextStyle get _hdrStyle => TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary);
}

// ── BOM Row with hover math ────────────────────────────────────────────────────

class _BomRow extends StatelessWidget {
  final BomLineItem item;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _BomRow({required this.item, required this.isExpanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Main row
      InkWell(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: isExpanded ? AppTheme.primary.withOpacity(0.03) : Colors.transparent,
            border: Border(bottom: BorderSide(
                color: isExpanded ? AppTheme.primary.withOpacity(0.1) : AppTheme.border.withOpacity(0.5))),
          ),
          child: Row(children: [
            // Name + notes
            Expanded(flex: 4, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: TextStyle(fontSize: 13, color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500)),
                if (item.notes.isNotEmpty)
                  Text(item.notes, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            )),
            // Qty
            SizedBox(width: 52, child: Text(
              item.orderQty == item.orderQty.roundToDouble()
                  ? item.orderQty.toInt().toString()
                  : item.orderQty.toStringAsFixed(1),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary),
              textAlign: TextAlign.right,
            )),
            // Unit
            SizedBox(width: 56, child: Text(item.unit,
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                textAlign: TextAlign.right)),
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
            color: AppTheme.primary.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
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
    final sg = active ? Colors.white.withOpacity(0.75) : AppTheme.textMuted;

    return GestureDetector(
      onTap: () => onSelect(idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
          border: active ? null : Border.all(color: AppTheme.border.withOpacity(0.5)),
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
          colors: [AppTheme.primary.withOpacity(0.08), AppTheme.primary.withOpacity(0.03)],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
      ),
      child: Row(children: [
        _chip('Total Area',   '$aStr sf',                                Icons.crop_square),
        _vDivider(),
        _chip('Squares',      sq,                                        Icons.grid_4x4),
        _vDivider(),
        _chip('Membrane',     '${membrane.thickness} ${membrane.membraneType}', Icons.texture),
        _vDivider(),
        _chip('Attachment',   membrane.fieldAttachment == 'Mechanically Attached' ? 'Mech. Att.' : membrane.fieldAttachment == 'Fully Adhered' ? 'Fully Adh.' : 'Rhinobond', Icons.link),
        _vDivider(),
        _chip('R-Value',      totalRValue > 0 ? 'R-${totalRValue.toStringAsFixed(0)}' : '—', Icons.thermostat),
      ]),
    );
  }

  Widget _chip(String label, String value, IconData icon) => Expanded(
    child: Column(children: [
      Icon(icon, size: 14, color: AppTheme.primary.withOpacity(0.7)),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
          overflow: TextOverflow.ellipsis),
      Text(label,
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
          overflow: TextOverflow.ellipsis),
    ]),
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
            _fasteningTable(geo, isRhinobond, wAcc, info.warrantyYears),
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
      decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withOpacity(0.25))),
      child: Row(children: [
        Icon(icon, color: c, size: 18), const SizedBox(width: 10),
        Text('Attachment Method: ', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        Text(method, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }

  Widget _fasteningTable(geo, bool rhinobond, double wAcc, int warrantyYears) {
    final zones = geo.windZones;
    final hasData = zones.fieldZoneArea > 0;

    // Fastening densities driven by warranty tier — mirrors bom_calculator logic.
    // MA: from Versico MA tables. Rhinobond: ~33–50% of MA (larger bond area per plate).
    final densities     = rhinobond
        ? _rbDensities(warrantyYears)
        : _maDensities(warrantyYears);
    final fieldDensity  = densities.$1;
    final perimDensity  = densities.$2;
    final cornerDensity = densities.$3;

    final fieldQty  = hasData ? (zones.fieldZoneArea  * fieldDensity  * (1 + wAcc)).ceil() : null;
    final perimQty  = hasData ? (zones.perimeterZoneArea * perimDensity  * (1 + wAcc)).ceil() : null;
    final cornerQty = hasData ? (zones.cornerZoneArea * cornerDensity * (1 + wAcc)).ceil() : null;

    return Table(
      border: TableBorder.all(color: AppTheme.border, borderRadius: BorderRadius.circular(7)),
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.2), 3: FlexColumnWidth(1.2), 4: FlexColumnWidth(1.2)},
      children: [
        TableRow(
          decoration: BoxDecoration(color: AppTheme.surfaceAlt),
          children: ['Zone', 'Area (sf)', 'Density', 'Pattern', rhinobond ? 'Plates' : 'Fasteners']
              .map(_th).toList(),
        ),
        _fRow('Field',     _nf(zones.fieldZoneArea),     '${fieldDensity.toStringAsFixed(3)}/sf',  '24"×24"', fieldQty,  AppTheme.primary.withOpacity(0.05)),
        _fRow('Perimeter', _nf(zones.perimeterZoneArea), '${perimDensity.toStringAsFixed(3)}/sf',  '12"×12"', perimQty,  AppTheme.primary.withOpacity(0.10)),
        _fRow('Corner',    _nf(zones.cornerZoneArea),    '${cornerDensity.toStringAsFixed(3)}/sf', '8"×12"',  cornerQty, AppTheme.primary.withOpacity(0.16)),
      ],
    );
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
            color: isActive ? AppTheme.accent.withOpacity(0.08) : AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: isActive ? AppTheme.accent.withOpacity(0.3) : AppTheme.border),
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
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          const SizedBox(height: 6),
          Text(totalR > 0 ? 'R-${totalR.toStringAsFixed(1)}' : '—',
              style: const TextStyle(color: Colors.white, fontSize: 44,
                  fontWeight: FontWeight.w800)),
          if (required != null)
            Text('Required: R-${required.toStringAsFixed(0)}',
                style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
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
        ]),

        if (hasAnyOverride) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.2))),
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
                    color: const Color(0xFF7C3AED).withOpacity(0.1),
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
                    color: const Color(0xFF7C3AED).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.25))),
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
        Text(displayText,
            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.6)),
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
    if (insul.hasTaperedInsulation) parts.add('tapered insulation system (slope-to-drain)');
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
        Uri.parse('https://us-central1-tpo-pro-245d1.cloudfunctions.net/askAssist'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': {
          'mode': 'sow',
          'system': systemMsg,
          'prompt': userMsg,
        }}),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data    = jsonDecode(response.body);
        final newText = (data['result']?['result'] as String? ?? '').trim();
        if (newText.isNotEmpty) {
          setState(() { _textCtrl.text = newText; _promptCtrl.clear(); });
        } else {
          setState(() => _error = 'Empty response. Try again.');
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
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.1),
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
              border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.2))),
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
                            color: const Color(0xFF7C3AED).withOpacity(0.3))),
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
      color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
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
  decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withOpacity(0.25))),
  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(Icons.info_outline, color: color, size: 14), const SizedBox(width: 7),
    Expanded(child: Text(msg, style: TextStyle(fontSize: 11, color: color))),
  ]),
);

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
