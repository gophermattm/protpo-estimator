# Job Record Phase 5 — Estimates Tab + Load/Save Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Estimates placeholder tab in Job Detail with a working estimates list, wire "Load into estimator" so tapping an estimate hydrates the editor, add a job context ribbon to the estimator AppBar, and reroute the save path so autosave and manual save write to the active estimate doc when a job is loaded.

**Architecture:** The Estimates tab is a new `_EstimatesTab` widget inside `job_detail_screen.dart`. Loading an estimate calls `loadEstimateIntoEditorRef` (from Phase 2) which deserializes the estimate's state into the estimator provider. The estimator screen gains a context ribbon showing `[Customer] > [Job] > [Estimate]` and a dual save path: when `hasActiveEstimateProvider` is true, saves go to the estimate doc via `FirestoreService.updateEstimate`; when false, saves go to the legacy `protpo_projects` path (unchanged). Three new display-name providers in `job_providers.dart` carry the ribbon labels so the ribbon doesn't need to subscribe to Firestore streams.

**Tech Stack:** Flutter 3.35+, Riverpod, cloud_firestore (existing). No new dependencies.

**Internal milestone.** Still reachable only via long-press on Open. Phase 8 performs the cutover.

---

## File Structure

### Files to modify

| Path | Change |
|---|---|
| `lib/providers/job_providers.dart` | Add 3 display-name StateProviders (`activeJobNameProvider`, `activeCustomerNameProvider`, `activeEstimateNameProvider`). Update `loadEstimateIntoEditor` and `loadEstimateIntoEditorRef` to accept and set these names. Update `buildEstimateDraft` to accept a `WidgetRef` variant. |
| `lib/screens/job_detail_screen.dart` | Replace the Estimates `_PlaceholderTab` with a real `_EstimatesTab` widget. Add Load/New/Duplicate/Delete/Rename actions on estimate cards. |
| `lib/screens/estimator_screen.dart` | Add job context ribbon between AppBar and BuildingTabBar. Reroute `_saveProject()` and `_maybeAutosave()` through the active estimate when `hasActiveEstimateProvider` is true. Import `job_providers.dart`. |
| `test/providers/job_providers_test.dart` | Update existing `loadEstimateIntoEditor` tests to pass the new name parameters. |

### Files NOT touched

- `lib/services/firestore_service.dart` — all CRUD methods exist from Phase 1
- `lib/models/*` — all models exist from Phase 1
- `lib/widgets/*` — no widget changes
- `lib/screens/project_list_screen.dart` — old flow untouched

---

## Task 1: Add display-name providers and update load helpers

**Files:**
- Modify: `lib/providers/job_providers.dart`
- Modify: `test/providers/job_providers_test.dart`

The estimator's context ribbon needs to show the active job name, customer name, and estimate name. Rather than subscribing to Firestore streams for display labels, we store them as simple StateProviders that get set alongside the IDs when loading an estimate.

### Step 1.1 — Add the three display-name providers

- [ ] **Edit `lib/providers/job_providers.dart`.** Find the `activeEstimateIdProvider` declaration and add the following three providers directly after it:

```dart
/// Display name for the active job — set when loading an estimate.
/// Used by the estimator context ribbon. Not reactive to Firestore changes
/// (the ribbon shows what was loaded, not live updates to the job name).
final activeJobNameProvider = StateProvider<String>((ref) => '');

/// Display name for the active customer — set when loading an estimate.
final activeCustomerNameProvider = StateProvider<String>((ref) => '');

/// Display name for the active estimate — set when loading an estimate.
final activeEstimateNameProvider = StateProvider<String>((ref) => '');
```

### Step 1.2 — Update loadEstimateIntoEditor to accept and set names

- [ ] **Replace** the existing `loadEstimateIntoEditor` function with:

