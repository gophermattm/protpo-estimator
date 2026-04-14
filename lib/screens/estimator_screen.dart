/// lib/screens/estimator_screen.dart
///
/// Main 3-panel estimator screen.
///
/// Multi-building change:
///   A BuildingTabBar is rendered between the AppBar and the 3-panel body.
///   It shows one tab per building in the project, with an "+ Add Building"
///   button at the end. Tapping a tab calls setActiveBuilding(index).
///   Double-tapping a tab name lets the user rename it inline.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_polish.dart';
import '../widgets/left_panel.dart';
import '../widgets/center_panel.dart';
import '../widgets/right_panel.dart';
import '../providers/estimator_providers.dart';
import '../models/estimator_state.dart';
import '../services/firestore_service.dart';
import 'job_list_sheet.dart';
import '../providers/job_providers.dart';
import '../services/serialization.dart';
import '../models/estimate.dart';
import 'job_detail_screen.dart';
import '../services/export_service.dart';
import '../widgets/settings_dialog.dart';
import '../services/validation_engine.dart';
import '../services/platform_utils.dart';
import '../models/estimate_version.dart';
import '../models/activity.dart';

class EstimatorScreen extends ConsumerStatefulWidget {
  const EstimatorScreen({super.key});

  @override
  ConsumerState<EstimatorScreen> createState() => _EstimatorScreenState();
}

class _EstimatorScreenState extends ConsumerState<EstimatorScreen> {
  bool _isExporting = false;
  bool _hasUnsavedChanges = false;
  int? _lastSavedState; // hashCode of EstimatorState at last save
  bool _isSaving = false;
  bool _saveSuccess = false;
  bool _autoSaveDone = false; // true once first auto-draft saved

  @override
  void initState() {
    super.initState();
    // Warn browser before tab close if there are unsaved changes
    registerBeforeUnload(() => _hasUnsavedChanges);
    // Load company profile from Firestore
    _loadCompanyProfile();
  }

  Future<void> _loadCompanyProfile() async {
    try {
      final fs = FirestoreService.instance;
      final json = await fs.loadCompanyProfile();
      if (json != null) {
        var profile = CompanyProfile.fromJson(json);
        // Load logo separately
        final logoBytes = await fs.loadCompanyLogo();
        if (logoBytes != null) {
          profile = profile.copyWith(logoBytes: logoBytes);
        }
        if (mounted) {
          ref.read(companyProfileProvider.notifier).state = profile;
        }
      }
    } catch (e) {
      debugPrint('[Settings] Failed to load company profile: $e');
    }
  }

  /// Called by ref.listen whenever state changes — triggers autosave
  /// after first meaningful edit if a job estimate is active.
  Future<void> _maybeAutosave(EstimatorState state) async {
    if (!mounted || _autoSaveDone) return;

    final hasActiveEst = ref.read(hasActiveEstimateProvider);
    if (!hasActiveEst) return;

    final hasData = state.projectInfo.projectName.isNotEmpty ||
        (state.buildings.isNotEmpty &&
         state.buildings.first.roofGeometry.totalArea > 0);
    if (!hasData) return;

    _autoSaveDone = true;
    try {
      final jobId = ref.read(activeJobIdProvider)!;
      final estId = ref.read(activeEstimateIdProvider)!;
      final estName = ref.read(activeEstimateNameProvider);
      final serialized = stateToJson(state, estId);
      final totalArea = state.buildings
          .fold(0.0, (sum, b) => sum + b.roofGeometry.totalArea);

      final draft = Estimate(
        id: estId,
        name: estName,
        estimatorState: serialized,
        totalArea: totalArea,
        totalValue: 0,
        buildingCount: state.buildings.length,
      );
      await FirestoreService.instance.updateEstimate(jobId, draft);
      if (mounted) {
        setState(() {
          _hasUnsavedChanges = false;
          _lastSavedState    = state.hashCode;
        });
      }
    } catch (e) {
      _autoSaveDone = false;
    }
  }


