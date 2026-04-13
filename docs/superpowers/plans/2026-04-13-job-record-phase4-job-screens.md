# Job Record Phase 4 — Job List Sheet + Job Detail Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the Job List Sheet (modal bottom sheet showing all jobs) and Job Detail Screen (full-screen with Overview tab) as internal-only screens reachable via a debug entry point. The existing project list and Open button are untouched — these screens exist alongside them until Phase 8 performs the cutover.

**Architecture:** Two new screen files following the existing patterns in `lib/screens/`. `JobListSheet` mirrors the structure of `project_list_screen.dart` (modal bottom sheet opened via a static function). `JobDetailScreen` is a full Scaffold with AppBar + TabBar + TabBarView (3 tabs: Overview is built, Estimates and Activity are placeholders). A long-press on the existing Open button in `estimator_screen.dart` serves as the debug entry point.

**Tech Stack:** Flutter 3.35+, Riverpod (flutter_riverpod), cloud_firestore (existing). Uses providers from Phase 2 (`jobsListProvider`, `jobStreamProvider`, `estimatesForJobProvider`, `activitiesForJobProvider`, `customerProvider`). No new dependencies.

**Internal milestone.** The old Open button still works via regular tap. Long-press opens the new Job List. Both screens are fully functional but won't be the primary entry point until Phase 8.

---

## File Structure

### Files to create

| Path | Responsibility |
|---|---|
| `lib/screens/job_list_sheet.dart` | Modal bottom sheet listing all jobs with status chips, filter (All/Active/Archived), search, and "+ New Job" button. Each card opens Job Detail. |
| `lib/screens/job_detail_screen.dart` | Full-screen job detail with 3-tab layout. Overview tab shows customer card, job details, status picker, key metrics. Estimates + Activity tabs are placeholders. |

### Files to modify

| Path | Change |
|---|---|
| `lib/screens/estimator_screen.dart` | Add `onLongPress: _openJobList` to the Open button (both mobile and desktop variants). Add `_openJobList()` method that calls `showJobList(context)`. ~10 lines added. |

### Files NOT touched

- `lib/screens/project_list_screen.dart` — stays as-is, still reachable via normal Open tap
- `lib/providers/*` — all providers already exist from Phase 2
- `lib/services/*` — all CRUD methods already exist from Phase 1
- `lib/widgets/*` — no widget changes

---

## Task 1: Job List Sheet

**Files:**
- Create: `lib/screens/job_list_sheet.dart`

### Step 1.1 — Create the Job List Sheet

- [ ] **Create `lib/screens/job_list_sheet.dart`** with the following content:

