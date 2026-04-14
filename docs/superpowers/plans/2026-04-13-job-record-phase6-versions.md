# Job Record Phase 6 — Versions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add version management: manual save-as-version in the estimator, auto-snapshot before every PDF export, expandable version history on each estimate card, and restore-from-version with confirmation dialog.

**Architecture:** Two files change. `estimator_screen.dart` gains a "Save as version" button in the context ribbon and an auto-snapshot call injected into the `_export()` method just before the PDF is generated. `job_detail_screen.dart`'s `_EstimateCard` gains an expandable version list (using `versionsForEstimateProvider` from Phase 2) with "Restore" buttons. All version CRUD uses `FirestoreService.createVersion/listVersions` from Phase 1 and the `EstimateVersion` model.

**Tech Stack:** Flutter 3.35+, Riverpod, cloud_firestore (existing). No new dependencies. No new files — only modifications.

**Internal milestone.** Still reachable via long-press on Open. Phase 8 performs the cutover.

---

## File Structure

### Files to modify

| Path | Change |
|---|---|
| `lib/screens/estimator_screen.dart` | Add "Save as version" button to context ribbon. Add auto-snapshot call in `_export()` before PDF download. Add `_saveVersion()` helper method. |
| `lib/screens/job_detail_screen.dart` | Convert `_EstimateCard` to `ConsumerStatefulWidget` to manage expand/collapse state. Add version list section with "Restore" action. Add `_VersionRow` widget. |

### Files NOT touched

- `lib/providers/job_providers.dart` — `versionsForEstimateProvider` already exists
- `lib/services/firestore_service.dart` — `createVersion`/`listVersions` already exist
- `lib/models/estimate_version.dart` — model already exists
- `lib/services/export_service.dart` — export logic untouched; the snapshot is taken in the caller

---

## Task 1: Save-as-version button + auto-snapshot on export

**Files:**
- Modify: `lib/screens/estimator_screen.dart`

### Step 1.1 — Add the _saveVersion helper method

- [ ] **Add** the following method to `_EstimatorScreenState`, placing it after the `_buildContextRibbon()` method:

```dart
  /// Creates a frozen version snapshot of the current estimate state.
  /// Called manually (via button) or automatically (before PDF export).
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

      // Update the estimate's activeVersionId pointer
      final currentEst = await FirestoreService.instance
          .getEstimate(jobId, estId);
      if (currentEst != null) {
        await FirestoreService.instance.updateEstimate(
          jobId,
          currentEst.copyWith(activeVersionId: versionId),
        );
      }

      // Log system activity
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

  /// Shows a dialog prompting for a version label, then saves.
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
    if (label == null) return; // cancelled

    await _saveVersion(source: 'manual', label: label);
  }
```

### Step 1.2 — Add imports for EstimateVersion and DateFormat

- [ ] **Verify** these imports exist at the top of `estimator_screen.dart`. Add any that are missing:

```dart
import 'package:intl/intl.dart';
import '../models/estimate_version.dart';
import '../models/activity.dart';
```

Note: `intl` is already used by `export_service.dart` and other files. `DateFormat` is the class needed. If `intl` import already exists, skip it.

### Step 1.3 — Add "Save as version" button to the context ribbon

- [ ] **Find** the `_buildContextRibbon()` method. In the "has job" branch, find the `Row` that ends with the chevron icon:

```dart
          Icon(Icons.chevron_right, size: 16, color: AppTheme.textMuted),
```

**Replace** that line with a "Save as version" button followed by the chevron:

```dart
          // Save as version button
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
```

### Step 1.4 — Add auto-snapshot before PDF export

- [ ] **Find** the `_export()` method. In the PDF branch, find the line where `ExportService.downloadPdf` is called (around line 361). **Add** the auto-snapshot call BEFORE the `downloadPdf` call:

Find this block:
```dart
    setState(() => _isExporting = true);
    try {
      final state = ref.read(estimatorProvider);
```

**Replace** with:
```dart
    setState(() => _isExporting = true);
    try {
      // Auto-snapshot version before export (if a job estimate is active)
      if (ref.read(hasActiveEstimateProvider)) {
        await _saveVersion(source: 'export');
      }

      final state = ref.read(estimatorProvider);
```

