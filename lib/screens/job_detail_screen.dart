/// lib/screens/job_detail_screen.dart
///
/// Full-screen job detail with 3 tabs: Overview, Estimates, Activity.
/// Push-navigated from the Job List Sheet or the estimator context ribbon.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/estimate.dart';
import '../models/estimate_version.dart';
import '../models/job.dart';
import '../models/customer.dart';
import '../models/activity.dart';
import '../providers/job_providers.dart';
import '../providers/estimator_providers.dart';
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(job.customerName,
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
          _EstimatesTab(job: job),
          _ActivityTab(job: job),
        ],
      ),
    );
  }
}

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
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: _statusColors[s], shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text(_statusLabels[s] ?? s.name,
                      style: TextStyle(
                        fontWeight: s == job.status ? FontWeight.w700 : FontWeight.normal,
                      )),
                  if (s == job.status) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check, size: 16, color: _statusColors[s]),
                  ],
                ]),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(_statusLabels[job.status] ?? 'Lead',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
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

      final activity = Activity(
        id: '',
        type: ActivityType.system,
        timestamp: DateTime.now(),
        author: 'system',
        body: 'Status changed from ${_statusLabels[oldStatus]} to ${_statusLabels[newStatus]}',
        systemEventKind: 'status_changed',
        systemEventData: {'from': oldStatus.name, 'to': newStatus.name},
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Customer'),
        const SizedBox(height: 6),
        _card(
          child: customerAsync.when(
            loading: () => const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Error loading customer: $e',
                style: TextStyle(fontSize: 12, color: AppTheme.error)),
            data: (customer) {
              if (customer == null) {
                return Text('Customer not found',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted));
              }
              return _CustomerCard(customer: customer);
            },
          ),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Job Details'),
        const SizedBox(height: 6),
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _detailRow(Icons.work_outline, 'Job Name', job.jobName),
            if (job.siteAddress.isNotEmpty)
              _detailRow(Icons.location_on, 'Site Address', job.siteAddress),
            if (job.siteZip.isNotEmpty)
              _detailRow(Icons.pin_drop, 'Site ZIP', job.siteZip),
            if (job.createdAt != null)
              _detailRow(Icons.calendar_today, 'Created', _dateFmt.format(job.createdAt!)),
            if (job.updatedAt != null)
              _detailRow(Icons.update, 'Last Updated', _dateFmt.format(job.updatedAt!)),
          ]),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Metrics'),
        const SizedBox(height: 6),
        _card(
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _metricBox('Estimates',
              estimatesAsync.when(loading: () => '...', error: (_, __) => '-', data: (est) => '${est.length}'),
              Icons.description_outlined),
            _metricBox('Activities',
              activitiesAsync.when(loading: () => '...', error: (_, __) => '-', data: (act) => '${act.length}'),
              Icons.timeline),
          ]),
        ),
      ]),
    );
  }

  static Widget _sectionLabel(String text) => Text(text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary));

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
          SizedBox(width: 100, child: Text(label,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
          Expanded(child: Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );

  static Widget _metricBox(String label, String value, IconData icon) =>
      Column(children: [
        Icon(icon, size: 20, color: AppTheme.primary),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ]);
}

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
          child: Text(
            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
            style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(customer.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            if (customer.primaryContactName.isNotEmpty)
              Text(customer.primaryContactName,
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ]),
        ),
      ]),
      if (customer.phone.isNotEmpty || customer.email.isNotEmpty) ...[
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 10),
        if (customer.phone.isNotEmpty) _contactRow(Icons.phone, customer.phone),
        if (customer.email.isNotEmpty) _contactRow(Icons.email, customer.email),
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
          Text(value, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// ESTIMATES TAB
// ══════════════════════════════════════════════════════════════════════════════

class _EstimatesTab extends ConsumerWidget {
  final Job job;
  const _EstimatesTab({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estimatesAsync = ref.watch(estimatesForJobProvider(job.id));

    return estimatesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Failed to load estimates: $e',
            style: TextStyle(color: AppTheme.error)),
      ),
      data: (estimates) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Text(
                '${estimates.length} estimate${estimates.length == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _createEstimate(context, ref),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Estimate',
                  style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
              ),
            ),
          ]),
        ),
        Expanded(
          child: estimates.isEmpty
              ? Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Icon(Icons.description_outlined,
                        size: 40, color: AppTheme.textMuted),
                    const SizedBox(height: 8),
                    Text('No estimates yet',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textMuted)),
                    const SizedBox(height: 4),
                    Text('Create your first estimate to start bidding.',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textMuted)),
                  ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: estimates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _EstimateCard(
                    job: job,
                    estimate: estimates[i],
                    isActive: estimates[i].id == job.activeEstimateId,
                  ),
                ),
        ),
      ]),
    );
  }

  Future<void> _createEstimate(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController(text: 'New Estimate');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Estimate', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Estimate Name',
            isDense: true,
            hintText: 'e.g. TPO Bid, PVC Alternate',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (name == null || name.isEmpty) return;

    try {
      final estimate = Estimate(
        id: '',
        name: name,
        estimatorState: const {},
      );
      final estId = await FirestoreService.instance
          .createEstimate(job.id, estimate);

      final updated = job.copyWith(activeEstimateId: estId);
      await FirestoreService.instance.updateJob(updated);

      final activity = Activity(
        id: '',
        type: ActivityType.system,
        timestamp: DateTime.now(),
        author: 'system',
        body: 'Estimate created: $name',
        systemEventKind: 'estimate_created',
        systemEventData: {'estimateId': estId, 'name': name},
      );
      await FirestoreService.instance.createActivity(job.id, activity);

      // New estimate has empty state — don't try to deserialize.
      // Just set the active IDs so saves go to the right place.
      ref.read(activeJobIdProvider.notifier).state = job.id;
      ref.read(activeEstimateIdProvider.notifier).state = estId;
      ref.read(activeJobNameProvider.notifier).state = job.jobName;
      ref.read(activeCustomerNameProvider.notifier).state = job.customerName;
      ref.read(activeEstimateNameProvider.notifier).state = name;
      FirestoreService.instance.saveLastSession(
          jobId: job.id, estimateId: estId);

      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create estimate: $e')),
        );
      }
    }
  }
}