```dart
/// lib/screens/job_list_sheet.dart
///
/// Modal bottom sheet listing all jobs. Replaces project_list_screen.dart
/// after Phase 8 cutover. Until then, reachable via long-press on Open.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/job.dart';
import '../providers/job_providers.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'job_detail_screen.dart';

final _dateFmt = DateFormat('MMM d, yyyy');

/// Opens the job list as a modal bottom sheet.
/// Returns the job ID if a job's estimate was loaded, null otherwise.
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
        // Handle
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Title + New Job button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
          child: Row(children: [
            Icon(Icons.work_outline, color: AppTheme.primary, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Jobs',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            // Phase 8 will wire this to the New Job Flow
            TextButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('New Job flow coming in Phase 8')),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Job', style: TextStyle(fontSize: 13)),
            ),
          ]),
        ),

        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search jobs or customers...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.border)),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),

        // Filter chips
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

        // Job list
        Expanded(
          child: jobsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Icon(Icons.error_outline,
                    size: 32, color: AppTheme.error),
                const SizedBox(height: 8),
                Text('Failed to load jobs: $e',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMuted)),
              ]),
            ),
            data: (jobs) {
              final filtered = _applyFilters(jobs);
              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Icon(Icons.work_off_outlined,
                        size: 40, color: AppTheme.textMuted),
                    const SizedBox(height: 8),
                    Text(
                        jobs.isEmpty
                            ? 'No jobs yet'
                            : 'No jobs match your filter',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textMuted)),
                    if (jobs.isEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Tap "+ New Job" to get started.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ]),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _JobCard(
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

    // Status filter
    switch (_filter) {
      case _JobFilter.active:
        result = result.where((j) => j.status.isActive).toList();
        break;
      case _JobFilter.archived:
        result = result
            .where((j) => !j.status.isActive)
            .toList();
        break;
      case _JobFilter.all:
        break;
    }

    // Text search
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
    Navigator.pop(context); // close sheet
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(jobId: job.id),
      ),
    );
  }

  Future<void> _deleteJob(Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:
            const Text('Delete Job?', style: TextStyle(fontSize: 16)),
        content: Text(
            'Delete "${job.jobName}" and all its estimates, versions, '
            'and activity? This cannot be undone.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }

  Widget _filterChip(String label, _JobFilter filter) {
    final selected = _filter == filter;
    return GestureDetector(
      onTap: () => setState(() => _filter = filter),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.3)
                : AppTheme.border,
          ),
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

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _JobCard({
    required this.job,
    required this.onTap,
    required this.onDelete,
  });

  static const _statusColors = {
    JobStatus.Lead: Color(0xFF6366F1),       // Indigo
    JobStatus.Quoted: Color(0xFFF59E0B),     // Amber
    JobStatus.Won: Color(0xFF10B981),        // Green
    JobStatus.InProgress: Color(0xFF3B82F6), // Blue
    JobStatus.Complete: Color(0xFF6B7280),   // Gray
    JobStatus.Lost: Color(0xFFEF4444),       // Red
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
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            // Left: icon
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.work_outline, color: color, size: 20),
            ),
            const SizedBox(width: 12),

            // Center: job info
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(job.jobName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(job.customerName,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis),
                if (job.siteAddress.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(job.siteAddress,
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis),
                ],
                if (job.updatedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(_dateFmt.format(job.updatedAt!),
                      style: TextStyle(
                          fontSize: 10, color: AppTheme.textMuted)),
                ],
              ]),
            ),

            // Right: status chip + overflow menu
            Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusLabels[job.status] ?? 'Lead',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
              ),
              const SizedBox(height: 4),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    size: 18, color: AppTheme.textMuted),
                onSelected: (v) {
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 16, color: AppTheme.error),
                      const SizedBox(width: 8),
                      Text('Delete',
                          style: TextStyle(color: AppTheme.error)),
                    ]),
                  ),
                ],
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
```

### Step 1.2 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/screens/job_list_sheet.dart`

Expected: No errors. May have info-level warnings.

### Step 1.3 — Commit

- [ ] **Run:**

```bash
git add lib/screens/job_list_sheet.dart
git commit -m "feat(ui): add Job List Sheet modal bottom sheet

Lists all jobs with status chips, search by name/customer/address,
and All/Active/Archived filter chips. Each card shows job name,
customer, address, date, and status. Tap opens Job Detail (Phase 4
Task 2). Delete cascades via FirestoreService.deleteJobCascade.

New Job button is a placeholder that shows a snackbar — Phase 8
will wire it to the New Job Flow.

Internal milestone — not yet reachable from the app UI.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Job Detail Screen with Overview tab

**Files:**
- Create: `lib/screens/job_detail_screen.dart`

### Step 2.1 — Create the Job Detail Screen

- [ ] **Create `lib/screens/job_detail_screen.dart`** with the following content:

```dart
/// lib/screens/job_detail_screen.dart
///
/// Full-screen job detail with 3 tabs: Overview, Estimates, Activity.
/// Push-navigated from the Job List Sheet or the estimator context ribbon.
///
/// Phase 4: Overview tab is functional.
/// Phase 5: Estimates tab content.
/// Phase 7: Activity tab content.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/job.dart';
import '../models/customer.dart';
import '../models/activity.dart';
import '../providers/job_providers.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

final _dateFmt = DateFormat('MMM d, yyyy');

