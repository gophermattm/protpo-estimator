/// lib/screens/project_list_screen.dart
///
/// Bottom sheet that shows all saved projects.
/// Opens from the AppBar "Open" button in EstimatorScreen.
///
/// Shows: project name, customer, address, date saved, total area, building count.
/// Actions: Load, Duplicate, Delete.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../providers/estimator_providers.dart';

/// Opens the project list as a modal bottom sheet.
/// Returns the loaded project ID if a project was opened, null otherwise.
Future<String?> showProjectList(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ProjectListSheet(),
  );
}

class _ProjectListSheet extends ConsumerStatefulWidget {
  const _ProjectListSheet();

  @override
  ConsumerState<_ProjectListSheet> createState() => _ProjectListSheetState();
}

class _ProjectListSheetState extends ConsumerState<_ProjectListSheet> {
  List<ProjectSummary>? _projects;
  bool    _loading      = true;
  String? _error;
  String? _actionId;    // ID of project currently being acted on

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final projects = await FirestoreService.instance.listProjects();
      if (mounted) setState(() { _projects = projects; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _openProject(ProjectSummary summary) async {
    setState(() => _actionId = summary.projectId);
    try {
      final state = await FirestoreService.instance.load(summary.projectId);
      if (state == null) {
        _showSnack('Could not load project — data may be corrupted.');
        setState(() => _actionId = null);
        return;
      }
      ref.read(estimatorProvider.notifier).loadState(state);
      if (mounted) Navigator.of(context).pop(summary.projectId);
    } catch (e) {
      _showSnack('Error loading project: $e');
      setState(() => _actionId = null);
    }
  }

  Future<void> _duplicateProject(ProjectSummary summary) async {
    setState(() => _actionId = summary.projectId);
    try {
      await FirestoreService.instance.duplicate(summary.projectId);
      await _load();
    } catch (e) {
      _showSnack('Error duplicating: $e');
    } finally {
      if (mounted) setState(() => _actionId = null);
    }
  }

  Future<void> _deleteProject(ProjectSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: Text('Delete "${summary.projectName}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionId = summary.projectId);
    try {
      await FirestoreService.instance.delete(summary.projectId);
      await _load();
    } catch (e) {
      _showSnack('Error deleting: $e');
    } finally {
      if (mounted) setState(() => _actionId = null);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
        ),

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Row(children: [
            Icon(Icons.folder_open, color: AppTheme.primary, size: 22),
            const SizedBox(width: 10),
            Text('Saved Projects',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const Spacer(),
            IconButton(
              onPressed: _load,
              icon: Icon(Icons.refresh, color: AppTheme.textSecondary, size: 20),
              tooltip: 'Refresh',
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close, color: AppTheme.textSecondary),
            ),
          ]),
        ),
        Divider(height: 1, color: AppTheme.border),

        // Body
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off, size: 48, color: AppTheme.textMuted),
        const SizedBox(height: 12),
        Text('Could not load projects', style: TextStyle(color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        TextButton(onPressed: _load, child: const Text('Try again')),
      ]));
    }
    if (_projects == null || _projects!.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.description_outlined, size: 48, color: AppTheme.textMuted),
        const SizedBox(height: 12),
        Text('No saved projects yet',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        Text('Use Save in the app bar to save your current project.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            textAlign: TextAlign.center),
      ]));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _projects!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ProjectCard(
        summary:    _projects![i],
        isActing:   _actionId == _projects![i].projectId,
        onOpen:      () => _openProject(_projects![i]),
        onDuplicate: () => _duplicateProject(_projects![i]),
        onDelete:    () => _deleteProject(_projects![i]),
      ),
    );
  }
}

// ─── PROJECT CARD ─────────────────────────────────────────────────────────────

class _ProjectCard extends StatelessWidget {
  final ProjectSummary summary;
  final bool           isActing;
  final VoidCallback   onOpen;
  final VoidCallback   onDuplicate;
  final VoidCallback   onDelete;

  static final _dateFmt = DateFormat('MMM d, yyyy');

  const _ProjectCard({
    required this.summary,
    required this.isActing,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha:0.03),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Top row — name + actions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha:0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.roofing, color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(summary.projectName,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis),
              if (summary.customerName.isNotEmpty)
                Text(summary.customerName,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis),
              if (summary.address.isNotEmpty)
                Text(summary.address,
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis),
            ])),
            if (isActing)
              const Padding(
                padding: EdgeInsets.only(top: 4, right: 8),
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
                onSelected: (v) {
                  if (v == 'duplicate') onDuplicate();
                  if (v == 'delete')    onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'duplicate',
                      child: Row(children: [
                        Icon(Icons.copy, size: 16), SizedBox(width: 10), Text('Duplicate'),
                      ])),
                  PopupMenuItem(value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
                        const SizedBox(width: 10),
                        Text('Delete', style: TextStyle(color: AppTheme.error)),
                      ])),
                ],
              ),
          ]),
        ),

        // Stats row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Wrap(spacing: 12, runSpacing: 6, children: [
            _chip(Icons.crop_square,
                summary.totalArea > 0
                    ? '${summary.totalArea.toStringAsFixed(0)} sf' : 'No area'),
            _chip(Icons.business,
                '${summary.buildingCount} building${summary.buildingCount != 1 ? "s" : ""}'),
            _chip(Icons.calendar_today, _dateFmt.format(summary.savedAt)),
          ]),
        ),

        // Open button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isActing ? null : onOpen,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Open Project'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _chip(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: AppTheme.textMuted),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
    ],
  );
}