class _EstimateCard extends ConsumerStatefulWidget {
  final Job job;
  final Estimate estimate;
  final bool isActive;

  const _EstimateCard({
    required this.job,
    required this.estimate,
    required this.isActive,
  });

  @override
  ConsumerState<_EstimateCard> createState() => _EstimateCardState();
}

class _EstimateCardState extends ConsumerState<_EstimateCard> {
  bool _showVersions = false;

  Job get job => widget.job;
  Estimate get estimate => widget.estimate;
  bool get isActive => widget.isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppTheme.primary.withValues(alpha: 0.4)
              : AppTheme.border,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Expanded(
              child: Row(children: [
                Icon(Icons.description_outlined,
                    size: 18,
                    color: isActive
                        ? AppTheme.primary
                        : AppTheme.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(estimate.name,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? AppTheme.primary
                              : AppTheme.textPrimary),
                      overflow: TextOverflow.ellipsis),
                ),
                if (isActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Active',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary)),
                  ),
                ],
              ]),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  size: 18, color: AppTheme.textMuted),
              onSelected: (v) {
                if (v == 'rename') _rename();
                if (v == 'duplicate') _duplicate();
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'rename',
                    child: Row(children: [
                      Icon(Icons.edit, size: 16),
                      SizedBox(width: 8),
                      Text('Rename'),
                    ])),
                const PopupMenuItem(
                    value: 'duplicate',
                    child: Row(children: [
                      Icon(Icons.copy, size: 16),
                      SizedBox(width: 8),
                      Text('Duplicate'),
                    ])),
                PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 16, color: AppTheme.error),
                      const SizedBox(width: 8),
                      Text('Delete',
                          style: TextStyle(color: AppTheme.error)),
                    ])),
              ],
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 16, runSpacing: 4, children: [
              if (estimate.totalArea > 0)
                _stat(Icons.crop_square,
                    '${estimate.totalArea.toStringAsFixed(0)} sf'),
              _stat(Icons.business,
                  '${estimate.buildingCount} bldg${estimate.buildingCount != 1 ? "s" : ""}'),
              if (estimate.updatedAt != null)
                _stat(Icons.update,
                    _dateFmt.format(estimate.updatedAt!)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadIntoEstimator,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Load into Estimator'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
          // ── Version history (expandable) ──
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => setState(() => _showVersions = !_showVersions),
              child: Row(children: [
                Icon(
                  _showVersions ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Version History',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textMuted),
                ),
              ]),
            ),
          ),
          if (_showVersions) _buildVersionList(),
        ]),
      ),
    );
  }

  static Widget _stat(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary)),
        ],
      );

  Widget _buildVersionList() {
    final versionsAsync = ref.watch(
        versionsForEstimateProvider(
            (jobId: job.id, estimateId: estimate.id)));

    return versionsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text('Failed to load versions: $e',
            style: TextStyle(fontSize: 11, color: AppTheme.error)),
      ),
      data: (versions) {
        if (versions.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text('No versions saved yet.',
                style: TextStyle(
                    fontSize: 11, color: AppTheme.textMuted)),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            children: versions
                .map((v) => _VersionRow(
                      version: v,
                      job: job,
                      estimate: estimate,
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  void _loadIntoEstimator() {
    FirestoreService.instance.updateJob(
        job.copyWith(activeEstimateId: estimate.id));

    loadEstimateIntoEditorRef(ref, estimate, job.id,
        jobName: job.jobName, customerName: job.customerName);

    FirestoreService.instance.saveLastSession(
        jobId: job.id, estimateId: estimate.id);

    Navigator.pop(context);
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: estimate.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Estimate',
            style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Name', isDense: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    ctrl.dispose();
    if (newName == null || newName.isEmpty || newName == estimate.name) return;

    try {
      final updated = estimate.copyWith(name: newName);
      await FirestoreService.instance
          .updateEstimate(job.id, updated);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rename failed: $e')),
        );
      }
    }
  }

  Future<void> _duplicate() async {
    try {
      final copy = Estimate(
        id: '',
        name: '${estimate.name} (Copy)',
        estimatorState: estimate.estimatorState,
        totalArea: estimate.totalArea,
        totalValue: estimate.totalValue,
        buildingCount: estimate.buildingCount,
      );
      await FirestoreService.instance.createEstimate(job.id, copy);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicate failed: $e')),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Estimate?',
            style: TextStyle(fontSize: 16)),
        content: Text(
            'Delete "${estimate.name}" and all its version history? '
            'This cannot be undone.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirestoreService.instance
          .deleteEstimate(job.id, estimate.id);
      if (estimate.id == job.activeEstimateId) {
        await FirestoreService.instance
            .updateJob(job.copyWith(activeEstimateId: null));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }
}

class _VersionRow extends ConsumerWidget {
  final EstimateVersion version;
  final Job job;
  final Estimate estimate;

  const _VersionRow({
    required this.version,
    required this.job,
    required this.estimate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExport = version.source == VersionSource.export;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        Icon(
          isExport ? Icons.picture_as_pdf : Icons.bookmark_outline,
          size: 14,
          color: isExport
              ? const Color(0xFFEF4444)
              : AppTheme.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(version.label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
            Text(
              '${_dateFmt.format(version.createdAt)}'
              '${version.createdBy.isNotEmpty ? ' by ${version.createdBy}' : ''}',
              style: TextStyle(
                  fontSize: 10, color: AppTheme.textMuted),
            ),
          ]),
        ),
        TextButton(
          onPressed: () => _restore(context, ref),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Restore',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary)),
        ),
      ]),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Version?',
            style: TextStyle(fontSize: 16)),
        content: Text(
          'Restoring "${version.label}" will overwrite your current '
          'draft. This cannot be undone. Continue?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final restored = estimate.copyWith(
        estimatorState: version.estimatorState,
        activeVersionId: version.id,
      );
      await FirestoreService.instance
          .updateEstimate(job.id, restored);

      loadEstimateIntoEditorRef(ref, restored, job.id,
          jobName: job.jobName, customerName: job.customerName);

      FirestoreService.instance.saveLastSession(
          jobId: job.id, estimateId: estimate.id);

      final activity = Activity(
        id: '',
        type: ActivityType.system,
        timestamp: DateTime.now(),
        author: 'system',
        body: 'Restored version: ${version.label}',
        systemEventKind: 'version_restored',
        systemEventData: {
          'versionId': version.id,
          'label': version.label,
        },
      );
      await FirestoreService.instance.createActivity(job.id, activity);

      if (context.mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ACTIVITY TAB
// ══════════════════════════════════════════════════════════════════════════════

class _ActivityTab extends ConsumerWidget {
  final Job job;
  const _ActivityTab({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(activitiesForJobProvider(job.id));

    return Stack(children: [
      activitiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load activities: $e',
              style: TextStyle(color: AppTheme.error)),
        ),
        data: (activities) {
          if (activities.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timeline, size: 40, color: AppTheme.textMuted),
                const SizedBox(height: 8),
                Text('No activity yet',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                Text('Notes, tasks, and calls will appear here.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            itemCount: activities.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _buildActivityCard(context, ref, activities[i]),
          );
        },
      ),
      Positioned(
        right: 16, bottom: 16,
        child: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'note') showDialog(context: context, builder: (_) => _AddNoteDialog(jobId: job.id));
            if (v == 'task') showDialog(context: context, builder: (_) => _AddTaskDialog(jobId: job.id));
            if (v == 'call') showDialog(context: context, builder: (_) => _LogCallDialog(jobId: job.id));
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'note', child: Row(children: [Icon(Icons.note_add, size: 18), SizedBox(width: 10), Text('Add Note')])),
            const PopupMenuItem(value: 'task', child: Row(children: [Icon(Icons.add_task, size: 18), SizedBox(width: 10), Text('Add Task')])),
            const PopupMenuItem(value: 'call', child: Row(children: [Icon(Icons.phone, size: 18), SizedBox(width: 10), Text('Log Call')])),
          ],
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 22),
          ),
        ),
      ),
    ]);
  }

  Widget _buildActivityCard(BuildContext context, WidgetRef ref, Activity activity) {
    switch (activity.type) {
      case ActivityType.note: return _buildNoteCard(context, activity);
      case ActivityType.task: return _buildTaskCard(context, ref, activity);
      case ActivityType.call: return _buildCallCard(context, activity);
      case ActivityType.system: return _buildSystemCard(activity);
    }
  }

  Widget _buildNoteCard(BuildContext context, Activity activity) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.sticky_note_2_outlined, size: 14, color: const Color(0xFF6366F1)),
          const SizedBox(width: 6),
          Text('Note', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF6366F1))),
          const Spacer(),
          Text(_timeAgo(activity.timestamp), style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          const SizedBox(width: 4),
          _deleteButton(context, activity),
        ]),
        const SizedBox(height: 6),
        Text(activity.body, style: const TextStyle(fontSize: 13)),
        if (activity.author.isNotEmpty && activity.author != 'system')
          Padding(padding: const EdgeInsets.only(top: 4),
            child: Text('— ${activity.author}', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: AppTheme.textMuted))),
      ]),
    );
  }

  Widget _buildTaskCard(BuildContext context, WidgetRef ref, Activity activity) {
    final completed = activity.taskCompleted == true;
    final overdue = !completed && activity.taskDueDate != null && activity.taskDueDate!.isBefore(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: overdue ? AppTheme.error.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: overdue ? AppTheme.error.withValues(alpha: 0.3) : AppTheme.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => FirestoreService.instance.updateTaskCompletion(job.id, activity.id, !completed),
          child: Container(
            width: 22, height: 22, margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: completed ? AppTheme.accent.withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: completed ? AppTheme.accent : AppTheme.border, width: 2),
            ),
            child: completed ? Icon(Icons.check, size: 14, color: AppTheme.accent) : null,
          ),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Task', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: overdue ? AppTheme.error : const Color(0xFFF59E0B))),
            const Spacer(),
            if (activity.taskDueDate != null)
              Text('Due ${_dateFmt.format(activity.taskDueDate!)}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: overdue ? AppTheme.error : AppTheme.textMuted)),
            const SizedBox(width: 4),
            _deleteButton(context, activity),
          ]),
          const SizedBox(height: 4),
          Text(activity.body, style: TextStyle(fontSize: 13, decoration: completed ? TextDecoration.lineThrough : null, color: completed ? AppTheme.textMuted : AppTheme.textPrimary)),
          if (completed && activity.taskCompletedAt != null)
            Padding(padding: const EdgeInsets.only(top: 4),
              child: Text('Completed ${_dateFmt.format(activity.taskCompletedAt!)}', style: TextStyle(fontSize: 10, color: AppTheme.accent))),
        ])),
      ]),
    );
  }

  Widget _buildCallCard(BuildContext context, Activity activity) {
    final isIncoming = activity.callDirection == CallDirection.in_;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isIncoming ? Icons.call_received : Icons.call_made, size: 14, color: const Color(0xFF10B981)),
          const SizedBox(width: 6),
          Text(isIncoming ? 'Incoming Call' : 'Outgoing Call', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF10B981))),
          if (activity.callDurationMinutes != null) ...[const SizedBox(width: 8), Text('${activity.callDurationMinutes} min', style: TextStyle(fontSize: 10, color: AppTheme.textMuted))],
          const Spacer(),
          Text(_timeAgo(activity.timestamp), style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          const SizedBox(width: 4),
          _deleteButton(context, activity),
        ]),
        if (activity.body.isNotEmpty) ...[const SizedBox(height: 6), Text(activity.body, style: const TextStyle(fontSize: 13))],
      ]),
    );
  }

  Widget _buildSystemCard(Activity activity) {
    IconData icon;
    switch (activity.systemEventKind) {
      case 'status_changed': icon = Icons.swap_horiz; break;
      case 'version_saved': icon = Icons.bookmark_added; break;
      case 'version_restored': icon = Icons.restore; break;
      case 'export_created': icon = Icons.picture_as_pdf; break;
      case 'job_created': icon = Icons.work; break;
      case 'estimate_created': icon = Icons.description; break;
      default: icon = Icons.info_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Expanded(child: Text(activity.body, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
        Text(_timeAgo(activity.timestamp), style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
      ]),
    );
  }

  Widget _deleteButton(BuildContext context, Activity activity) {
    return GestureDetector(
      onTap: () async {
        final confirmed = await showDialog<bool>(context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete?', style: TextStyle(fontSize: 16)),
            content: const Text('Delete this activity entry?', style: TextStyle(fontSize: 13)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error), child: const Text('Delete')),
            ],
          ),
        );
        if (confirmed == true) await FirestoreService.instance.deleteActivity(job.id, activity.id);
      },
      child: Icon(Icons.close, size: 14, color: AppTheme.textMuted),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _dateFmt.format(dt);
  }
}

