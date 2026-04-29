/// lib/widgets/settings_dialog.dart
///
/// Company profile & branding settings + customer management.
/// Two tabs: Company | Customers.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/customer.dart';
import '../providers/estimator_providers.dart';
import '../providers/job_providers.dart';
import '../screens/sku_mapping_admin_screen.dart';
import '../services/firestore_service.dart';
import '../services/platform_utils.dart';
import '../theme/app_theme.dart';

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // ── Company profile state ────────────────────────────────────────────
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _websiteCtrl;
  late TextEditingController _taglineCtrl;
  late Color _brandColor;
  Uint8List? _pendingLogo;
  bool _clearLogo = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));

    final profile = ref.read(companyProfileProvider);
    _nameCtrl = TextEditingController(text: profile.companyName);
    _phoneCtrl = TextEditingController(text: profile.phone);
    _emailCtrl = TextEditingController(text: profile.email);
    _addressCtrl = TextEditingController(text: profile.address);
    _websiteCtrl = TextEditingController(text: profile.website);
    _taglineCtrl = TextEditingController(text: profile.tagline);
    _brandColor = Color(profile.brandColorValue);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _websiteCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  void _pickLogo() {
    pickFileBytes(
      accept: 'image/*',
      onPicked: (bytes) {
        setState(() {
          _pendingLogo = bytes;
          _clearLogo = false;
        });
      },
    );
  }

  void _saveCompanyProfile() async {
    final current = ref.read(companyProfileProvider);
    final updated = current.copyWith(
      companyName: _nameCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      address: _addressCtrl.text,
      website: _websiteCtrl.text,
      tagline: _taglineCtrl.text,
      brandColorValue: _brandColor.value,
      logoBytes: _pendingLogo ?? (_clearLogo ? null : current.logoBytes),
      clearLogo: _clearLogo && _pendingLogo == null,
    );
    ref.read(companyProfileProvider.notifier).state = updated;
    Navigator.pop(context);

    final fs = FirestoreService.instance;
    try {
      await fs.saveCompanyProfile(updated.toJson());
      if (_pendingLogo != null) {
        await fs.saveCompanyLogo(_pendingLogo!);
      } else if (_clearLogo) {
        await fs.deleteCompanyLogo();
      }
    } catch (e) {
      debugPrint('[Settings] Firestore save error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompanyTab = _tabCtrl.index == 0;

    return AlertDialog(
      title: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.settings, size: 22, color: AppTheme.primary),
          const SizedBox(width: 10),
          const Text('Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        TabBar(
          controller: _tabCtrl,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.primary,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Company'),
            Tab(text: 'Customers'),
          ],
        ),
      ]),
      content: SizedBox(
        width: 560,
        height: 480,
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildCompanyTab(),
            const _CustomersTab(),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SkuMappingAdminScreen()),
            );
          },
          icon: const Icon(Icons.link, size: 16),
          label: const Text('SKU Mapping (BOM ↔ QXO)'),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(isCompanyTab ? 'Cancel' : 'Close'),
        ),
        if (isCompanyTab)
          ElevatedButton.icon(
            onPressed: _saveCompanyProfile,
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Save'),
          ),
      ],
    );
  }

  Widget _buildCompanyTab() {
    final currentProfile = ref.watch(companyProfileProvider);
    final hasLogo =
        _pendingLogo != null || (!_clearLogo && currentProfile.hasLogo);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text('Company Logo',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 120,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: hasLogo
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: _pendingLogo != null
                          ? Image.memory(_pendingLogo!, fit: BoxFit.contain)
                          : Image.memory(
                              Uint8List.fromList(currentProfile.logoBytes!),
                              fit: BoxFit.contain),
                    )
                  : Center(
                      child: Icon(Icons.image,
                          size: 28, color: Colors.grey.shade400)),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ElevatedButton.icon(
                onPressed: _pickLogo,
                icon: const Icon(Icons.upload, size: 16),
                label: Text(hasLogo ? 'Change Logo' : 'Upload Logo',
                    style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
              if (hasLogo) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () =>
                      setState(() { _clearLogo = true; _pendingLogo = null; }),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Remove',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
                ),
              ],
            ]),
          ]),
          const SizedBox(height: 20),
          Text('Company Information',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Company Name',
                isDense: true,
                prefixIcon: Icon(Icons.business, size: 18)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _taglineCtrl,
            decoration: const InputDecoration(
                labelText: 'Tagline (optional)',
                isDense: true,
                hintText: 'e.g. Commercial Roofing Specialists'),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                  labelText: 'Phone',
                  isDense: true,
                  prefixIcon: Icon(Icons.phone, size: 18)),
            )),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                  labelText: 'Email',
                  isDense: true,
                  prefixIcon: Icon(Icons.email, size: 18)),
            )),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _addressCtrl,
            decoration: const InputDecoration(
                labelText: 'Address',
                isDense: true,
                prefixIcon: Icon(Icons.location_on, size: 18)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _websiteCtrl,
            decoration: const InputDecoration(
                labelText: 'Website',
                isDense: true,
                prefixIcon: Icon(Icons.language, size: 18)),
          ),
          const SizedBox(height: 20),
          Text('Brand Color',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in [
                const Color(0xFF1E3A5F),
                const Color(0xFF0F172A),
                const Color(0xFF1E40AF),
                const Color(0xFF047857),
                const Color(0xFF991B1B),
                const Color(0xFF7C3AED),
                const Color(0xFFB45309),
                const Color(0xFF0E7490),
              ])
                GestureDetector(
                  onTap: () => setState(() => _brandColor = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(6),
                      border: _brandColor.value == c.value
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                      boxShadow: _brandColor.value == c.value
                          ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6)]
                          : null,
                    ),
                    child: _brandColor.value == c.value
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PDF Header Preview',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(children: [
                  if (hasLogo)
                    Container(
                      height: 32,
                      width: 80,
                      margin: const EdgeInsets.only(right: 10),
                      child: _pendingLogo != null
                          ? Image.memory(_pendingLogo!, fit: BoxFit.contain)
                          : Image.memory(
                              Uint8List.fromList(currentProfile.logoBytes!),
                              fit: BoxFit.contain),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nameCtrl.text.isNotEmpty
                            ? _nameCtrl.text
                            : 'Your Company Name',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _brandColor),
                      ),
                      if (_taglineCtrl.text.isNotEmpty)
                        Text(_taglineCtrl.text,
                            style: TextStyle(
                                fontSize: 10, color: AppTheme.textMuted)),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_phoneCtrl.text.isNotEmpty)
                        Text(_phoneCtrl.text,
                            style: TextStyle(
                                fontSize: 10, color: AppTheme.textSecondary)),
                      if (_emailCtrl.text.isNotEmpty)
                        Text(_emailCtrl.text,
                            style: TextStyle(
                                fontSize: 10, color: AppTheme.textSecondary)),
                      if (_websiteCtrl.text.isNotEmpty)
                        Text(_websiteCtrl.text,
                            style: TextStyle(
                                fontSize: 10, color: _brandColor)),
                    ],
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CUSTOMERS TAB
// ══════════════════════════════════════════════════════════════════════════════