```dart
bool loadEstimateIntoEditor(
  ProviderContainer container,
  Estimate estimate,
  String jobId, {
  String jobName = '',
  String customerName = '',
}) {
  if (estimate.estimatorState.isEmpty) return false;

  final loaded = stateFromJson(estimate.estimatorState);
  if (loaded == null) return false;

  container.read(estimatorProvider.notifier).loadState(loaded);
  container.read(activeJobIdProvider.notifier).state = jobId;
  container.read(activeEstimateIdProvider.notifier).state = estimate.id;
  container.read(activeJobNameProvider.notifier).state = jobName;
  container.read(activeCustomerNameProvider.notifier).state = customerName;
  container.read(activeEstimateNameProvider.notifier).state = estimate.name;
  return true;
}
```

### Step 1.3 — Update loadEstimateIntoEditorRef similarly

- [ ] **Replace** the existing `loadEstimateIntoEditorRef` function with:

```dart
bool loadEstimateIntoEditorRef(
  dynamic ref,
  Estimate estimate,
  String jobId, {
  String jobName = '',
  String customerName = '',
}) {
  if (estimate.estimatorState.isEmpty) return false;

  final loaded = stateFromJson(estimate.estimatorState);
  if (loaded == null) return false;

  ref.read(estimatorProvider.notifier).loadState(loaded);
  ref.read(activeJobIdProvider.notifier).state = jobId;
  ref.read(activeEstimateIdProvider.notifier).state = estimate.id;
  ref.read(activeJobNameProvider.notifier).state = jobName;
  ref.read(activeCustomerNameProvider.notifier).state = customerName;
  ref.read(activeEstimateNameProvider.notifier).state = estimate.name;
  return true;
}
```

### Step 1.4 — Update restoreLastSession to pass names

- [ ] **Find** the `restoreLastSession` function. Update the `loadEstimateIntoEditor` call at the bottom to pass the names:

Replace:
```dart
  return loadEstimateIntoEditor(container, estimate, session.jobId!);
```

With:
```dart
  return loadEstimateIntoEditor(
    container, estimate, session.jobId!,
    jobName: job.jobName,
    customerName: job.customerName,
  );
```

### Step 1.5 — Update tests to pass new parameters

- [ ] **Edit `test/providers/job_providers_test.dart`.** Find the test `'hydrates estimatorProvider from estimate.estimatorState'`. Update the `loadEstimateIntoEditor` call:

Replace:
```dart
      final result = loadEstimateIntoEditor(container, estimate, 'job-42');
```

With:
```dart
      final result = loadEstimateIntoEditor(container, estimate, 'job-42',
          jobName: 'Warehouse', customerName: 'Acme');
```

Add these assertions after the existing ones:
```dart
      expect(container.read(activeJobNameProvider), 'Warehouse');
      expect(container.read(activeCustomerNameProvider), 'Acme');
      expect(container.read(activeEstimateNameProvider), 'TPO Bid');
```

Also update the import to include the new providers:
```dart
import 'package:protpo_app/providers/job_providers.dart';
```
(This import already exists — just verify the new providers are accessible.)

### Step 1.6 — Run tests

- [ ] **Run:** `flutter test test/providers/job_providers_test.dart`

Expected: All tests pass (the `loadEstimateIntoEditor` test now also verifies name providers are set).

### Step 1.7 — Commit

- [ ] **Run:**

```bash
git add lib/providers/job_providers.dart test/providers/job_providers_test.dart
git commit -m "feat(providers): add display-name providers for job context ribbon

Three new StateProviders (activeJobNameProvider, activeCustomerNameProvider,
activeEstimateNameProvider) carry the ribbon labels. Set alongside the
IDs in loadEstimateIntoEditor/loadEstimateIntoEditorRef — avoids the
need for the ribbon widget to subscribe to Firestore streams.

Updated restoreLastSession to pass names from the loaded job.
Tests updated to verify names are set correctly.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Build the Estimates tab

**Files:**
- Modify: `lib/screens/job_detail_screen.dart`

Replace the Estimates `_PlaceholderTab` with a real `_EstimatesTab` widget that shows the list of estimates for a job with Load/New/Duplicate/Delete/Rename actions.

### Step 2.1 — Replace the Estimates placeholder in the TabBarView

- [ ] **Find** the TabBarView in `_JobDetailBodyState.build()` (around line 112-124). Replace:

```dart
          _PlaceholderTab(
              icon: Icons.description_outlined,
              label: 'Estimates',
              message: 'Estimate management coming in Phase 5'),
