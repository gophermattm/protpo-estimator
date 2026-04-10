/// lib/widgets/settings_dialog.dart
///
/// Company profile & branding settings dialog.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/estimator_providers.dart';
import '../services/platform_utils.dart';
import '../services/firestore_service.dart';
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

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
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

  void _save() async {
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

    // Persist to Firestore in background
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
    final currentProfile = ref.watch(companyProfileProvider);
    final hasLogo = _pendingLogo != null || (!_clearLogo && currentProfile.hasLogo);

    return AlertDialog(
      title: Row(children: [
        Icon(Icons.business, size: 22, color: AppTheme.primary),
        const SizedBox(width: 10),
        const Text('Company Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ]),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            // Logo section
            Text('Company Logo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Row(children: [
              Container(
                width: 120, height: 60,
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
                            : Image.memory(Uint8List.fromList(currentProfile.logoBytes!), fit: BoxFit.contain),
                      )
                    : Center(child: Icon(Icons.image, size: 28, color: Colors.grey.shade400)),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ElevatedButton.icon(
                  onPressed: _pickLogo,
                  icon: const Icon(Icons.upload, size: 16),
                  label: Text(hasLogo ? 'Change Logo' : 'Upload Logo', style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                ),
                if (hasLogo) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => setState(() { _clearLogo = true; _pendingLogo = null; }),
                    child: Text('Remove', style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ]),
            ]),

            const SizedBox(height: 20),
            Text('Company Information', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),

            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Company Name', isDense: true, prefixIcon: Icon(Icons.business, size: 18)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _taglineCtrl,
              decoration: const InputDecoration(labelText: 'Tagline (optional)', isDense: true, hintText: 'e.g. Commercial Roofing Specialists'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone', isDense: true, prefixIcon: Icon(Icons.phone, size: 18)),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email', isDense: true, prefixIcon: Icon(Icons.email, size: 18)),
              )),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Address', isDense: true, prefixIcon: Icon(Icons.location_on, size: 18)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _websiteCtrl,
              decoration: const InputDecoration(labelText: 'Website', isDense: true, prefixIcon: Icon(Icons.language, size: 18)),
            ),

            const SizedBox(height: 20),
            Text('Brand Color', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in [
                const Color(0xFF1E3A5F), // ProTPO blue
                const Color(0xFF0F172A), // Slate dark
                const Color(0xFF1E40AF), // Blue
                const Color(0xFF047857), // Green
                const Color(0xFF991B1B), // Red
                const Color(0xFF7C3AED), // Purple
                const Color(0xFFB45309), // Amber
                const Color(0xFF0E7490), // Cyan
              ])
                GestureDetector(
                  onTap: () => setState(() => _brandColor = c),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(6),
                      border: _brandColor.value == c.value
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                      boxShadow: _brandColor.value == c.value
                          ? [BoxShadow(color: c.withValues(alpha:0.5), blurRadius: 6)]
                          : null,
                    ),
                    child: _brandColor.value == c.value
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ]),

            const SizedBox(height: 20),
            // Preview
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PDF Header Preview', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(children: [
                  if (hasLogo)
                    Container(
                      height: 32, width: 80,
                      margin: const EdgeInsets.only(right: 10),
                      child: _pendingLogo != null
                          ? Image.memory(_pendingLogo!, fit: BoxFit.contain)
                          : Image.memory(Uint8List.fromList(currentProfile.logoBytes!), fit: BoxFit.contain),
                    ),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Your Company Name',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _brandColor),
                    ),
                    if (_taglineCtrl.text.isNotEmpty)
                      Text(_taglineCtrl.text, style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                  ]),
                  const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (_phoneCtrl.text.isNotEmpty)
                      Text(_phoneCtrl.text, style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                    if (_emailCtrl.text.isNotEmpty)
                      Text(_emailCtrl.text, style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                    if (_websiteCtrl.text.isNotEmpty)
                      Text(_websiteCtrl.text, style: TextStyle(fontSize: 10, color: _brandColor)),
                  ]),
                ]),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Save'),
        ),
      ],
    );
  }
}