class _CustomersTab extends ConsumerWidget {
  const _CustomersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersListProvider);

    return customersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 32, color: AppTheme.error),
          const SizedBox(height: 8),
          Text('Failed to load customers',
              style: TextStyle(color: AppTheme.error)),
          const SizedBox(height: 4),
          Text('$e', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ]),
      ),
      data: (customers) => Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Text('${customers.length} customer${customers.length == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _showEditDialog(context, ref, null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Customer', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
              ),
            ),
          ]),
        ),
        Expanded(
          child: customers.isEmpty
              ? Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Icon(Icons.people_outline,
                        size: 40, color: AppTheme.textMuted),
                    const SizedBox(height: 8),
                    Text('No customers yet',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textMuted)),
                    const SizedBox(height: 4),
                    Text('Add your first customer to get started.',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textMuted)),
                  ]))
              : ListView.separated(
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) =>
                      _CustomerRow(customer: customers[i]),
                ),
        ),
      ]),
    );
  }

  static void _showEditDialog(
      BuildContext context, WidgetRef ref, Customer? existing) {
    showDialog(
      context: context,
      builder: (_) => _CustomerEditDialog(existing: existing),
    );
  }
}

class _CustomerRow extends ConsumerWidget {
  final Customer customer;
  const _CustomerRow({required this.customer});