```

With:

```dart
          _EstimatesTab(job: job),
```

### Step 2.2 — Add the _EstimatesTab widget

- [ ] **Add the following widget** to `lib/screens/job_detail_screen.dart`, placing it directly BEFORE the `_PlaceholderTab` class (around line 372):

```dart
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
        // Header with count + new estimate button
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
    // Prompt for estimate name
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

      // Set as active estimate on the job
      final updated = job.copyWith(activeEstimateId: estId);
      await FirestoreService.instance.updateJob(updated);

      // Log system activity
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

      // New estimate has empty state — don't try to deserialize via
      // loadEstimateIntoEditorRef (stateFromJson({}) returns null).
      // Just set the active IDs so saves go to the right place.
      // The estimator keeps its current in-memory state.
      ref.read(activeJobIdProvider.notifier).state = job.id;
      ref.read(activeEstimateIdProvider.notifier).state = estId;
      ref.read(activeJobNameProvider.notifier).state = job.jobName;
      ref.read(activeCustomerNameProvider.notifier).state = job.customerName;
      ref.read(activeEstimateNameProvider.notifier).state = name;
      // Persist session for next app launch
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

// ── Estimate card ────────────────────────────────────────────────────────────

class _EstimateCard extends ConsumerWidget {
  final Job job;
  final Estimate estimate;
  final bool isActive;

