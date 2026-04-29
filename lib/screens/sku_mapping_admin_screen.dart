import 'package:flutter/material.dart';

import '../data/sku_registry.dart';
import '../services/qxo_api_service.dart';
import '../services/qxo_sku_mapping_service.dart';
import '../theme/app_theme.dart';

/// Admin screen for aligning BOM line items with QXO catalog SKUs.
///
/// Shows every registered skuKey grouped by category with a mapped/unmapped
/// status. Per skuKey, lists each `(skuKey, attributes)` variant currently
/// mapped in Firestore and an "Add variant" affordance for new ones.
class SkuMappingAdminScreen extends StatefulWidget {
  const SkuMappingAdminScreen({super.key});

  @override
  State<SkuMappingAdminScreen> createState() => _SkuMappingAdminScreenState();
}

class _SkuMappingAdminScreenState extends State<SkuMappingAdminScreen> {
  final _service = QxoSkuMappingService();
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final byCategory = skuRegistryByCategory();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SKU Mapping (BOM ↔ QXO)'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<QxoSkuMapping>>(
        stream: _service.watchAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final mappings = snap.data ?? const [];

          // Group mappings by skuKey for fast lookup.
          final mappingsByKey = <String, List<QxoSkuMapping>>{};
          for (final m in mappings) {
            mappingsByKey.putIfAbsent(m.skuKey, () => []).add(m);
          }

          int totalKeys = 0;
          int mappedKeys = 0;
          for (final entry in kSkuRegistry) {
            totalKeys++;
            final variants = mappingsByKey[entry.skuKey] ?? const [];
            if (variants.any((v) => v.isMapped)) mappedKeys++;
          }

          return Column(
            children: [
              _summaryBar(mappedKeys, totalKeys, mappings.length),
              _searchField(),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    for (final cat in byCategory.keys)
                      _categorySection(cat, byCategory[cat]!, mappingsByKey),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryBar(int mapped, int total, int totalVariants) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppTheme.primary.withValues(alpha: 0.05),
      child: Row(
        children: [
          Icon(Icons.dataset_outlined, color: AppTheme.primary, size: 20),
          const SizedBox(width: 8),
          Text('$mapped / $total skuKeys mapped',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Text('· $totalVariants variant rows in Firestore',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const Spacer(),
          if (mapped < total)
            Chip(
              label: Text('${total - mapped} unmapped'),
              backgroundColor: Colors.orange.shade100,
              labelStyle: TextStyle(color: Colors.orange.shade900, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Filter by skuKey or display name…',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onChanged: (v) => setState(() => _filter = v.toLowerCase()),
      ),
    );
  }

  Widget _categorySection(
    String category,
    List<SkuRegistryEntry> entries,
    Map<String, List<QxoSkuMapping>> mappingsByKey,
  ) {
    final filtered = _filter.isEmpty
        ? entries
        : entries
            .where((e) =>
                e.skuKey.toLowerCase().contains(_filter) ||
                e.displayName.toLowerCase().contains(_filter))
            .toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: Text(category,
            style:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        subtitle: Text('${filtered.length} SKU keys',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        initiallyExpanded: _filter.isNotEmpty,
        children: [
          for (final entry in filtered)
            _skuKeyTile(entry, mappingsByKey[entry.skuKey] ?? const []),
        ],
      ),
    );
  }

  Widget _skuKeyTile(SkuRegistryEntry entry, List<QxoSkuMapping> variants) {
    final mappedCount = variants.where((v) => v.isMapped).length;
    final isMapped = mappedCount > 0;

    return ExpansionTile(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: isMapped
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.orange.withValues(alpha: 0.15),
        child: Icon(
          isMapped ? Icons.check : Icons.warning_amber_rounded,
          size: 16,
          color: isMapped ? Colors.green.shade700 : Colors.orange.shade800,
        ),
      ),
      title: Text(entry.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        entry.skuKey + (variants.isNotEmpty ? '  ·  $mappedCount variant${mappedCount == 1 ? "" : "s"} mapped' : '  ·  not mapped yet'),
        style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
      children: [
        if (entry.notes != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(entry.notes!,
                style: TextStyle(fontSize: 11, color: Colors.blue.shade900)),
          ),
          const SizedBox(height: 8),
        ],

        // Known variants — pre-populated rows the operator just needs to map.
        if (entry.knownVariants.isNotEmpty) ...[
          Text('Known variants  ·  ${entry.knownVariants.length} combinations',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5)),
          const SizedBox(height: 6),
          for (final preset in entry.knownVariants)
            _knownVariantRow(entry, preset, variants),
          const SizedBox(height: 8),
        ],

        // Custom variants — mapped tuples that don't match any known preset.
        if (_customVariants(entry, variants).isNotEmpty) ...[
          Text('Custom variants',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5)),
          const SizedBox(height: 6),
          for (final variant in _customVariants(entry, variants))
            _variantRow(entry, variant),
          const SizedBox(height: 8),
        ],

        // For skuKeys with no variants and no known presets, show ALL mapped
        // (typically just the single entry).
        if (entry.knownVariants.isEmpty)
          for (final variant in variants) _variantRow(entry, variant),

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: Text(entry.variantAttributes.isEmpty
                ? (variants.isEmpty ? 'Set mapping' : 'Replace mapping')
                : 'Add custom variant'),
            onPressed: () => _openEditor(entry, null),
          ),
        ),
      ],
    );
  }

