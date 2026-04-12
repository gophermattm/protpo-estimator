# Job Record Phase 2 — State Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Riverpod providers and helper functions for the job record data layer so that later phases (UI) can read/write customers, jobs, estimates, versions, and activities through reactive state. Also add session persistence (last-opened job/estimate IDs survive app reloads).

**Architecture:** A new `lib/providers/job_providers.dart` file holds all job-record-related providers and helper functions, keeping the already-large `estimator_providers.dart` (1524 lines) untouched. Stream providers delegate to `FirestoreService` methods created in Phase 1. Pure helper functions (`loadEstimateIntoEditor`, `saveEstimateDraft`) bridge between the job/estimate model layer and the existing `estimatorProvider`. Session persistence uses the existing `protpo_settings` Firestore collection.

**Tech Stack:** Dart 3.x, Flutter 3.35+, Riverpod (flutter_riverpod — already installed), cloud_firestore (existing). No new dependencies.

**No user-visible changes.** The existing estimator screen, save/load flow, and project list screen remain untouched. The new providers are inert until Phase 4+ UI code calls them. The existing save path (`protpo_projects/{id}`) continues to work as-is.

---

## File Structure

### Files to create

| Path | Responsibility |
|---|---|
| `lib/providers/job_providers.dart` | All job-record Riverpod providers: state providers for active job/estimate IDs, stream providers for Firestore collections, and pure helper functions for loading/saving estimates through the estimator provider |
| `test/providers/job_providers_test.dart` | Tests for the pure helper functions and state providers. Stream providers are NOT tested (thin Firestore wrappers). |

### Files to modify

| Path | Change |
|---|---|
| `lib/services/firestore_service.dart` | Add `saveLastSession(jobId, estimateId)` and `loadLastSession()` methods that persist the last-opened job/estimate IDs to `protpo_settings/last_session` |

### Files NOT touched in Phase 2

- `lib/screens/estimator_screen.dart` — still uses old save/load path
- `lib/screens/project_list_screen.dart` — still the entry for Open
- `lib/providers/estimator_providers.dart` — no changes, no new imports
- `lib/widgets/*` — no UI changes
- `lib/services/export_service.dart` — no changes

---

## Task 1: Active job/estimate state providers and load/save helpers

**Files:**
- Create: `lib/providers/job_providers.dart`
- Create: `test/providers/job_providers_test.dart`

This task creates the core state providers and the two pure helper functions that bridge between the job/estimate model layer and the existing `estimatorProvider`.

### Step 1.1 — Write the failing test

- [ ] **Create `test/providers/job_providers_test.dart`:**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/providers/job_providers.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/models/estimate.dart';
import 'package:protpo_app/services/serialization.dart';