  const _EstimateCard({
    required this.job,
    required this.estimate,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          // Top row: name + active badge + overflow menu
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
                if (v == 'rename') _rename(context, ref);
                if (v == 'duplicate') _duplicate(context, ref);
                if (v == 'delete') _delete(context, ref);
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

          // Stats row
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

          // Load button
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _loadIntoEstimator(context, ref),
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

  void _loadIntoEstimator(BuildContext context, WidgetRef ref) {
    // Set as the active estimate on the job
    FirestoreService.instance.updateJob(
        job.copyWith(activeEstimateId: estimate.id));

    // Load estimate state into the estimator
    loadEstimateIntoEditorRef(ref, estimate, job.id,
        jobName: job.jobName, customerName: job.customerName);

    // Persist session for next app launch
    FirestoreService.instance.saveLastSession(
        jobId: job.id, estimateId: estimate.id);

    // Pop back to estimator
    Navigator.pop(context);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
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

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
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

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
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
      // If this was the active estimate, clear it
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
```

### Step 2.3 — Add required imports

- [ ] **Verify** the following imports exist at the top of `job_detail_screen.dart`. Add any that are missing:

```dart
import '../models/estimate.dart';
import '../services/firestore_service.dart';
```

The `Estimate` import may already be there via `job_providers.dart` re-export — check and add if needed. `FirestoreService` import is needed for the CRUD calls in the estimate card actions.

### Step 2.4 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/screens/job_detail_screen.dart`

Expected: No errors.

### Step 2.5 — Commit

- [ ] **Run:**

```bash
git add lib/screens/job_detail_screen.dart
git commit -m "feat(ui): build Estimates tab with Load/New/Duplicate/Delete/Rename

Replaces the Estimates placeholder in Job Detail with a real
_EstimatesTab widget. Shows estimate cards with name, area,
building count, last-modified date, and Active badge.

Actions:
- Load into Estimator: calls loadEstimateIntoEditorRef, sets
  job.activeEstimateId, persists session, pops to estimator
- New Estimate: prompts for name, creates empty estimate doc,
  sets as active, loads into estimator
- Rename: inline dialog, updates Firestore
- Duplicate: creates a copy with '(Copy)' suffix
- Delete: confirms, cascades versions, clears activeEstimateId
  if this was the active estimate

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Add context ribbon + reroute save path in estimator screen

**Files:**
- Modify: `lib/screens/estimator_screen.dart`

This is the most important task in Phase 5. It adds the context ribbon and reroutes the save path.

### Step 3.1 — Add import for job_providers

- [ ] **Find** the import block at the top of `lib/screens/estimator_screen.dart`. Add after the existing imports:

```dart
import '../providers/job_providers.dart';
```

### Step 3.2 — Add the context ribbon to the build method

- [ ] **Find** the `build()` method's `Scaffold` body. It contains a `Column` with the `BuildingTabBar` and the 3-panel body (around line 338-345). Add the context ribbon as the first child of the Column:

Find:
```dart
    return Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(isMobile),
      body: Column(
        children: [
          // Hide building tab bar in tight landscape to save vertical space
          if (!isLandscapeTight) const BuildingTabBar(),
```

Replace with:
```dart
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
```

### Step 3.3 — Add the _buildContextRibbon method

- [ ] **Add** this method to the `_EstimatorScreenState` class, placing it after the `_openJobList()` method:

```dart
  Widget _buildContextRibbon(bool isMobile) {
    final hasJob = ref.watch(hasActiveEstimateProvider);
    if (!hasJob) {
      // No job loaded — show a subtle prompt
      return GestureDetector(
        onTap: _openJobList,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: AppTheme.primary.withValues(alpha: 0.04),
          child: Row(children: [
            Icon(Icons.info_outline, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            Text('No job loaded — tap to open a job',
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
          Icon(Icons.chevron_right, size: 16, color: AppTheme.textMuted),
        ]),
      ),
    );
  }
```

### Step 3.4 — Add import for JobDetailScreen

- [ ] **Verify** that `import 'job_detail_screen.dart';` exists. If not, add it alongside the existing `import 'job_list_sheet.dart';`.

### Step 3.5 — Reroute _saveProject to use active estimate when available

- [ ] **Replace** the existing `_saveProject()` method with the following dual-path version:

```dart
  Future<void> _saveProject() async {
    if (_isSaving) return;
    setState(() { _isSaving = true; _saveSuccess = false; });

    final hasActiveEst = ref.read(hasActiveEstimateProvider);

    try {
      if (hasActiveEst) {
        // ── NEW PATH: save to job estimate doc ──
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
      } else {
        // ── LEGACY PATH: save to protpo_projects ──
        final state = ref.read(estimatorProvider);
        final id = await FirestoreService.instance
            .save(state, projectId: _currentProjectId);
        setState(() {
          _currentProjectId = id;
          _isSaving = false;
          _saveSuccess = true;
          _hasUnsavedChanges = false;
          _lastSavedState = ref.read(estimatorProvider).hashCode;
        });
        if (mounted) {
          final name = state.projectInfo.projectName.isNotEmpty
              ? state.projectInfo.projectName
              : 'Untitled Project';
          AppSnackbar.success(context, 'Saved "$name"');
        }
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
```

### Step 3.6 — Reroute _maybeAutosave similarly

- [ ] **Replace** the existing `_maybeAutosave()` method with:

```dart
  Future<void> _maybeAutosave(EstimatorState state) async {
    if (!mounted || _autoSaveDone) return;
    final hasData = state.projectInfo.projectName.isNotEmpty ||
        (state.buildings.isNotEmpty &&
         state.buildings.first.roofGeometry.totalArea > 0);
    if (!hasData) return;

    final hasActiveEst = ref.read(hasActiveEstimateProvider);

    // Skip autosave if no job estimate is loaded AND no legacy project ID
    // exists. This prevents creating orphan protpo_projects docs for new
    // empty states.
    if (!hasActiveEst && _currentProjectId == null) {
      // Legacy autosave behavior: create a new protpo_projects doc
      _autoSaveDone = true;
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
        _autoSaveDone = false;
      }
      return;
    }

    if (hasActiveEst) {
      // Job estimate autosave — write to the estimate doc silently
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
  }
```

### Step 3.7 — Add stateToJson import

- [ ] **Verify** that `import '../services/serialization.dart';` exists in `estimator_screen.dart`. If not, add it. The `stateToJson` function is needed by the new save path.

Check with: `grep "serialization" lib/screens/estimator_screen.dart`

If missing, add: `import '../services/serialization.dart';`

### Step 3.8 — Add Estimate model import

- [ ] **Add** `import '../models/estimate.dart';` to the imports if not already present.

### Step 3.9 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/screens/estimator_screen.dart`

Expected: No new errors.

### Step 3.10 — Verify all tests still pass

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All 63 tests pass.

### Step 3.11 — Commit

- [ ] **Run:**

```bash
git add lib/screens/estimator_screen.dart
git commit -m "feat(ui): add job context ribbon + dual save path in estimator

Context ribbon: slim bar between AppBar and BuildingTabBar showing
[Customer] > [Job] > [Estimate] (draft). Tap navigates to Job Detail.
When no job is loaded, shows 'No job loaded — tap to open'.

Save path: _saveProject() and _maybeAutosave() now check
hasActiveEstimateProvider. When true: serialize state via stateToJson,
build an Estimate draft, write via FirestoreService.updateEstimate.
When false: use legacy protpo_projects save path (unchanged).

This is the critical wiring that makes the job system functional —
estimates loaded via the new Job Detail screen now save correctly.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Final verification and push

**Files:** none modified

### Step 4.1 — Run all tests

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All tests pass.

### Step 4.2 — Run flutter analyze

- [ ] **Run:** `flutter analyze lib/screens/ lib/providers/`

Expected: No new errors.

### Step 4.3 — Push to GitHub

- [ ] **Run:** `git push origin main`

Expected: Push succeeds.

### Step 4.4 — Phase 5 complete checkpoint

Phase 5 is done when all of the following are true:

- [ ] Job Detail > Estimates tab shows a live list of estimates from Firestore
- [ ] "New Estimate" creates an empty estimate, sets it active, loads into estimator
- [ ] "Load into Estimator" hydrates the editor with the estimate's state and pops back
- [ ] "Rename", "Duplicate", "Delete" work on estimate cards
- [ ] The estimator shows a context ribbon: `[Customer] > [Job] > [Estimate] (draft)`
- [ ] Tapping the ribbon navigates to Job Detail
- [ ] Manual Save writes to the estimate doc (not protpo_projects) when a job is loaded
- [ ] Autosave writes to the estimate doc when a job is loaded
- [ ] The old save path still works for projects opened via the legacy Open button
- [ ] All tests pass, no new analyzer errors
- [ ] Pushed to `origin/main`

**This is the minimum viable milestone.** After Phase 5, the new job system is end-to-end functional: create a customer → create a job → create an estimate → edit in the estimator → save → reload. The old project flow still works in parallel.

---

## Notes for the implementing engineer

- **The dual save path is the most critical code in this plan.** Test it carefully: load a job estimate via the new flow, edit something, save manually, reload the page, long-press Open → Job List → Job Detail → Estimates → verify the estimate shows the saved changes.
- **`stateToJson` and `stateFromJson`** are from `lib/services/serialization.dart`. The new save path uses `stateToJson` to serialize the estimator state into the estimate doc, and `loadEstimateIntoEditor` uses `stateFromJson` to deserialize it back.
- **The context ribbon uses `GestureDetector` + `Container`** rather than a Flutter AppBar widget because it sits BETWEEN the AppBar and the body content. It's a simple row with breadcrumb text.
- **`loadEstimateIntoEditorRef` now takes optional named params** (`jobName`, `customerName`). All existing callers use the new signatures — check that the test file is also updated (Task 1 step 1.5).
- **The "Load into Estimator" button calls `FirestoreService.instance.saveLastSession`** to persist the active job/estimate for session restore. This means the next app launch (Phase 8+) will auto-restore to this estimate.
- **New Estimate creates an empty `estimatorState: const {}`**. When loaded into the estimator via `loadEstimateIntoEditorRef`, `stateFromJson({})` returns null, and the function returns false. This is fine — the empty estimate gets a fresh `EstimatorState.initial()` on first save because the estimator's existing state (already in memory) gets serialized into the estimate doc when autosave fires. The "load" is really "set the context IDs so saves go to the right place."

Actually, this is a problem. If `loadEstimateIntoEditorRef` returns false for an empty estimatorState, the active IDs won't be set. Let me fix this.

- **New estimates skip `loadEstimateIntoEditorRef`.** The `_createEstimate` method directly sets the active IDs and name providers because a new estimate has `estimatorState: const {}` which `stateFromJson` can't deserialize. The estimator keeps its current in-memory state and autosave writes it into the new estimate doc on the next edit. This is intentional and already handled in the Task 2 code above.