// ── Add Note Dialog ──────────────────────────────────────────────────────────

class _AddNoteDialog extends ConsumerStatefulWidget {
  final String jobId;
  const _AddNoteDialog({required this.jobId});
  @override
  ConsumerState<_AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends ConsumerState<_AddNoteDialog> {
  final _bodyCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _bodyCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _saving = true);
    try {
      final profile = ref.read(companyProfileProvider);
      final activity = Activity(id: '', type: ActivityType.note, timestamp: DateTime.now(),
        author: profile.companyName.isNotEmpty ? profile.companyName : 'ProTPO', body: body);
      await FirestoreService.instance.createActivity(widget.jobId, activity);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [Icon(Icons.note_add, size: 20, color: AppTheme.primary), const SizedBox(width: 8), const Text('Add Note', style: TextStyle(fontSize: 16))]),
      content: SizedBox(width: 400, child: TextField(controller: _bodyCtrl, autofocus: true, maxLines: 4,
        decoration: const InputDecoration(labelText: 'Note', isDense: true, hintText: 'Enter your note...', alignLabelWithHint: true))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add, size: 16),
          label: const Text('Add Note')),
      ],
    );
  }
}

// ── Add Task Dialog ──────────────────────────────────────────────────────────

class _AddTaskDialog extends ConsumerStatefulWidget {
  final String jobId;
  const _AddTaskDialog({required this.jobId});
  @override
  ConsumerState<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends ConsumerState<_AddTaskDialog> {
  final _bodyCtrl = TextEditingController();
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void dispose() { _bodyCtrl.dispose(); super.dispose(); }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _saving = true);
    try {
      final profile = ref.read(companyProfileProvider);
      final activity = Activity(id: '', type: ActivityType.task, timestamp: DateTime.now(),
        author: profile.companyName.isNotEmpty ? profile.companyName : 'ProTPO', body: body,
        taskDueDate: _dueDate, taskCompleted: false);
      await FirestoreService.instance.createActivity(widget.jobId, activity);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [Icon(Icons.add_task, size: 20, color: AppTheme.primary), const SizedBox(width: 8), const Text('Add Task', style: TextStyle(fontSize: 16))]),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _bodyCtrl, autofocus: true,
          decoration: const InputDecoration(labelText: 'Task description', isDense: true, hintText: 'e.g. Call adjuster, Send revised estimate')),
        const SizedBox(height: 12),
        GestureDetector(onTap: _pickDueDate, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(Icons.calendar_today, size: 16, color: AppTheme.textMuted), const SizedBox(width: 8),
            Text(_dueDate != null ? 'Due: ${_dateFmt.format(_dueDate!)}' : 'Set due date (optional)',
              style: TextStyle(fontSize: 13, color: _dueDate != null ? AppTheme.textPrimary : AppTheme.textMuted)),
            if (_dueDate != null) ...[const Spacer(), GestureDetector(onTap: () => setState(() => _dueDate = null), child: Icon(Icons.close, size: 14, color: AppTheme.textMuted))],
          ]),
        )),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add, size: 16),
          label: const Text('Add Task')),
      ],
    );
  }
}