  /// Returns mappings for `entry` that don't match any known preset.
  /// Compared via attributesHash (the same key Firestore uses).
  List<QxoSkuMapping> _customVariants(
      SkuRegistryEntry entry, List<QxoSkuMapping> variants) {
    if (entry.knownVariants.isEmpty) return const [];
    final knownHashes = entry.knownVariants
        .map((p) => QxoSkuMappingService.hashAttributes(p))
        .toSet();
    return variants
        .where((v) => !knownHashes.contains(v.attributesHash))
        .toList();
  }

  /// Locates the existing mapping (if any) for a known-variant preset.
  QxoSkuMapping? _findMappingForPreset(
      Map<String, dynamic> preset, List<QxoSkuMapping> variants) {
    final hash = QxoSkuMappingService.hashAttributes(preset);
    for (final v in variants) {
      if (v.attributesHash == hash) return v;
    }
    return null;
  }

  /// Compact row for a known-variant preset. Shows attribute chips, mapped
  /// status, and a Map/Edit button. Clicking opens the editor pre-filled.
  Widget _knownVariantRow(
    SkuRegistryEntry entry,
    Map<String, dynamic> preset,
    List<QxoSkuMapping> variants,
  ) {
    final existing = _findMappingForPreset(preset, variants);
    final mapped = existing?.isMapped ?? false;

    final chips = <Widget>[
      for (final attr in entry.variantAttributes)
        if (preset.containsKey(attr))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              '${preset[attr]}',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 6, height: 6,
            margin: const EdgeInsets.only(right: 8, top: 4),
            decoration: BoxDecoration(
              color: mapped ? Colors.green.shade600 : Colors.orange.shade400,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 6, runSpacing: 4, children: chips),
                if (mapped) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${existing!.qxoItemNumber}  ·  ${existing.qxoProductName ?? ""}',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (mapped)
            TextButton.icon(
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('Edit'),
              onPressed: () => _openEditor(entry, existing,
                  presetAttributes: preset),
            )
          else
            FilledButton.tonalIcon(
              icon: const Icon(Icons.link, size: 14),
              label: const Text('Map'),
              onPressed: () => _openEditor(entry, null,
                  presetAttributes: preset),
            ),
          if (mapped)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              color: Colors.red.shade400,
              tooltip: 'Remove mapping',
              onPressed: () async {
                await _service.delete(entry.skuKey, existing!.attributes);
              },
            ),
        ],
      ),
    );
  }

  Widget _variantRow(SkuRegistryEntry entry, QxoSkuMapping variant) {
    final attrText = variant.attributes.isEmpty
        ? '(no variant attributes)'
        : variant.attributes.entries
            .map((e) => '${e.key}=${e.value}')
            .join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attrText,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(
                    variant.isMapped ? Icons.link : Icons.link_off,
                    size: 14,
                    color: variant.isMapped
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      variant.isMapped
                          ? '${variant.qxoItemNumber}  ·  ${variant.qxoProductName ?? ""}'
                          : 'No QXO SKU set',
                      style: TextStyle(
                        fontSize: 11,
                        color: variant.isMapped ? AppTheme.textPrimary : AppTheme.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            tooltip: 'Edit mapping',
            onPressed: () => _openEditor(entry, variant),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Remove mapping',
            color: Colors.red.shade400,
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Remove mapping?'),
                  content: Text('This will unmap "${entry.displayName}" '
                      'for variant: $attrText'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Remove')),
                  ],
                ),
              );
              if (confirm == true) {
                await _service.delete(entry.skuKey, variant.attributes);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(
    SkuRegistryEntry entry,
    QxoSkuMapping? existing, {
    Map<String, dynamic>? presetAttributes,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _MappingEditorDialog(
        entry: entry,
        existing: existing,
        presetAttributes: presetAttributes,
        service: _service,
      ),
    );
  }
}

/// Dialog: edit a single mapping. Lets the operator set attribute values
/// (per the entry's variantAttributes) and pick a QXO SKU via search.
class _MappingEditorDialog extends StatefulWidget {
  const _MappingEditorDialog({
    required this.entry,
    required this.existing,
    required this.service,
    this.presetAttributes,
  });

  final SkuRegistryEntry entry;
  final QxoSkuMapping? existing;
  final Map<String, dynamic>? presetAttributes;
  final QxoSkuMappingService service;

  @override
  State<_MappingEditorDialog> createState() => _MappingEditorDialogState();
}

class _MappingEditorDialogState extends State<_MappingEditorDialog> {
  final _api = QxoApiService();
  final _attrControllers = <String, TextEditingController>{};
  final _searchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<QxoItem> _searchResults = [];
  QxoItem? _selectedItem;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final attr in widget.entry.variantAttributes) {
      // Priority: existing mapping value > preset value > empty.
      final initial = widget.existing?.attributes[attr]?.toString() ??
          widget.presetAttributes?[attr]?.toString() ??
          '';
      _attrControllers[attr] = TextEditingController(text: initial);
    }
    if (widget.existing?.qxoItemNumber != null) {
      _searchCtrl.text = widget.existing!.qxoItemNumber!;
      _selectedItem = QxoItem(
        itemNumber: widget.existing!.qxoItemNumber!,
        productName: widget.existing!.qxoProductName ?? '',
        internalName: '',
        brand: '',
        productId: '',
      );
    } else if (widget.presetAttributes != null) {
      // Pre-fill the search with attribute values so the operator can hit
      // Search immediately. Pulls fastenerName + length first when present.
      final p = widget.presetAttributes!;
      final query = [
        if (p['fastenerName'] != null) p['fastenerName'],
        if (p['length'] != null) p['length'],
        if (p['deckType'] != null) p['deckType'],
        if (p['thickness'] != null) p['thickness'],
        if (p['color'] != null) p['color'],
      ].whereType<Object>().join(' ');
      _searchCtrl.text = query;
      // Run the search automatically once the widget mounts.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && query.isNotEmpty) _runSearch();
      });
    }
    _notesCtrl.text = widget.existing?.notes ?? '';
  }

  @override
  void dispose() {
    for (final c in _attrControllers.values) {
      c.dispose();
    }
    _searchCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final result = await _api.searchItems(q);
      setState(() => _searchResults = result.items.take(20).toList());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _searching = false);
    }
  }

  Map<String, dynamic> _collectAttributes() {
    final attrs = <String, dynamic>{};
    for (final attr in widget.entry.variantAttributes) {
      final raw = _attrControllers[attr]!.text.trim();
      if (raw.isEmpty) continue;
      // Try to preserve numeric attributes as numbers when round-trippable.
      final asInt = int.tryParse(raw);
      final asDouble = double.tryParse(raw);
      if (asInt != null) {
        attrs[attr] = asInt;
      } else if (asDouble != null) {
        attrs[attr] = asDouble;
      } else {
        attrs[attr] = raw;
      }
    }
    return attrs;
  }

  bool _saving = false;

  Future<void> _save() async {
    if (_selectedItem == null) {
      setState(() => _error = 'Pick a QXO item first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final attrs = _collectAttributes();
      final hash = QxoSkuMappingService.hashAttributes(attrs);
      final mapping = QxoSkuMapping(
        skuKey: widget.entry.skuKey,
        attributes: attrs,
        attributesHash: hash,
        qxoItemNumber: _selectedItem!.itemNumber,
        qxoProductName: _selectedItem!.productName,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      await widget.service.save(mapping);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Save failed: $e\n\n'
            'If this says "permission-denied", deploy the updated Firestore '
            'rules: `firebase deploy --only firestore:rules` from protpo_app/.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.entry.displayName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(widget.entry.skuKey,
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              const SizedBox(height: 12),

              if (widget.entry.variantAttributes.isNotEmpty) ...[
                const Text('Variant attributes',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final attr in widget.entry.variantAttributes)
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _attrControllers[attr],
                        decoration: InputDecoration(
                          labelText: attr,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
              ],

              const Text('QXO catalog search',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search QXO by item # or product description…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: _searching
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.search, size: 16),
                  label: const Text('Search'),
                  onPressed: _searching ? null : _runSearch,
                ),
              ]),
              const SizedBox(height: 8),

              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: Colors.red.shade900, fontSize: 12)),
                    ),
                  ]),
                ),
              Expanded(
                child: _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          'Enter a search query above and tap Search.',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final it = _searchResults[i];
                          final selected =
                              _selectedItem?.itemNumber == it.itemNumber;
                          return ListTile(
                            dense: true,
                            selected: selected,
                            selectedTileColor:
                                AppTheme.primary.withValues(alpha: 0.08),
                            title: Text(it.productName,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text('#${it.itemNumber}',
                                style: TextStyle(
                                    fontSize: 11, color: AppTheme.textMuted)),
                            trailing: selected
                                ? Icon(Icons.check_circle,
                                    color: AppTheme.primary)
                                : null,
                            onTap: () => setState(() => _selectedItem = it),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),
              Row(children: [
                if (_selectedItem != null)
                  Expanded(
                    child: Text(
                      'Mapping → ${_selectedItem!.itemNumber}: ${_selectedItem!.productName}',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 16),
                  label: Text(_saving ? 'Saving…' : 'Save mapping'),
                  onPressed: (_selectedItem == null || _saving) ? null : _save,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