void main() {
  group('activeJobIdProvider', () {
    test('initial value is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeJobIdProvider), isNull);
    });

    test('can be set to a job ID', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeJobIdProvider.notifier).state = 'job-42';
      expect(container.read(activeJobIdProvider), 'job-42');
    });
  });

  group('activeEstimateIdProvider', () {
    test('initial value is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeEstimateIdProvider), isNull);
    });

    test('can be set to an estimate ID', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeEstimateIdProvider.notifier).state = 'est-99';
      expect(container.read(activeEstimateIdProvider), 'est-99');
    });
  });

  group('hasActiveEstimate', () {
    test('returns false when both IDs are null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(hasActiveEstimateProvider), isFalse);
    });

    test('returns false when only jobId is set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeJobIdProvider.notifier).state = 'job-1';
      expect(container.read(hasActiveEstimateProvider), isFalse);
    });

    test('returns true when both IDs are set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeJobIdProvider.notifier).state = 'job-1';
      container.read(activeEstimateIdProvider.notifier).state = 'est-1';
      expect(container.read(hasActiveEstimateProvider), isTrue);
    });
  });

  group('loadEstimateIntoEditor', () {
    test('hydrates estimatorProvider from estimate.estimatorState', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Build a realistic estimatorState map using the existing serializer
      final state = container.read(estimatorProvider);
      final notifier = container.read(estimatorProvider.notifier);
      notifier.updateProjectInfo(state.projectInfo.copyWith(
        projectName: 'Warehouse Bid',
        customerName: 'Acme Properties',
      ));
      final serialized = stateToJson(container.read(estimatorProvider), 'est-test');

      // Reset the estimator to blank
      notifier.loadState(container.read(estimatorProvider).copyWith(
        projectInfo: container.read(estimatorProvider).projectInfo.copyWith(
          projectName: '', customerName: '',
        ),
      ));
      expect(container.read(estimatorProvider).projectInfo.projectName, '');

      // Create an Estimate carrying the serialized state
      final estimate = Estimate(
        id: 'est-test',
        name: 'TPO Bid',
        estimatorState: serialized,
      );

      // Load the estimate into the editor
      final result = loadEstimateIntoEditor(container, estimate, 'job-42');
      expect(result, isTrue);
      expect(container.read(activeJobIdProvider), 'job-42');
      expect(container.read(activeEstimateIdProvider), 'est-test');
      expect(
        container.read(estimatorProvider).projectInfo.projectName,
        'Warehouse Bid',
      );
    });

    test('returns false when estimatorState is empty/invalid', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final estimate = Estimate(
        id: 'est-bad',
        name: 'Bad Estimate',
        estimatorState: const {},
      );

      final result = loadEstimateIntoEditor(container, estimate, 'job-1');
      expect(result, isFalse);
      expect(container.read(activeJobIdProvider), isNull);
      expect(container.read(activeEstimateIdProvider), isNull);
    });
  });

  group('buildEstimateDraft', () {
    test('serializes current estimator state into an Estimate update', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Set up an active estimate context
      container.read(activeJobIdProvider.notifier).state = 'job-1';
      container.read(activeEstimateIdProvider.notifier).state = 'est-1';

      // Put some data in the estimator
      final notifier = container.read(estimatorProvider.notifier);
      notifier.updateProjectInfo(
        container.read(estimatorProvider).projectInfo.copyWith(
          projectName: 'Test Project',
        ),
      );

      final draft = buildEstimateDraft(container, 'est-1', 'TPO Bid');
      expect(draft, isNotNull);
      expect(draft!.id, 'est-1');
      expect(draft.name, 'TPO Bid');
      expect(draft.estimatorState['projectInfo'], isNotNull);
      expect(
        (draft.estimatorState['projectInfo'] as Map)['projectName'],
        'Test Project',
      );
      expect(draft.totalArea, isA<double>());
      expect(draft.buildingCount, greaterThan(0));
    });

    test('returns null when activeEstimateId is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Don't set activeEstimateIdProvider
      final draft = buildEstimateDraft(container, '', 'Name');
      expect(draft, isNull);
    });
  });
}
```

### Step 1.2 — Run test to verify it fails

- [ ] **Run:** `flutter test test/providers/job_providers_test.dart`

Expected: FAIL with "Target of URI doesn't exist: 'package:protpo_app/providers/job_providers.dart'"

### Step 1.3 — Create the job_providers.dart file

- [ ] **Create `lib/providers/job_providers.dart`:**

```dart
/// lib/providers/job_providers.dart
///
/// Riverpod providers for the job record feature.
///
/// Responsibilities:
///   - State providers for active job/estimate IDs (navigation context)
///   - Stream providers for Firestore collections (customers, jobs, estimates,
///     versions, activities) — see Task 2
///   - Pure helper functions that bridge between the estimate data layer
///     and the existing estimatorProvider
///
/// This file is intentionally separate from estimator_providers.dart (1524
/// lines) to keep responsibilities bounded.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/estimate.dart';
import '../providers/estimator_providers.dart';
import '../services/serialization.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// NAVIGATION STATE — which job/estimate is currently loaded in the editor
// ═══════════════════════════════════════════════════════════════════════════════

/// The currently-loaded job ID. Null when no job is loaded (fresh launch,
/// or user hasn't opened a job yet). Set by `loadEstimateIntoEditor` or
/// session restore. UI reads this to show the job context ribbon.
final activeJobIdProvider = StateProvider<String?>((ref) => null);

