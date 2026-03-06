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
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_polish.dart';
import '../widgets/left_panel.dart';
import '../widgets/center_panel.dart';
import '../widgets/right_panel.dart';
import '../providers/estimator_providers.dart';
import '../services/firestore_service.dart';
import 'project_list_screen.dart';
import '../services/export_service.dart';

class EstimatorScreen extends ConsumerStatefulWidget {
  const EstimatorScreen({super.key});

  @override
  ConsumerState<EstimatorScreen> createState() => _EstimatorScreenState();
}

class _EstimatorScreenState extends ConsumerState<EstimatorScreen> {
  String? _currentProjectId; // null = unsaved
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
    html.window.onBeforeUnload.listen((event) {
      if (_hasUnsavedChanges) {
        (event as html.BeforeUnloadEvent).returnValue =
            'You have unsaved changes. Are you sure you want to leave?';
      }
    });
  }

  /// Called by ref.listen whenever state changes — triggers autosave
  /// after first meaningful edit if project has not been saved yet.
  Future<void> _maybeAutosave(EstimatorState state) async {
    if (!mounted || _autoSaveDone) return;
    // Only autosave if there's something worth saving
    final hasData = state.projectInfo.projectName.isNotEmpty ||
        (state.buildings.isNotEmpty &&
         state.buildings.first.roofGeometry.totalArea > 0);
    if (!hasData) return;
    _autoSaveDone = true; // prevent repeat attempts
    try {
      final id = await FirestoreService.instance.save(
          state, projectId: _currentProjectId);
      if (mounted) {
        setState(() {
          _currentProjectId  = id;
          _hasUnsavedChanges = false;
          _lastSavedState    = state.hashCode;
        });
        AppSnackbar.info(context, 'Auto-draft saved — tap Save anytime to keep it.');
      }
    } catch (e) {
      _autoSaveDone = false; // allow retry on next change
    }
  }

  /// Picks an image file from disk and stores bytes in companyLogoProvider.
  Future<void> _pickLogo() async {
    final input = html.FileUploadInputElement()
      ..accept = 'image/*'
      ..click();
    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) return;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final bytes = reader.result as List<int>;
    ref.read(companyLogoProvider.notifier).state = bytes;
  }

  void _clearLogo() =>
      ref.read(companyLogoProvider.notifier).state = null;

  Future<void> _saveProject() async {
    if (_isSaving) return;
    setState(() { _isSaving = true; _saveSuccess = false; });
    try {
      final state = ref.read(estimatorProvider);
      final id = await FirestoreService.instance.save(state, projectId: _currentProjectId);
      setState(() { _currentProjectId = id; _isSaving = false; _saveSuccess = true; _hasUnsavedChanges = false; _lastSavedState = ref.read(estimatorProvider).hashCode; });
      // Clear success badge after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saveSuccess = false);
      });
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        AppSnackbar.error(context, 'Save failed: \$e');
      }
    }
  }

  Future<void> _openProject() async {
    final id = await showProjectList(context);
    if (id != null) {
      setState(() {
        _currentProjectId   = id;
        _hasUnsavedChanges  = false;
        _lastSavedState     = ref.read(estimatorProvider).hashCode;
      });
    }
  }

  Future<void> _export(String format) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final state  = ref.read(estimatorProvider);
      final bom    = ref.read(bomProvider);
      final rValue = ref.read(rValueResultProvider);
      if (format == 'csv') {
        await ExportService.downloadCsv(state, bom);
      } else {
        final logo = ref.read(companyLogoProvider);
        await ExportService.downloadPdf(state, bom, rValue: rValue, logoBytes: logo);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Export failed: \$e');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 1200;
    final isTablet = screenWidth > 768 && screenWidth <= 1200;

    // Track unsaved changes whenever estimator state changes
    ref.listen(estimatorProvider, (prev, next) {
      if (_lastSavedState != null && next.hashCode != _lastSavedState) {
        if (mounted && !_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
      }
      // Auto-save draft on first meaningful change
      if (prev != next && _currentProjectId == null) {
        _maybeAutosave(next);
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Building tab bar — always visible above the 3-panel layout
          const BuildingTabBar(),
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 1,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.roofing, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Text('ProTPO', style: TextStyle(color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700, fontSize: 20)),
          UnsavedDot(visible: _hasUnsavedChanges && _currentProjectId != null),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4)),
            child: Text('ESTIMATOR', style: TextStyle(color: AppTheme.accent,
                fontWeight: FontWeight.w600, fontSize: 10, letterSpacing: 1)),
          ),
          // ── Company logo (top-center) ──────────────────────────────
          Expanded(child: _buildLogoWidget()),
        ],
      ),
      actions: [
        // Open project
        TextButton.icon(
          onPressed: _openProject,
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('Open'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
        ),
        const SizedBox(width: 4),
        // Save project
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
    );
  }

  Widget _buildLogoWidget() {
    final logoBytes = ref.watch(companyLogoProvider);
    if (logoBytes != null) {
      // Show uploaded logo with remove button
      return Center(
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              height: 36,
              constraints: const BoxConstraints(maxWidth: 160),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(6),
                color: AppTheme.surfaceAlt,
              ),
              child: Image.memory(
                Uint8List.fromList(logoBytes),
                fit: BoxFit.contain,
              ),
            ),
            GestureDetector(
              onTap: _clearLogo,
              child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 10, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
    // No logo — show upload button
    return Center(
      child: TextButton.icon(
        onPressed: _pickLogo,
        icon: const Icon(Icons.upload, size: 16),
        label: const Text('Upload Logo'),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.textSecondary,
          textStyle: const TextStyle(fontSize: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          side: BorderSide(color: AppTheme.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
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
          child: const LeftPanel(),
        ),
        Expanded(
          flex: 3,
          child: Container(
            color: AppTheme.centerPanelBg,
            child: const CenterPanel(),
          ),
        ),
        Container(
          width: 360,
          decoration: BoxDecoration(
            color: AppTheme.rightPanelBg,
            border: Border(left: BorderSide(color: AppTheme.border)),
          ),
          child: const RightPanel(),
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
          child: const LeftPanel(),
        ),
        const Expanded(child: CenterPanel()),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(text: 'Inputs'),
              Tab(text: 'Estimate'),
              Tab(text: 'Summary'),
            ],
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
                              ? Colors.white.withOpacity(0.8)
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
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _confirmDelete(context, index,
                                building.buildingName, notifier),
                            child: Icon(
                              Icons.close,
                              size: 13,
                              color: isActive
                                  ? Colors.white.withOpacity(0.7)
                                  : AppTheme.textMuted,
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
                side: BorderSide(color: AppTheme.primary.withOpacity(0.4)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                minimumSize: const Size(0, 32),
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