class JobDetailScreen extends ConsumerWidget {
  final String jobId;
  const JobDetailScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobStreamProvider(jobId));

    return jobAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text('Failed to load job: $e')),
      ),
      data: (job) {
        if (job == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Not Found')),
            body: const Center(child: Text('This job no longer exists.')),
          );
        }
        return _JobDetailBody(job: job);
      },
    );
  }
}

class _JobDetailBody extends ConsumerStatefulWidget {
  final Job job;
  const _JobDetailBody({required this.job});

  @override
  ConsumerState<_JobDetailBody> createState() => _JobDetailBodyState();
}

class _JobDetailBodyState extends ConsumerState<_JobDetailBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.jobName,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            Text(job.customerName,
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
        actions: [
          _StatusChip(job: job),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.primary,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Estimates'),
            Tab(text: 'Activity'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _OverviewTab(job: job),
          _PlaceholderTab(
              icon: Icons.description_outlined,
              label: 'Estimates',
              message: 'Estimate management coming in Phase 5'),
          _PlaceholderTab(
              icon: Icons.timeline,
              label: 'Activity',
              message: 'Activity timeline coming in Phase 7'),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STATUS CHIP (tappable — opens status picker)
// ══════════════════════════════════════════════════════════════════════════════

class _StatusChip extends ConsumerWidget {
  final Job job;
  const _StatusChip({required this.job});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColors[job.status] ?? AppTheme.textMuted;

    return PopupMenuButton<JobStatus>(
      onSelected: (newStatus) => _changeStatus(context, ref, newStatus),
      itemBuilder: (_) => JobStatus.values
          .map((s) => PopupMenuItem(
                value: s,
                child: Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _statusColors[s],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(_statusLabels[s] ?? s.name,
                      style: TextStyle(
                        fontWeight: s == job.status
                            ? FontWeight.w700
                            : FontWeight.normal,
                      )),
                  if (s == job.status) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check, size: 16, color: _statusColors[s]),
                  ],
                ]),
              ))
          .toList(),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(_statusLabels[job.status] ?? 'Lead',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
          Icon(Icons.arrow_drop_down, size: 16, color: color),
        ]),
      ),
    );
  }

  Future<void> _changeStatus(
      BuildContext context, WidgetRef ref, JobStatus newStatus) async {
    if (newStatus == job.status) return;

    final oldStatus = job.status;
    final updated = job.copyWith(status: newStatus);
    try {
      await FirestoreService.instance.updateJob(updated);

      // Log system activity
      final activity = Activity(
        id: '',
        type: ActivityType.system,
        timestamp: DateTime.now(),
        author: 'system',
        body:
            'Status changed from ${_statusLabels[oldStatus]} to ${_statusLabels[newStatus]}',
        systemEventKind: 'status_changed',
        systemEventData: {
          'from': oldStatus.name,
          'to': newStatus.name,
        },
      );
      await FirestoreService.instance.createActivity(job.id, activity);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status update failed: $e')),
        );
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OVERVIEW TAB
// ══════════════════════════════════════════════════════════════════════════════

class _OverviewTab extends ConsumerWidget {
  final Job job;
  const _OverviewTab({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerProvider(job.customerId));
    final estimatesAsync = ref.watch(estimatesForJobProvider(job.id));
    final activitiesAsync = ref.watch(activitiesForJobProvider(job.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        // ── Customer card ────────────────────────────────────────
        _sectionLabel('Customer'),
        const SizedBox(height: 6),
        _card(
          child: customerAsync.when(
            loading: () => const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Error loading customer: $e',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.error)),
            data: (customer) {
              if (customer == null) {
                return Text('Customer not found',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMuted));
              }
              return _CustomerCard(customer: customer);
            },
          ),
        ),

        const SizedBox(height: 16),

        // ── Job details card ─────────────────────────────────────
        _sectionLabel('Job Details'),
        const SizedBox(height: 6),
        _card(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _detailRow(Icons.work_outline, 'Job Name', job.jobName),
            if (job.siteAddress.isNotEmpty)
              _detailRow(
                  Icons.location_on, 'Site Address', job.siteAddress),
            if (job.siteZip.isNotEmpty)
              _detailRow(Icons.pin_drop, 'Site ZIP', job.siteZip),
            if (job.createdAt != null)
              _detailRow(Icons.calendar_today, 'Created',
                  _dateFmt.format(job.createdAt!)),
            if (job.updatedAt != null)
              _detailRow(Icons.update, 'Last Updated',
                  _dateFmt.format(job.updatedAt!)),
          ]),
        ),

        const SizedBox(height: 16),

        // ── Key metrics card ─────────────────────────────────────
        _sectionLabel('Metrics'),
        const SizedBox(height: 6),
        _card(
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
            _metricBox(
              'Estimates',
              estimatesAsync.when(
                loading: () => '...',
                error: (_, __) => '-',
                data: (est) => '${est.length}',
              ),
              Icons.description_outlined,
            ),
            _metricBox(
              'Activities',
              activitiesAsync.when(
                loading: () => '...',
                error: (_, __) => '-',
                data: (act) => '${act.length}',
              ),
              Icons.timeline,
            ),
          ]),
        ),
      ]),
    );
  }

  static Widget _sectionLabel(String text) => Text(text,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary));

  static Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: child,
      );

  static Widget _detailRow(IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ]),
      );

  static Widget _metricBox(
          String label, String value, IconData icon) =>
      Column(children: [
        Icon(icon, size: 20, color: AppTheme.primary),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700)),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: AppTheme.textMuted)),
      ]);
}