// ── Log Call Dialog ──────────────────────────────────────────────────────────

class _LogCallDialog extends ConsumerStatefulWidget {
  final String jobId;
  const _LogCallDialog({required this.jobId});
  @override
  ConsumerState<_LogCallDialog> createState() => _LogCallDialogState();
}

class _LogCallDialogState extends ConsumerState<_LogCallDialog> {
  final _summaryCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  CallDirection _direction = CallDirection.out;
  bool _saving = false;

  @override
  void dispose() { _summaryCtrl.dispose(); _durationCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final profile = ref.read(companyProfileProvider);
      final duration = int.tryParse(_durationCtrl.text.trim());
      final activity = Activity(id: '', type: ActivityType.call, timestamp: DateTime.now(),
        author: profile.companyName.isNotEmpty ? profile.companyName : 'ProTPO',
        body: _summaryCtrl.text.trim(), callDirection: _direction, callDurationMinutes: duration);
      await FirestoreService.instance.createActivity(widget.jobId, activity);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [Icon(Icons.phone, size: 20, color: AppTheme.primary), const SizedBox(width: 8), const Text('Log Call', style: TextStyle(fontSize: 16))]),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('Direction:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)), const SizedBox(width: 12),
          SegmentedButton<CallDirection>(
            segments: const [
              ButtonSegment(value: CallDirection.out, label: Text('Outgoing', style: TextStyle(fontSize: 12)), icon: Icon(Icons.call_made, size: 14)),
              ButtonSegment(value: CallDirection.in_, label: Text('Incoming', style: TextStyle(fontSize: 12)), icon: Icon(Icons.call_received, size: 14)),
            ],
            selected: {_direction}, onSelectionChanged: (s) => setState(() => _direction = s.first),
            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _durationCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Duration (minutes)', isDense: true, hintText: 'Optional', prefixIcon: Icon(Icons.timer, size: 18))),
        const SizedBox(height: 10),
        TextField(controller: _summaryCtrl, maxLines: 3,
          decoration: const InputDecoration(labelText: 'Call summary', isDense: true, hintText: 'What was discussed?', alignLabelWithHint: true)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.phone, size: 16),
          label: const Text('Log Call')),
      ],
    );
  }
}

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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        Text(message, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ]),
    );
  }
}
