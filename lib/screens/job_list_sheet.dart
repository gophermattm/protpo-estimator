// lib/screens/job_list_sheet.dart
//
// Modal bottom sheet listing all jobs. Replaces project_list_screen.dart
// after Phase 8 cutover. Until then, reachable via long-press on Open.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/job.dart';
import '../providers/job_providers.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
// import 'job_detail_screen.dart'; // TODO: uncomment when Task 2 (job_detail_screen.dart) lands

final _dateFmt = DateFormat('MMM d, yyyy');

/// Opens the job list as a modal bottom sheet.
Future<String?> showJobList(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _JobListSheet(),
  );
}

class _JobListSheet extends ConsumerStatefulWidget {
  const _JobListSheet();

  @override
  ConsumerState<_JobListSheet> createState() => _JobListSheetState();
}

enum _JobFilter { all, active, archived }

class _JobListSheetState extends ConsumerState<_JobListSheet> {
  _JobFilter _filter = _JobFilter.active;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(jobsListProvider);
    final screenH = MediaQuery.sizeOf(context).height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenH * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
          child: Row(children: [
            Icon(Icons.work_outline, color: AppTheme.primary, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Jobs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('New Job flow coming in Phase 8')),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Job', style: TextStyle(fontSize: 13)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search jobs or customers...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.border)),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            _filterChip('All', _JobFilter.all),
            const SizedBox(width: 6),
            _filterChip('Active', _JobFilter.active),
            const SizedBox(width: 6),
            _filterChip('Archived', _JobFilter.archived),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: jobsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline, size: 32, color: AppTheme.error),
                const SizedBox(height: 8),
                Text('Failed to load jobs: $e',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ]),
            ),
            data: (jobs) {
              final filtered = _applyFilters(jobs);
              if (filtered.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.work_off_outlined, size: 40, color: AppTheme.textMuted),
                    const SizedBox(height: 8),
                    Text(jobs.isEmpty ? 'No jobs yet' : 'No jobs match your filter',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textMuted)),
                    if (jobs.isEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Tap "+ New Job" to get started.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ]),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (context, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _JobCard(
                  job: filtered[i],
                  onTap: () => _openJobDetail(filtered[i]),
                  onDelete: () => _deleteJob(filtered[i]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  List<Job> _applyFilters(List<Job> jobs) {
    var result = jobs;
    switch (_filter) {
      case _JobFilter.active:
        result = result.where((j) => j.status.isActive).toList();
        break;
      case _JobFilter.archived:
        result = result.where((j) => !j.status.isActive).toList();
        break;
      case _JobFilter.all:
        break;
    }
    if (_search.isNotEmpty) {
      result = result.where((j) {
        return j.jobName.toLowerCase().contains(_search) ||
            j.customerName.toLowerCase().contains(_search) ||
            j.siteAddress.toLowerCase().contains(_search);
      }).toList();
    }
    return result;
  }

  void _openJobDetail(Job job) {
    // TODO: uncomment when job_detail_screen.dart lands (Task 2)
    Navigator.pop(context);
    // Navigator.push(context,
    //   MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: job.id)),
    // );
  }

  Future<void> _deleteJob(Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Job?', style: TextStyle(fontSize: 16)),
        content: Text(
            'Delete "${job.jobName}" and all its estimates, versions, '
            'and activity? This cannot be undone.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
        await FirestoreService.instance.deleteJobCascade(job.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        }
      }
    }
  }

  Widget _filterChip(String label, _JobFilter filter) {
    final selected = _filter == filter;
    return GestureDetector(
      onTap: () => setState(() => _filter = filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.border),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            )),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _JobCard({required this.job, required this.onTap, required this.onDelete});

  static const _statusColors = {
    JobStatus.Lead: Color(0xFF6366F1),
    JobStatus.Quoted: Color(0xFFF59E0B),
    JobStatus.Won: Color(0xFF10B981),
    JobStatus.InProgress: Color(0xFF3B82F6),
    JobStatus.Complete: Color(0xFF6B7280),
    JobStatus.Lost: Color(0xFFEF4444),
  };
  static const _statusLabels = {
    JobStatus.Lead: 'Lead',
    JobStatus.Quoted: 'Quoted',
    JobStatus.Won: 'Won',
    JobStatus.InProgress: 'In Progress',
    JobStatus.Complete: 'Complete',
    JobStatus.Lost: 'Lost',
  };

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[job.status] ?? AppTheme.textMuted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.work_outline, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(job.jobName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(job.customerName, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis),
                if (job.siteAddress.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(job.siteAddress, style: TextStyle(fontSize: 11, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                ],
                if (job.updatedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(_dateFmt.format(job.updatedAt!), style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                ],
              ]),
            ),
            Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_statusLabels[job.status] ?? 'Lead',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
              ),
              const SizedBox(height: 4),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: AppTheme.textMuted),
                onSelected: (v) { if (v == 'delete') onDelete(); },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'delete', child: Row(children: [
                    Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: AppTheme.error)),
                  ])),
                ],
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