// ── Customer detail inside overview ──────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
          child: Text(
            customer.name.isNotEmpty
                ? customer.name[0].toUpperCase()
                : '?',
            style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(customer.name,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            if (customer.primaryContactName.isNotEmpty)
              Text(customer.primaryContactName,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary)),
          ]),
        ),
      ]),
      if (customer.phone.isNotEmpty || customer.email.isNotEmpty) ...[
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 10),
        if (customer.phone.isNotEmpty)
          _contactRow(Icons.phone, customer.phone),
        if (customer.email.isNotEmpty)
          _contactRow(Icons.email, customer.email),
        if (customer.mailingAddress.isNotEmpty)
          _contactRow(Icons.location_on, customer.mailingAddress),
      ],
    ]);
  }

  Widget _contactRow(IconData icon, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 14, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// PLACEHOLDER TAB (for Estimates and Activity until Phases 5 and 7)
// ══════════════════════════════════════════════════════════════════════════════

class _PlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final String message;

  const _PlaceholderTab({
    required this.icon,
    required this.label,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: AppTheme.textMuted),
        const SizedBox(height: 12),
        Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        Text(message,
            style: TextStyle(
                fontSize: 12, color: AppTheme.textMuted)),
      ]),
    );
  }
}
```

### Step 2.2 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/screens/job_detail_screen.dart`

Expected: No errors.

### Step 2.3 — Commit

- [ ] **Run:**