  Future<void> _saveProject() async {
    if (_isSaving) return;

    final hasActiveEst = ref.read(hasActiveEstimateProvider);
    if (!hasActiveEst) {
      AppSnackbar.info(context, 'Create or open a job first \u2014 tap "Jobs" in the toolbar.');
      return;
    }

    setState(() { _isSaving = true; _saveSuccess = false; });

    try {
      final jobId = ref.read(activeJobIdProvider)!;
      final estId = ref.read(activeEstimateIdProvider)!;
      final estName = ref.read(activeEstimateNameProvider);
      final state = ref.read(estimatorProvider);
      final serialized = stateToJson(state, estId);

      final totalArea = state.buildings
          .fold(0.0, (sum, b) => sum + b.roofGeometry.totalArea);

      final draft = Estimate(
        id: estId,
        name: estName,
        estimatorState: serialized,
        totalArea: totalArea,
        totalValue: 0,
        buildingCount: state.buildings.length,
      );
      await FirestoreService.instance.updateEstimate(jobId, draft);

      setState(() {
        _isSaving = false;
        _saveSuccess = true;
        _hasUnsavedChanges = false;
        _lastSavedState = state.hashCode;
      });
      if (mounted) {
        AppSnackbar.success(context, 'Saved estimate "$estName"');
      }

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saveSuccess = false);
      });
    } catch (e, stack) {
      debugPrint('[SAVE] Save failed: $e');
      debugPrint('[SAVE] Stack: $stack');
      setState(() => _isSaving = false);
      if (mounted) {
        AppSnackbar.error(context, 'Save failed: $e');
      }
    }
  }

  /// Debug entry point for the new Job List (Phase 4).
  /// Long-press the Open button to reach this. Phase 8 replaces the
  /// regular Open tap handler with this.
  Future<void> _openJobList() async {
    await showJobList(context);
  }

  Widget _buildContextRibbon(bool isMobile) {
    final hasJob = ref.watch(hasActiveEstimateProvider);
    if (!hasJob) {
      return GestureDetector(
        onTap: _openJobList,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: AppTheme.primary.withValues(alpha: 0.04),
          child: Row(children: [
            Icon(Icons.info_outline, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            Text('No job loaded \u2014 tap to open a job',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ]),
        ),
      );
    }

    final customerName = ref.watch(activeCustomerNameProvider);
    final jobName = ref.watch(activeJobNameProvider);
    final estName = ref.watch(activeEstimateNameProvider);

    return GestureDetector(
      onTap: () {
        final jobId = ref.read(activeJobIdProvider);
        if (jobId != null) {
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: jobId)),
          );
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          border: Border(
            bottom: BorderSide(
                color: AppTheme.primary.withValues(alpha: 0.15)),
          ),
        ),
        child: Row(children: [
          Icon(Icons.work_outline, size: 14, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (!isMobile && customerName.isNotEmpty) ...[
                  TextSpan(text: customerName,
                      style: TextStyle(color: AppTheme.textSecondary)),
                  TextSpan(text: '  \u203A  ',
                      style: TextStyle(color: AppTheme.textMuted)),
                ],
                TextSpan(text: jobName.isNotEmpty ? jobName : 'Job',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: '  \u203A  ',
                    style: TextStyle(color: AppTheme.textMuted)),
                TextSpan(text: estName.isNotEmpty ? estName : 'Estimate',
                    style: TextStyle(color: AppTheme.textSecondary)),
                TextSpan(text: ' (draft)',
                    style: TextStyle(
                        fontSize: 10, color: AppTheme.textMuted)),
              ]),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _promptSaveVersion,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.bookmark_add_outlined,
                    size: 12, color: AppTheme.accent),
                const SizedBox(width: 4),
                Text('Version',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent)),
              ]),
            ),
          ),
          Icon(Icons.chevron_right, size: 16, color: AppTheme.textMuted),
        ]),
      ),
    );
  }

  Future<void> _saveVersion({
    required String source,
    String? label,
  }) async {
    final jobId = ref.read(activeJobIdProvider);
    final estId = ref.read(activeEstimateIdProvider);
    if (jobId == null || estId == null) return;

    final state = ref.read(estimatorProvider);
    final estName = ref.read(activeEstimateNameProvider);
    final serialized = stateToJson(state, estId);
    final profile = ref.read(companyProfileProvider);
    final now = DateTime.now();

    final defaultLabel = source == 'export'
        ? 'Export ${DateFormat('yyyy-MM-dd HH:mm').format(now)}'
        : 'Manual snapshot ${DateFormat('yyyy-MM-dd HH:mm').format(now)}';

    final version = EstimateVersion(
      id: '',
      label: label?.isNotEmpty == true ? label! : defaultLabel,
      source: source == 'export' ? VersionSource.export : VersionSource.manual,
      estimatorState: serialized,
      createdAt: now,
      createdBy: profile.companyName.isNotEmpty
          ? profile.companyName
          : 'ProTPO',
    );

    try {
      final versionId = await FirestoreService.instance
          .createVersion(jobId, estId, version);

      final currentEst = await FirestoreService.instance
          .getEstimate(jobId, estId);
      if (currentEst != null) {
        await FirestoreService.instance.updateEstimate(
          jobId,
          currentEst.copyWith(activeVersionId: versionId),
        );
      }

      final activity = Activity(
        id: '',
        type: ActivityType.system,
        timestamp: now,
        author: 'system',
        body: source == 'export'
            ? 'Version saved before export: ${version.label}'
            : 'Version saved: ${version.label}',
        systemEventKind: 'version_saved',
        systemEventData: {
          'versionId': versionId,
          'label': version.label,
          'source': source,
          'estimateName': estName,
        },
      );
      await FirestoreService.instance.createActivity(jobId, activity);

      if (source == 'manual' && mounted) {
        AppSnackbar.success(context, 'Version saved: "${version.label}"');
      }
    } catch (e) {
      debugPrint('[VERSION] Save failed: $e');
      if (source == 'manual' && mounted) {
        AppSnackbar.error(context, 'Version save failed: $e');
      }
    }
  }

  Future<void> _promptSaveVersion() async {
    final ctrl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as Version',
            style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Version label (optional)',
            isDense: true,
            hintText: 'e.g. v2 — added Building B',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save Version'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (label == null) return;

    await _saveVersion(source: 'manual', label: label);
  }

  Future<void> _export(String format) async {
    if (_isExporting) return;
    if (format == 'csv') {
      setState(() => _isExporting = true);
      try {
        final state = ref.read(estimatorProvider);
        final bom = ref.read(bomProvider);
        await ExportService.downloadCsv(state, bom);
      } catch (e) {
        if (mounted) AppSnackbar.error(context, 'Export failed: $e');
      } finally {
        if (mounted) setState(() => _isExporting = false);
      }
      return;
    }

    // PDF — ask for view type
    final viewType = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF View Type', style: TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.engineering),
            title: const Text('Contractor View'),
            subtitle: const Text('Includes cost, margin, and sell price'),
            onTap: () => Navigator.of(ctx).pop('contractor'),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Customer View'),
            subtitle: const Text('Shows only unit price and line totals'),
            onTap: () => Navigator.of(ctx).pop('customer'),
          ),
        ]),
      ),
    );
    if (viewType == null || !mounted) return;

    // Second dialog: let user pick which pages to include
    final sections = await _showPdfSectionsDialog();
    if (sections == null || !mounted) return;

    setState(() => _isExporting = true);
    try {
      // Auto-snapshot version before export (if a job estimate is active)
      if (ref.read(hasActiveEstimateProvider)) {
        await _saveVersion(source: 'export');
      }

      final state = ref.read(estimatorProvider);
      final bom = ref.read(bomProvider);
      final rValue = ref.read(rValueResultProvider);
      final profile = ref.read(companyProfileProvider);
      final pricedItems = ref.read(pricedItemsProvider);
      final globalMargin = ref.read(globalMarginProvider);
      final itemOverrides = ref.read(itemMarginOverridesProvider);
      final laborItems = ref.read(laborLineItemsProvider);
      final bomEdits = ref.read(bomLineEditsProvider);
      final bomDeleted = ref.read(bomDeletedItemsProvider);
      final bomManual = ref.read(bomManualItemsProvider);
      await ExportService.downloadPdf(state, bom,
          rValue: rValue, logoBytes: profile.logoBytes, pricedItems: pricedItems,
          globalMargin: globalMargin, itemMarginOverrides: itemOverrides,
          viewType: viewType,
          laborItems: laborItems.isNotEmpty ? laborItems : null,
          companyProfile: profile,
          bomEdits: bomEdits, bomDeleted: bomDeleted, bomManualItems: bomManual,
          sections: sections);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Shows a dialog with checkboxes for each optional PDF page.
  /// Returns null if cancelled, else a PdfSections with user selections.
  Future<PdfSections?> _showPdfSectionsDialog() async {
    bool materialsTakeoff = true;
    bool fasteningSchedule = true;
    bool thermalCode = true;
    bool scopeOfWork = true;
    bool installInstructions = true;

    return showDialog<PdfSections>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Include Pages', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Cover page and roof plan are always included.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Materials Takeoff'),
                subtitle: const Text('BOM line items and totals',
                    style: TextStyle(fontSize: 11)),
                value: materialsTakeoff,
                onChanged: (v) => setLocal(() => materialsTakeoff = v ?? false),
              ),
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Fastening Schedule'),
                subtitle: const Text('Fasteners & plates category in the BOM',
                    style: TextStyle(fontSize: 11)),
                value: fasteningSchedule,
                onChanged: materialsTakeoff
                    ? (v) => setLocal(() => fasteningSchedule = v ?? false)
                    : null,
              ),
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Thermal & Code Compliance'),
                subtitle: const Text('R-value breakdown and code check',
                    style: TextStyle(fontSize: 11)),
                value: thermalCode,
                onChanged: (v) => setLocal(() => thermalCode = v ?? false),
              ),
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Scope of Work'),
                subtitle: const Text('Customer-facing project narrative',
                    style: TextStyle(fontSize: 11)),
                value: scopeOfWork,
                onChanged: (v) => setLocal(() => scopeOfWork = v ?? false),
              ),
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Installation Instructions'),
                subtitle: const Text('Subcontractor install guide',
                    style: TextStyle(fontSize: 11)),
                value: installInstructions,
                onChanged: (v) => setLocal(() => installInstructions = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(PdfSections(
                materialsTakeoff: materialsTakeoff,
                fasteningSchedule: fasteningSchedule,
                thermalCode: thermalCode,
                scopeOfWork: scopeOfWork,
                installInstructions: installInstructions,
              )),
              child: const Text('Export'),
            ),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth > 1200;
    final isTablet = screenWidth > 768 && screenWidth <= 1200;

    // Track unsaved changes whenever estimator state changes
    ref.listen(estimatorProvider, (prev, next) {
      if (_lastSavedState != null && next.hashCode != _lastSavedState) {
        if (mounted && !_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
      }
      // Auto-save draft on first meaningful change
      if (prev != next) {
        _maybeAutosave(next);
      }
    });

    final isMobile = screenWidth <= 768;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isLandscapeTight = isMobile && screenHeight < 500;

    return Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(isMobile),
      body: Column(
        children: [
          // Job context ribbon — shows which job/estimate is loaded
          _buildContextRibbon(isMobile),
          // Hide building tab bar in tight landscape to save vertical space
          if (!isLandscapeTight) const BuildingTabBar(),
          // 3-panel body
          Expanded(
            child: isDesktop
                ? _buildDesktopLayout()
                : isTablet
                    ? _buildTabletLayout()
                    : _buildMobileLayout(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    final profile = ref.watch(companyProfileProvider);
    final hasCompany = profile.hasName;
    final brandColor = Color(profile.brandColorValue);

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleSpacing: isMobile ? 8 : null,
      title: Row(
        children: [
          // Logo or default icon
          if (profile.hasLogo)
            Container(
              height: isMobile ? 32 : 36,
              constraints: BoxConstraints(maxWidth: isMobile ? 80 : 120),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: brandColor.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.memory(
                Uint8List.fromList(profile.logoBytes!),
                fit: BoxFit.contain,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (hasCompany ? brandColor : AppTheme.primary).withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.roofing,
                  color: hasCompany ? brandColor : AppTheme.primary,
                  size: isMobile ? 20 : 24),
            ),
          const SizedBox(width: 8),
          // Company name or ProTPO
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hasCompany ? profile.companyName : 'ProTPO',
                  style: TextStyle(color: hasCompany ? brandColor : AppTheme.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: isMobile ? 14 : 18)),
              if (hasCompany && profile.tagline.isNotEmpty && !isMobile)
                Text(profile.tagline, style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w400)),
            ],
          ),
          UnsavedDot(visible: _hasUnsavedChanges && ref.watch(hasActiveEstimateProvider)),
          if (!isMobile) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(4)),
              child: Text('ESTIMATOR', style: TextStyle(color: AppTheme.accent,
                  fontWeight: FontWeight.w600, fontSize: 10, letterSpacing: 1)),
            ),
          ],
        ],
      ),
      actions: [
        if (isMobile) ...[
          // Compact icon-only buttons on mobile
          IconButton(
            onPressed: _openJobList,
            icon: const Icon(Icons.work_outline, size: 20),
            color: AppTheme.textSecondary,
            tooltip: 'Jobs',
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              onPressed: _saveProject,
              icon: Icon(_saveSuccess ? Icons.check_circle : Icons.save_outlined, size: 20,
                  color: _saveSuccess ? AppTheme.accent : AppTheme.textSecondary),
              tooltip: _saveSuccess ? 'Saved!' : 'Save',
            ),
          IconButton(
            onPressed: () => SettingsDialog.show(context),
            icon: Icon(Icons.settings, size: 20, color: AppTheme.textSecondary),
            tooltip: 'Company Settings',
          ),
          PopupMenuButton<String>(
            onSelected: _export,
            icon: Icon(Icons.download, size: 20, color: AppTheme.primary),
            tooltip: 'Export',
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pdf',
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf, size: 16, color: Color(0xFFEF4444)),
                    SizedBox(width: 10), Text('Download PDF'),
                  ])),
              const PopupMenuItem(value: 'csv',
                  child: Row(children: [
                    Icon(Icons.table_chart, size: 16, color: Color(0xFF10B981)),
                    SizedBox(width: 10), Text('Download CSV'),
                  ])),
            ],
          ),
        ] else ...[
          // Full labels on desktop/tablet
          const _ProjectHealthChip(),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _openJobList,
            icon: const Icon(Icons.work_outline, size: 18),
            label: const Text('Jobs'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
          ),
          const SizedBox(width: 4),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton.icon(
              onPressed: _saveProject,
              icon: Icon(_saveSuccess ? Icons.check_circle : Icons.save_outlined, size: 18,
                  color: _saveSuccess ? AppTheme.accent : null),
              label: Text(_saveSuccess ? 'Saved!' : 'Save',
                  style: TextStyle(color: _saveSuccess ? AppTheme.accent : null)),
            ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: () => SettingsDialog.show(context),
            icon: Icon(Icons.settings, size: 18, color: AppTheme.textSecondary),
            label: Text('Settings', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          const SizedBox(width: 8),
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            PopupMenuButton<String>(
              onSelected: _export,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'pdf',
                    child: Row(children: [
                      Icon(Icons.picture_as_pdf, size: 16, color: Color(0xFFEF4444)),
                      SizedBox(width: 10), Text('Download PDF'),
                    ])),
                const PopupMenuItem(value: 'csv',
                    child: Row(children: [
                      Icon(Icons.table_chart, size: 16, color: Color(0xFF10B981)),
                      SizedBox(width: 10), Text('Download CSV'),
                    ])),
              ],
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.download, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text('Export', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                ]),
              ),
            ),
          const SizedBox(width: 16),
        ],
      ],
    );
  }


  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: AppTheme.leftPanelBg,
            border: Border(right: BorderSide(color: AppTheme.border)),
          ),
          child: FocusTraversalGroup(child: const LeftPanel()),
        ),
        Expanded(
          flex: 3,
          child: Container(
            color: AppTheme.centerPanelBg,
            child: FocusTraversalGroup(child: const CenterPanel()),
          ),
        ),
        Container(
          width: 360,
          decoration: BoxDecoration(
            color: AppTheme.rightPanelBg,
            border: Border(left: BorderSide(color: AppTheme.border)),
          ),
          child: FocusTraversalGroup(child: const RightPanel()),
        ),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      children: [
        Container(
          width: 280,
          decoration: BoxDecoration(
            color: AppTheme.leftPanelBg,
            border: Border(right: BorderSide(color: AppTheme.border)),
          ),
          child: FocusTraversalGroup(child: const LeftPanel()),
        ),
        Expanded(child: FocusTraversalGroup(child: const CenterPanel())),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 3,
              isScrollable: false,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              tabs: const [
                Tab(height: 44, text: 'Inputs'),
                Tab(height: 44, text: 'Estimate'),
                Tab(height: 44, text: 'VersiBot'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [LeftPanel(), CenterPanel(), RightPanel()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── BUILDING TAB BAR ────────────────────────────────────────────────────────

/// Horizontal strip of building tabs that sits below the AppBar.
/// - One chip per building
/// - Active tab highlighted in primary blue
/// - Double-tap any tab name to rename it inline
/// - "+ Add Building" button always last
/// - "×" delete button on each tab (hidden when only one building)
class BuildingTabBar extends ConsumerStatefulWidget {
  const BuildingTabBar({super.key});

  @override
  ConsumerState<BuildingTabBar> createState() => _BuildingTabBarState();
}

class _BuildingTabBarState extends ConsumerState<BuildingTabBar> {
  // Track which tab (if any) is in rename mode
  int? _renamingIndex;
  final TextEditingController _renameController = TextEditingController();
  final FocusNode _renameFocus = FocusNode();

  @override
  void dispose() {
    _renameController.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  void _startRename(int index, String currentName) {
    setState(() {
      _renamingIndex = index;
      _renameController.text = currentName;
    });
    // Focus after frame so the TextField is in the tree
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _renameFocus.requestFocus();
      _renameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _renameController.text.length,
      );
    });
  }

  void _commitRename() {
    if (_renamingIndex == null) return;
    final name = _renameController.text.trim();
    if (name.isNotEmpty) {
      ref
          .read(estimatorProvider.notifier)
          .renameBuilding(_renamingIndex!, name);
    }
    setState(() => _renamingIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final buildings = ref.watch(buildingsProvider);
    final activeIndex = ref.watch(activeBuildingIndexProvider);
    final notifier = ref.read(estimatorProvider.notifier);
    final canDelete = buildings.length > 1;
    final isMobile = MediaQuery.sizeOf(context).width <= 768;

    // Mobile: compact dropdown instead of full tab strip
    if (isMobile) {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(children: [
          Icon(Icons.domain, size: 14, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: activeIndex,
                isDense: true,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                items: buildings.asMap().entries.map((e) =>
                  DropdownMenuItem(value: e.key, child: Text(e.value.buildingName)),
                ).toList(),
                onChanged: (i) { if (i != null) notifier.setActiveBuilding(i); },
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => notifier.addBuilding(),
            icon: const Icon(Icons.add, size: 12),
            label: const Text('Add'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
    }

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Row(
        children: [
          // Scrollable tab list
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: buildings.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final isActive = index == activeIndex;
                final building = buildings[index];
                final isRenaming = _renamingIndex == index;

                return GestureDetector(
                  onTap: () => notifier.setActiveBuilding(index),
                  onDoubleTap: () =>
                      _startRename(index, building.buildingName),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 0),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppTheme.primary
                          : AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isActive
                            ? AppTheme.primary
                            : AppTheme.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Building icon
                        Icon(
                          Icons.domain,
                          size: 14,
                          color: isActive
                              ? Colors.white.withValues(alpha:0.8)
                              : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 6),

                        // Name — either inline editor or label
                        if (isRenaming)
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _renameController,
                              focusNode: _renameFocus,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isActive
                                    ? Colors.white
                                    : AppTheme.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _commitRename(),
                              onEditingComplete: _commitRename,
                            ),
                          )
                        else
                          Text(
                            building.buildingName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? Colors.white
                                  : AppTheme.textPrimary,
                            ),
                          ),

                        // Delete button — only when > 1 building
                        if (canDelete) ...[
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 36, height: 36,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              iconSize: 13,
                              tooltip: 'Remove building',
                              onPressed: () => _confirmDelete(context, index,
                                  building.buildingName, notifier),
                              icon: Icon(
                                Icons.close,
                                color: isActive
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Add building button
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: OutlinedButton.icon(
              onPressed: () => notifier.addBuilding(),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Building'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: BorderSide(color: AppTheme.primary.withValues(alpha:0.4)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                minimumSize: const Size(0, 44),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows a confirmation dialog before deleting a building.
  Future<void> _confirmDelete(
    BuildContext context,
    int index,
    String buildingName,
    EstimatorNotifier notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Building?'),
        content: Text(
          'Remove "$buildingName" and all its inputs? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      notifier.removeBuilding(index);
    }
  }
}

// ─── PROJECT HEALTH CHIP ─────────────────────────────────────────────────────

class _ProjectHealthChip extends ConsumerWidget {
  const _ProjectHealthChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vr = ref.watch(validationResultProvider);
    final score = vr.healthScore;

    final Color color;
    final IconData icon;
    if (score >= 85) {
      color = const Color(0xFF10B981); // green
      icon = Icons.check_circle;
    } else if (score >= 60) {
      color = const Color(0xFFF59E0B); // amber
      icon = Icons.warning_amber_rounded;
    } else {
      color = const Color(0xFFEF4444); // red
      icon = Icons.error;
    }

    final issueCount = vr.errorCount + vr.warningCount + vr.missingItems.length;

    return InkWell(
      onTap: () => _showHealthDetail(context, vr),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha:0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text('$score%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          if (issueCount > 0) ...[
            const SizedBox(width: 4),
            Text('($issueCount)', style: TextStyle(fontSize: 10, color: color.withValues(alpha:0.7))),
          ],
        ]),
      ),
    );
  }

  void _showHealthDetail(BuildContext context, ValidationResult vr) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(Icons.health_and_safety, size: 22, color: vr.healthScore >= 85
            ? const Color(0xFF10B981) : vr.healthScore >= 60
            ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
        const SizedBox(width: 10),
        Text('Project Health: ${vr.healthScore}%', style: const TextStyle(fontSize: 18)),
      ]),
      content: SizedBox(
        width: 550, height: 500,
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (vr.errorCount > 0) ...[
              _sectionLabel('ERRORS', const Color(0xFFEF4444)),
              ...vr.issues.where((i) => i.severity == IssueSeverity.error).map((i) =>
                  _issueTile(i, const Color(0xFFEF4444))),
              const SizedBox(height: 12),
            ],
            if (vr.warningCount > 0) ...[
              _sectionLabel('WARNINGS', const Color(0xFFF59E0B)),
              ...vr.issues.where((i) => i.severity == IssueSeverity.warning).map((i) =>
                  _issueTile(i, const Color(0xFFF59E0B))),
              const SizedBox(height: 12),
            ],
            if (vr.missingItems.isNotEmpty) ...[
              _sectionLabel('MISSING VERSICO SPEC ITEMS', const Color(0xFFEF4444)),
              ...vr.missingItems.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (m.isCritical ? const Color(0xFFEF4444) : const Color(0xFFF59E0B)).withValues(alpha:0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: (m.isCritical ? const Color(0xFFEF4444) : const Color(0xFFF59E0B)).withValues(alpha:0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(m.isCritical ? Icons.error : Icons.warning_amber, size: 14,
                          color: m.isCritical ? const Color(0xFFEF4444) : const Color(0xFFF59E0B)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(m.missingItem, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    ]),
                    const SizedBox(height: 4),
                    Text('Required by: ${m.triggerItem}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Text(m.reason, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  ]),
                ),
              )),
              const SizedBox(height: 12),
            ],
            if (vr.okCount > 0) ...[
              _sectionLabel('PASSING', const Color(0xFF10B981)),
              ...vr.issues.where((i) => i.severity == IssueSeverity.ok).map((i) =>
                  _issueTile(i, const Color(0xFF10B981))),
              const SizedBox(height: 12),
            ],
            if (vr.issues.where((i) => i.severity == IssueSeverity.info).isNotEmpty) ...[
              _sectionLabel('INFO', Colors.blue),
              ...vr.issues.where((i) => i.severity == IssueSeverity.info).map((i) =>
                  _issueTile(i, Colors.blue)),
            ],
          ],
        )),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ));
  }

  Widget _sectionLabel(String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 1)),
  );

  Widget _issueTile(ValidationIssue issue, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha:0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha:0.15), borderRadius: BorderRadius.circular(4)),
            child: Text(issue.category, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(issue.message, style: const TextStyle(fontSize: 12))),
        ]),
        if (issue.fix != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.lightbulb, size: 12, color: Colors.amber.shade700),
            const SizedBox(width: 4),
            Expanded(child: Text(issue.fix!, style: TextStyle(fontSize: 11, color: Colors.amber.shade800, fontStyle: FontStyle.italic))),
          ]),
        ],
      ]),
    ),
  );
}