### Step 1.5 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/screens/estimator_screen.dart`

Expected: No new errors.

### Step 1.6 — Verify tests still pass

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All 63 tests pass.

### Step 1.7 — Commit

- [ ] **Run:**

```bash
git add lib/screens/estimator_screen.dart
git commit -m "feat(versions): add save-as-version button + auto-snapshot on export

Context ribbon gains a 'Version' button that prompts for a label and
saves a frozen EstimateVersion snapshot. Default label for manual:
'Manual snapshot YYYY-MM-DD HH:MM'. Empty label uses the default.

PDF export now auto-snapshots the estimate state before generating
the PDF (when a job estimate is active). Label: 'Export YYYY-MM-DD
HH:MM'. Source: 'export'. This provides a paper trail of every PDF
sent to a customer.

Both paths log a 'version_saved' system activity and update the
estimate's activeVersionId pointer.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Version list + restore in estimate cards

**Files:**
- Modify: `lib/screens/job_detail_screen.dart`

The `_EstimateCard` is currently a `ConsumerWidget`. It needs to become a `ConsumerStatefulWidget` to manage the expand/collapse state of the version list.

### Step 2.1 — Convert _EstimateCard to ConsumerStatefulWidget

- [ ] **Find** the `_EstimateCard` class declaration. Replace:

```dart
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
```

With:

```dart
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
```

Also update all references from `ref` to the implicit `ref` from ConsumerState (no change needed — ConsumerState provides `ref` automatically). Remove the `WidgetRef ref` parameter from the `build` method signature since ConsumerState provides it.

### Step 2.2 — Add the version list section to the card's Column

- [ ] **Find** the "Load button" section at the bottom of the card's Column children (the `Padding` containing the `ElevatedButton.icon` for "Load into Estimator"). **After** that Padding, add the version list section:

```dart
          // ── Version history (expandable) ──
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => setState(() => _showVersions = !_showVersions),
              child: Row(children: [
                Icon(
                  _showVersions
                      ? Icons.expand_less
                      : Icons.expand_more,
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
```

### Step 2.3 — Add the _buildVersionList method

- [ ] **Add** this method to `_EstimateCardState`:

```dart
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
```

### Step 2.4 — Update method signatures for ConsumerStatefulWidget

- [ ] **Update** all the action methods (`_loadIntoEstimator`, `_rename`, `_duplicate`, `_delete`) to remove the `WidgetRef ref` parameter (since ConsumerState provides `ref` implicitly) and replace `BuildContext context` with just using `context` from the state.

For each method, the signature changes from:
```dart
  void _loadIntoEstimator(BuildContext context, WidgetRef ref) {
```
To:
```dart
  void _loadIntoEstimator() {
```

And update all call sites in `build()` from:
```dart
                onPressed: () => _loadIntoEstimator(context, ref),
```
To:
```dart
                onPressed: _loadIntoEstimator,
```

Do this for ALL four methods: `_loadIntoEstimator`, `_rename`, `_duplicate`, `_delete`.

Also update the popup menu callback from:
```dart
              onSelected: (v) {
                if (v == 'rename') _rename(context, ref);
                if (v == 'duplicate') _duplicate(context, ref);
                if (v == 'delete') _delete(context, ref);
              },
```
To:
```dart
              onSelected: (v) {
                if (v == 'rename') _rename();
                if (v == 'duplicate') _duplicate();
                if (v == 'delete') _delete();
              },
```

### Step 2.5 — Add the _VersionRow widget

- [ ] **Add** this widget AFTER the `_EstimateCardState` class (before `_PlaceholderTab`):

```dart
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
      // Copy the version's frozen state into the estimate's mutable draft
      final restored = estimate.copyWith(
        estimatorState: version.estimatorState,
        activeVersionId: version.id,
      );
      await FirestoreService.instance
          .updateEstimate(job.id, restored);

      // Load the restored state into the estimator
      loadEstimateIntoEditorRef(ref, restored, job.id,
          jobName: job.jobName, customerName: job.customerName);

      // Persist session
      FirestoreService.instance.saveLastSession(
          jobId: job.id, estimateId: estimate.id);

      // Log system activity
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
        Navigator.pop(context); // pop Job Detail → back to estimator
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
```

### Step 2.6 — Add EstimateVersion import

- [ ] **Verify** `import '../models/estimate_version.dart';` exists at the top of `job_detail_screen.dart`. Add if missing.

### Step 2.7 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/screens/job_detail_screen.dart`

Expected: No new errors.

### Step 2.8 — Verify tests still pass

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All 63 tests pass.

### Step 2.9 — Commit

- [ ] **Run:**

```bash
git add lib/screens/job_detail_screen.dart
git commit -m "feat(versions): add version history list + restore in estimate cards

_EstimateCard converted to ConsumerStatefulWidget to manage expand/
collapse state. Expandable 'Version History' section shows frozen
snapshots from versionsForEstimateProvider.

Each version row shows: icon (PDF for export, bookmark for manual),
label, date, created-by, and a 'Restore' button.

Restore action:
1. Confirmation dialog ('will overwrite your current draft')
2. Copies version.estimatorState into estimate.estimatorState
3. Updates estimate.activeVersionId to this version
4. Loads restored state into the estimator
5. Logs 'version_restored' system activity
6. Pops to estimator screen

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Final verification and push

**Files:** none modified

### Step 3.1 — Run all tests

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All 63 tests pass.

### Step 3.2 — Run flutter analyze

- [ ] **Run:** `flutter analyze lib/screens/`

Expected: No new errors.

### Step 3.3 — Push to GitHub

- [ ] **Run:** `git push origin main`

Expected: Push succeeds.

### Step 3.4 — Phase 6 complete checkpoint

Phase 6 is done when all of the following are true:

- [ ] Estimator context ribbon shows a "Version" button (green accent)
- [ ] Tapping "Version" prompts for a label and saves a frozen snapshot
- [ ] PDF export auto-snapshots the estimate state before generating (when a job is active)
- [ ] Estimate cards in Job Detail have an expandable "Version History" section
- [ ] Each version row shows label, date, source icon, and "Restore" button
- [ ] Restore overwrites the mutable draft with the version's frozen state, with confirmation
- [ ] System activities are logged for both save and restore
- [ ] All 63 tests pass, no new analyzer errors
- [ ] Pushed to `origin/main`

---

## Notes for the implementing engineer

- **The auto-snapshot fires BEFORE the PDF is generated**, not after. This ensures the version captures exactly the state that went into the PDF. If the PDF generation fails, the version still exists — acceptable tradeoff (better to have a spurious version than to lose the record of what was sent).
- **`_saveVersion` uses `stateToJson` to serialize** the current estimator state, same as the save path in Phase 5. The frozen snapshot is identical in structure to the mutable draft.
- **`versionsForEstimateProvider` is a `FutureProvider`** (not a stream). It loads on first watch and caches. To refresh after saving a new version, the estimate card's expand toggle re-watches the provider. If the list is stale, the user can collapse/expand to force a reload. Phase 9 may improve this to a stream if needed.
- **The `_EstimateCard` conversion from `ConsumerWidget` to `ConsumerStatefulWidget`** is the trickiest part of Task 2. All action methods (`_loadIntoEstimator`, `_rename`, `_duplicate`, `_delete`) must have their `BuildContext context, WidgetRef ref` parameters removed — `context` and `ref` come from the `ConsumerState` base class instead. The call sites in `build()` must be updated accordingly (no more `(context, ref)` arguments).
- **The `_VersionRow` restore action calls `loadEstimateIntoEditorRef`** with the restored estimate (which has the version's state). This re-hydrates the estimator and sets the active IDs, then pops to the estimator screen.
- **Version labels**: manual save prompts for a label with a default of `Manual snapshot YYYY-MM-DD HH:MM` if the user leaves it blank. Export auto-snapshots use `Export YYYY-MM-DD HH:MM`. Both include the timestamp for chronological clarity.