```bash
git add lib/screens/job_detail_screen.dart
git commit -m "feat(ui): add Job Detail Screen with Overview tab

Full-screen job detail pushed from Job List Sheet. AppBar shows job
name, customer subtitle, and a tappable status chip that opens a
picker and auto-logs a system activity on status change.

Three tabs: Overview (functional), Estimates (placeholder), Activity
(placeholder). Overview shows customer card with contact info, job
details (name/address/zip/dates), and metrics (estimate count,
activity count).

Internal milestone — Phase 5 fills Estimates, Phase 7 fills Activity.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Debug entry point (long-press on Open button)

**Files:**
- Modify: `lib/screens/estimator_screen.dart`

### Step 3.1 — Add import and method

- [ ] **Edit `lib/screens/estimator_screen.dart`.** Find the existing imports and add:

```dart
import 'job_list_sheet.dart';
```

Find the existing `_openProject` method (around line 131):

```dart
  Future<void> _openProject() async {
```

Add the following method **directly after** `_openProject`:

```dart
  Future<void> _openJobList() async {
    await showJobList(context);
  }
```

### Step 3.2 — Add long-press to the Open button (mobile)

- [ ] **Find** the mobile Open button (around line 415-420). It looks like:

```dart
          IconButton(
            onPressed: _openProject,
            icon: const Icon(Icons.folder_open, size: 20),
            color: AppTheme.textSecondary,
            tooltip: 'Open Project',
          ),
```

**Replace** it with a `GestureDetector` wrapping the `IconButton` to add long-press:

```dart
          GestureDetector(
            onLongPress: _openJobList,
            child: IconButton(
              onPressed: _openProject,
              icon: const Icon(Icons.folder_open, size: 20),
              color: AppTheme.textSecondary,
              tooltip: 'Open Project (long-press for Jobs)',
            ),
          ),
```

### Step 3.3 — Add long-press to the Open button (desktop/tablet)

- [ ] **Find** the desktop Open button (around line 460-464). It looks like:

```dart
          TextButton.icon(
            onPressed: _openProject,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Open'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
          ),
```

**Replace** it with a `GestureDetector` wrapping:

```dart
          GestureDetector(
            onLongPress: _openJobList,
            child: TextButton.icon(
              onPressed: _openProject,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Open'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            ),
          ),
```

### Step 3.4 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/screens/estimator_screen.dart`

Expected: No new errors (pre-existing warnings are OK).

### Step 3.5 — Verify existing tests still pass

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All 63 tests pass.

### Step 3.6 — Commit

- [ ] **Run:**

```bash
git add lib/screens/estimator_screen.dart
git commit -m "feat(ui): add debug entry point to Job List via long-press on Open

Long-pressing the Open button (both mobile and desktop) now opens the
new Job List Sheet instead of the legacy Project List. Regular tap
still opens the old Project List — no user-facing change.

This is a temporary debug entry point for testing Phase 4 screens.
Phase 8 will replace the regular tap handler and remove this
long-press workaround.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Final verification and push

**Files:** none modified

### Step 4.1 — Run all tests

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All 63 tests pass.

### Step 4.2 — Run flutter analyze

- [ ] **Run:** `flutter analyze lib/screens/`

Expected: No new errors from the 3 new/modified screen files.

### Step 4.3 — Push to GitHub

- [ ] **Run:** `git push origin main`

Expected: Push succeeds with 3 new commits.

### Step 4.4 — Phase 4 complete checkpoint

Phase 4 is done when all of the following are true:

- [ ] `lib/screens/job_list_sheet.dart` exists with `showJobList(context)` entry point
- [ ] `lib/screens/job_detail_screen.dart` exists with Overview tab functional, Estimates + Activity placeholder
- [ ] Long-pressing the Open button opens the Job List Sheet
- [ ] Regular tap on Open still opens the old Project List
- [ ] Status chip in Job Detail changes status and logs a system activity
- [ ] Customer card in Overview tab shows contact info from Firestore
- [ ] Metrics card shows estimate count and activity count
- [ ] All 63 existing tests pass
- [ ] No new analyzer errors
- [ ] Pushed to `origin/main`

---

## Notes for the implementing engineer

- **The Job List Sheet's "+ New Job" button is a placeholder.** It shows a snackbar saying "coming in Phase 8". Do NOT implement the new-job flow here.
- **The Estimates and Activity tabs are `_PlaceholderTab` widgets.** They show a centered icon + message. Phase 5 and Phase 7 will replace these with real content. Do NOT build any estimate or activity content here.
- **The status chip writes to Firestore immediately** via `FirestoreService.instance.updateJob`. It also creates a system Activity via `createActivity` to log the status change. The Activity uses `id: ''` which means the FirestoreService will generate a UUID for it.
- **The long-press debug entry point is intentionally hidden.** No UI indicates that long-press does anything. It's a power-user testing path until Phase 8 replaces the Open button entirely.
- **`jobStreamProvider` (not `jobProvider`)** is used in `job_detail_screen.dart` for the live-updating job stream. Check `lib/providers/job_providers.dart` — the provider was named `jobStreamProvider` (not `jobProvider`) in Phase 2 Task 2.
- **All screens use `ConsumerWidget` or `ConsumerStatefulWidget`** to access Riverpod providers, matching the existing pattern in the codebase.