/// The currently-loaded estimate ID within the active job. Null when no
/// estimate is loaded. Always null if activeJobId is null.
final activeEstimateIdProvider = StateProvider<String?>((ref) => null);

/// True when both an active job and estimate are set — meaning the editor
/// is working on a real estimate and autosave should write to the estimate
/// doc rather than protpo_projects. Used by estimator_screen to decide
/// which save path to use.
final hasActiveEstimateProvider = Provider<bool>((ref) {
  final jobId = ref.watch(activeJobIdProvider);
  final estId = ref.watch(activeEstimateIdProvider);
  return jobId != null && estId != null;
});

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS — bridging between job/estimate and estimatorProvider
// ═══════════════════════════════════════════════════════════════════════════════

/// Loads an estimate's serialized state into the estimator for editing.
///
/// Deserializes [estimate.estimatorState] via [stateFromJson], hydrates
/// the [estimatorProvider], and sets the active job/estimate IDs.
///
/// Returns true if the load succeeded, false if the estimatorState was
/// empty or structurally invalid (in which case the IDs remain unchanged).
///
/// This is a pure function over the ProviderContainer — no Firestore I/O.
/// The caller is responsible for fetching the Estimate from Firestore first.
bool loadEstimateIntoEditor(
  ProviderContainer container,
  Estimate estimate,
  String jobId,
) {
  if (estimate.estimatorState.isEmpty) return false;

  final loaded = stateFromJson(estimate.estimatorState);
  if (loaded == null) return false;

  container.read(estimatorProvider.notifier).loadState(loaded);
  container.read(activeJobIdProvider.notifier).state = jobId;
  container.read(activeEstimateIdProvider.notifier).state = estimate.id;
  return true;
}

/// Also works with a WidgetRef for use inside widgets (Phase 4+).
bool loadEstimateIntoEditorRef(
  dynamic ref,
  Estimate estimate,
  String jobId,
) {
  if (estimate.estimatorState.isEmpty) return false;

  final loaded = stateFromJson(estimate.estimatorState);
  if (loaded == null) return false;

  ref.read(estimatorProvider.notifier).loadState(loaded);
  ref.read(activeJobIdProvider.notifier).state = jobId;
  ref.read(activeEstimateIdProvider.notifier).state = estimate.id;
  return true;
}

/// Builds an updated [Estimate] object from the current estimator state,
/// ready to be written back to Firestore via `FirestoreService.updateEstimate`.
///
/// Returns null if [estimateId] is empty (no active estimate to save to).
///
/// This is a pure function — no Firestore I/O. The caller writes the
/// returned Estimate to Firestore.
Estimate? buildEstimateDraft(
  ProviderContainer container,
  String estimateId,
  String estimateName,
) {
  if (estimateId.isEmpty) return null;

  final state = container.read(estimatorProvider);
  final serialized = stateToJson(state, estimateId);

  // Compute denormalized list-view fields from the current state
  final totalArea = state.buildings
      .fold(0.0, (sum, b) => sum + b.roofGeometry.totalArea);
  // Total value could come from BOM provider, but we don't want to depend
  // on bomProvider here (it pulls in the whole BOM engine). Use 0 for now;
  // Phase 5 will compute it when wiring the real save path.
  final buildingCount = state.buildings.length;

  return Estimate(
    id: estimateId,
    name: estimateName,
    estimatorState: serialized,
    totalArea: totalArea,
    totalValue: 0, // computed by save path in Phase 5
    buildingCount: buildingCount,
  );
}
```

### Step 1.4 — Run test to verify it passes

- [ ] **Run:** `flutter test test/providers/job_providers_test.dart`

Expected: All tests pass. If the `loadEstimateIntoEditor` round-trip test fails, verify that `stateToJson` and `stateFromJson` are imported correctly from `lib/services/serialization.dart`.

### Step 1.5 — Commit

- [ ] **Run:**

```bash
git add lib/providers/job_providers.dart test/providers/job_providers_test.dart
git commit -m "feat(providers): add job record state providers and load/save helpers