  static const _typeLabels = {
    CustomerType.Company: 'Company',
    CustomerType.InsuranceCarrier: 'Insurance Carrier',
    CustomerType.PropertyManager: 'Property Manager',
    CustomerType.GeneralContractor: 'General Contractor',
    CustomerType.Individual: 'Individual',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
        child: Text(
          customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
          style: TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13),
        ),
      ),
      title: Text(customer.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          _typeLabels[customer.customerType] ?? 'Company',
          if (customer.primaryContactName.isNotEmpty)
            customer.primaryContactName,
          if (customer.phone.isNotEmpty) customer.phone,
        ].join(' \u2022 '),
        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: Icon(Icons.edit, size: 16, color: AppTheme.textSecondary),
          tooltip: 'Edit',
          onPressed: () => _CustomersTab._showEditDialog(
              context, ref, customer),
          splashRadius: 18,
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
          tooltip: 'Delete',
          onPressed: () => _confirmDelete(context, ref),
          splashRadius: 18,
        ),
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final jobsAsync = ref.read(jobsListProvider);
    final jobs = jobsAsync.valueOrNull ?? [];
    final referencingJobs =
        jobs.where((j) => j.customerId == customer.id).toList();

    if (referencingJobs.isNotEmpty) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(children: [
            Icon(Icons.warning_amber, color: AppTheme.warning, size: 22),
            const SizedBox(width: 8),
            const Text('Cannot Delete Customer',
                style: TextStyle(fontSize: 16)),
          ]),
          content: SizedBox(
            width: 400,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                '${customer.name} is referenced by ${referencingJobs.length} '
                'job${referencingJobs.length == 1 ? '' : 's'}:',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              ...referencingJobs.take(5).map((j) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                    child: Row(children: [
                      Icon(Icons.work_outline,
                          size: 14, color: AppTheme.textMuted),
                      const SizedBox(width: 6),
                      Text(j.jobName,
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  )),
              if (referencingJobs.length > 5)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                      '...and ${referencingJobs.length - 5} more',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textMuted)),
                ),
              const SizedBox(height: 12),
              Text(
                'Reassign or delete these jobs first, then try again.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Customer?', style: TextStyle(fontSize: 16)),
        content: Text('Delete "${customer.name}"? This cannot be undone.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirestoreService.instance.deleteCustomer(customer.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }
}

class _CustomerEditDialog extends ConsumerStatefulWidget {
  final Customer? existing;

  const _CustomerEditDialog({this.existing});

  @override
  ConsumerState<_CustomerEditDialog> createState() =>
      _CustomerEditDialogState();
}

class _CustomerEditDialogState extends ConsumerState<_CustomerEditDialog> {
  final _uuid = const Uuid();
  late TextEditingController _nameCtrl;
  late TextEditingController _contactCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _notesCtrl;
  late CustomerType _type;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _contactCtrl = TextEditingController(text: c?.primaryContactName ?? '');
    _phoneCtrl = TextEditingController(text: c?.phone ?? '');
    _emailCtrl = TextEditingController(text: c?.email ?? '');
    _addressCtrl = TextEditingController(text: c?.mailingAddress ?? '');
    _notesCtrl = TextEditingController(text: c?.notes ?? '');
    _type = c?.customerType ?? CustomerType.Company;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      final customer = Customer(
        id: widget.existing?.id ?? _uuid.v4(),
        name: name,
        customerType: _type,
        primaryContactName: _contactCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        mailingAddress: _addressCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );

      final fs = FirestoreService.instance;
      if (_isEdit) {
        await fs.updateCustomer(customer);
      } else {
        await fs.createCustomer(customer);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _typeOptions = {
    CustomerType.Company: 'Company',
    CustomerType.InsuranceCarrier: 'Insurance Carrier',
    CustomerType.PropertyManager: 'Property Manager',
    CustomerType.GeneralContractor: 'General Contractor',
    CustomerType.Individual: 'Individual',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(_isEdit ? Icons.edit : Icons.person_add,
            size: 20, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(_isEdit ? 'Edit Customer' : 'Add Customer',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ]),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            TextField(
              controller: _nameCtrl,
              autofocus: !_isEdit,
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                isDense: true,
                prefixIcon: Icon(Icons.business, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CustomerType>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Type',
                isDense: true,
                prefixIcon: Icon(Icons.category, size: 18),
              ),
              items: _typeOptions.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) { if (v != null) setState(() => _type = v); },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contactCtrl,
              decoration: const InputDecoration(
                labelText: 'Primary Contact Name',
                isDense: true,
                prefixIcon: Icon(Icons.person, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    isDense: true,
                    prefixIcon: Icon(Icons.phone, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    isDense: true,
                    prefixIcon: Icon(Icons.email, size: 18),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Mailing Address',
                isDense: true,
                prefixIcon: Icon(Icons.location_on, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                isDense: true,
                hintText:
                    'Preferred contact method, payment terms, etc.',
                alignLabelWithHint: true,
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_isEdit ? Icons.save : Icons.add, size: 16),
          label: Text(_isEdit ? 'Save' : 'Add Customer'),
        ),
      ],
    );
  }
}
