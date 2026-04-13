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
import '../services/firestore_service.dart';
import '../models/customer.dart';
import '../models/job.dart';
import '../models/estimate_version.dart';
import '../models/activity.dart';

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

  final totalArea = state.buildings
      .fold(0.0, (sum, b) => sum + b.roofGeometry.totalArea);
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
final jobStreamProvider = StreamProvider.family<Job?, String>((ref, jobId) {
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