Creates job_providers.dart with:
- activeJobIdProvider / activeEstimateIdProvider (navigation state)
- hasActiveEstimateProvider (derived bool for save-path routing)
- loadEstimateIntoEditor: deserializes estimate.estimatorState via
  stateFromJson, hydrates estimatorProvider, sets active IDs
- buildEstimateDraft: serializes current estimator state into an
  Estimate object ready for Firestore write

All helpers are pure functions over ProviderContainer — no Firestore
I/O. The caller fetches/writes the data. Tested with 10 tests.

Part of Phase 2 (State Management) for the job record feature.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Firestore stream providers

**Files:**
- Modify: `lib/providers/job_providers.dart` (append stream providers at the bottom)

These providers are thin wrappers over `FirestoreService` streams. They have no business logic — they just expose Firestore data reactively. No unit tests are written for them because testing would only verify that we called the SDK correctly.

### Step 2.1 — Add imports for FirestoreService and models

- [ ] **Edit `lib/providers/job_providers.dart`.** Find the existing import block and add:

```dart
import '../services/firestore_service.dart';
import '../models/customer.dart';
import '../models/job.dart';
import '../models/estimate_version.dart';
import '../models/activity.dart';
```

### Step 2.2 — Append stream providers after the helper functions section

- [ ] **Append the following to `lib/providers/job_providers.dart`**, after the closing `}` of `buildEstimateDraft`:

```dart
// ═══════════════════════════════════════════════════════════════════════════════
// FIRESTORE STREAM PROVIDERS — reactive access to job record collections
//
// These are thin wrappers over FirestoreService methods. No business logic.
// Not unit tested — they delegate directly to cloud_firestore streams.
// ═══════════════════════════════════════════════════════════════════════════════

/// All customers, ordered by name. Used by the Settings "Customers" tab
/// and the customer picker in the new-job flow.
final customersListProvider = StreamProvider<List<Customer>>((ref) {
  return FirestoreService.instance.streamCustomers();
});

/// Single customer by ID. Used by Job Detail Overview tab.
final customerProvider =
    FutureProvider.family<Customer?, String>((ref, customerId) {
  return FirestoreService.instance.getCustomer(customerId);
});

/// All jobs, most-recently-updated first. Used by the Job List Sheet.
final jobsListProvider = StreamProvider<List<Job>>((ref) {
  return FirestoreService.instance.streamJobs();
});

/// Single job by ID (live stream). Used by Job Detail header and overview.
final jobProvider = StreamProvider.family<Job?, String>((ref, jobId) {
  return FirestoreService.instance.streamJob(jobId);
});

/// Estimates for a specific job, most-recently-updated first.
/// Used by the Estimates tab in Job Detail.
final estimatesForJobProvider =
    StreamProvider.family<List<Estimate>, String>((ref, jobId) {
  return FirestoreService.instance.streamEstimates(jobId);
});

/// Version history for a specific estimate. Loaded on-demand when the
/// user expands the version list in the Estimates tab.
final versionsForEstimateProvider = FutureProvider.family<
    List<EstimateVersion>, ({String jobId, String estimateId})>((ref, ids) {
  return FirestoreService.instance.listVersions(ids.jobId, ids.estimateId);
});

/// Activity timeline for a specific job, newest first.
/// Used by the Activity tab in Job Detail.
final activitiesForJobProvider =
    StreamProvider.family<List<Activity>, String>((ref, jobId) {
  return FirestoreService.instance.streamActivities(jobId);
});
```

### Step 2.3 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/providers/job_providers.dart`

Expected: No issues found (or only pre-existing info-level warnings).

### Step 2.4 — Verify existing tests still pass

- [ ] **Run:** `flutter test test/providers/job_providers_test.dart`

Expected: All tests from Task 1 still pass. The new stream providers don't affect the existing tests.

### Step 2.5 — Commit

- [ ] **Run:**

```bash
git add lib/providers/job_providers.dart
git commit -m "feat(providers): add Firestore stream providers for job record

Thin reactive wrappers over FirestoreService:
- customersListProvider (StreamProvider, ordered by name)
- customerProvider.family (FutureProvider by ID)
- jobsListProvider (StreamProvider, newest first)
- jobProvider.family (StreamProvider by ID)
- estimatesForJobProvider.family (StreamProvider by job ID)
- versionsForEstimateProvider.family (FutureProvider by job+estimate)
- activitiesForJobProvider.family (StreamProvider by job ID)

No business logic, no unit tests — delegates directly to
FirestoreService.stream* methods from Phase 1.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Session persistence (last-opened job + estimate)

**Files:**
- Modify: `lib/services/firestore_service.dart` (append 2 methods)
- Modify: `lib/providers/job_providers.dart` (add restoreLastSession helper)
- Modify: `test/providers/job_providers_test.dart` (add session restore test)

### Step 3.1 — Add session persistence methods to FirestoreService

- [ ] **Edit `lib/services/firestore_service.dart`.** Append the following methods just before the final closing `}` of the class:

```dart
// ═══════════════════════════════════════════════════════════════════════
// SESSION PERSISTENCE
// ═══════════════════════════════════════════════════════════════════════

/// Saves the last-opened job and estimate IDs so the app can restore
/// context on the next launch. Written to protpo_settings/last_session.
Future<void> saveLastSession({
  required String? jobId,
  required String? estimateId,
}) async {
  await _db.collection(_settingsCol).doc('last_session').set({
    'jobId': jobId,
    'estimateId': estimateId,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

/// Loads the last-opened job and estimate IDs. Returns null values if
/// no session has been saved yet.
Future<({String? jobId, String? estimateId})> loadLastSession() async {
  final snap = await _db.collection(_settingsCol).doc('last_session').get();
  final data = snap.data();
  if (data == null) return (jobId: null, estimateId: null);
  return (
    jobId: data['jobId'] as String?,
    estimateId: data['estimateId'] as String?,
  );
}
```

### Step 3.2 — Add restoreLastSession helper to job_providers.dart

- [ ] **Edit `lib/providers/job_providers.dart`.** Append the following after the stream providers section:

```dart
// ═══════════════════════════════════════════════════════════════════════════════
// SESSION RESTORE — reload the last-opened job/estimate on app launch
// ═══════════════════════════════════════════════════════════════════════════════

/// Attempts to restore the last-opened job and estimate from
/// `protpo_settings/last_session`. If the job or estimate no longer exists
/// in Firestore, silently returns false without changing state.
///
/// Called once on app startup (Phase 4+ wires this into initState).
Future<bool> restoreLastSession(ProviderContainer container) async {
  final fs = FirestoreService.instance;

  // Read the last session IDs
  final session = await fs.loadLastSession();
  if (session.jobId == null || session.estimateId == null) return false;

  // Verify the job still exists
  final job = await fs.getJob(session.jobId!);
  if (job == null) return false;

  // Verify the estimate still exists
  final estimate = await fs.getEstimate(session.jobId!, session.estimateId!);
  if (estimate == null) return false;

  // Load the estimate into the editor
  return loadEstimateIntoEditor(container, estimate, session.jobId!);
}

/// Persists the current active job/estimate IDs for session restore.
/// Call this whenever the active job or estimate changes (Phase 5 wires
/// this into the save path and the load-into-editor flow).
Future<void> persistActiveSession(ProviderContainer container) async {
  final jobId = container.read(activeJobIdProvider);
  final estId = container.read(activeEstimateIdProvider);
  await FirestoreService.instance.saveLastSession(
    jobId: jobId,
    estimateId: estId,
  );
}
```

### Step 3.3 — Add import for FirestoreService if not already present

- [ ] **Check** that `lib/providers/job_providers.dart` already has `import '../services/firestore_service.dart';` from Task 2. If it does, no action needed. If not, add it.

### Step 3.4 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/providers/job_providers.dart lib/services/firestore_service.dart`

Expected: No new issues.

### Step 3.5 — Verify existing tests still pass

- [ ] **Run:** `flutter test test/providers/job_providers_test.dart`

Expected: All tests from Task 1 still pass. The new session functions are async and Firestore-dependent — they aren't called by the existing tests.

### Step 3.6 — Commit

- [ ] **Run:**

```bash
git add lib/services/firestore_service.dart lib/providers/job_providers.dart
git commit -m "feat(providers): add session persistence for last-opened job/estimate

FirestoreService gains saveLastSession/loadLastSession that persist
the active job + estimate IDs to protpo_settings/last_session.

job_providers gains restoreLastSession (verifies job and estimate
still exist before loading) and persistActiveSession (saves current
IDs after every navigation change). Both are async and called by
Phase 4+ UI code.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Final verification

**Files:** none modified

### Step 4.1 — Run all provider tests

- [ ] **Run:** `flutter test test/providers/`

Expected: All tests pass (job_providers_test.dart + existing board_schedule_provider_test.dart).

### Step 4.2 — Run all model tests

- [ ] **Run:** `flutter test test/models/`

Expected: 47 tests pass (unchanged from Phase 1).

### Step 4.3 — Run flutter analyze on new/modified files

- [ ] **Run:** `flutter analyze lib/providers/job_providers.dart lib/services/firestore_service.dart`

Expected: No new errors. Pre-existing info-level warnings are OK.

### Step 4.4 — Verify git status is clean

- [ ] **Run:** `git status`

Expected: `nothing to commit, working tree clean` (all Phase 2 work has been committed in Tasks 1-3).

### Step 4.5 — Push to GitHub

- [ ] **Run:** `git push origin main`

Expected: Push succeeds with 3 new commits.

### Step 4.6 — Phase 2 complete checkpoint

Phase 2 is done when all of the following are true:

- [ ] `lib/providers/job_providers.dart` exists with:
  - `activeJobIdProvider` (StateProvider<String?>)
  - `activeEstimateIdProvider` (StateProvider<String?>)
  - `hasActiveEstimateProvider` (derived Provider<bool>)
  - `loadEstimateIntoEditor` (pure function, tested)
  - `loadEstimateIntoEditorRef` (ref-based variant for widgets)
  - `buildEstimateDraft` (pure function, tested)
  - 7 Firestore stream providers (customers, jobs, estimates, versions, activities)
  - `restoreLastSession` + `persistActiveSession` (async helpers)
- [ ] `lib/services/firestore_service.dart` has `saveLastSession` + `loadLastSession`
- [ ] `test/providers/job_providers_test.dart` passes all tests
- [ ] `flutter analyze` shows no new errors
- [ ] All commits pushed to `origin/main`
- [ ] The running app at `tpo-pro-245d1.web.app` is unchanged

The estimator screen still uses the old save path. Phase 3 adds Customer CRUD UI, and Phase 5 wires the new providers into the estimator's save/load flow.

---

## Notes for the implementing engineer

- **Do NOT modify `estimator_providers.dart`.** Phase 2 only adds `job_providers.dart` alongside it. The existing 1524-line file stays untouched.
- **The `loadEstimateIntoEditor` function uses `ProviderContainer`**, not `WidgetRef`, because it needs to work in tests. The `loadEstimateIntoEditorRef` variant accepts a dynamic ref for widget-context calls in Phase 4+. Both do the same thing.
- **`buildEstimateDraft` sets `totalValue` to 0.** Computing the real total requires reading `bomProvider` which has heavy dependencies. Phase 5 will compute it when it wires the real save path. For now, 0 is a placeholder that doesn't affect any UI.
- **Stream providers use `FirestoreService.instance`** (the singleton) directly. This is consistent with how the existing codebase uses FirestoreService (see estimator_screen.dart lines 85, 108). If injectable DI is needed later, it's a single-line change to a provider-based DI.
- **Session restore validates existence.** `restoreLastSession` calls `getJob` and `getEstimate` before loading. If either is deleted since the last session, it silently returns false. The UI shows "No job loaded — tap to open" (Phase 4+).
- **The `versionsForEstimateProvider` uses a Dart 3 record `({String jobId, String estimateId})` as the family key.** This requires Dart 3.0+ which is already the project's minimum SDK.
