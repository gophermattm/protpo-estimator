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
import '../models/estimator_state.dart';
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

/// Display name for the active job — set when loading an estimate.
/// Used by the estimator context ribbon. Not reactive to Firestore changes.
final activeJobNameProvider = StateProvider<String>((ref) => '');

/// Display name for the active customer — set when loading an estimate.
final activeCustomerNameProvider = StateProvider<String>((ref) => '');

/// Display name for the active estimate — set when loading an estimate.
final activeEstimateNameProvider = StateProvider<String>((ref) => '');

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

/// Estimator state for [estimate]: a never-saved (empty) estimate starts
/// blank; a non-empty but unparseable one returns null.
///
/// An empty estimate used to be rejected, which left the previous job's roof
/// in the editor under the new job — and saving wrote it into the new job.
EstimatorState? _stateForEstimate(Estimate estimate) {
  if (estimate.estimatorState.isEmpty) return EstimatorState.initial();
  return stateFromJson(estimate.estimatorState);
}

/// BOM/labor edits, deletions, manual lines, QXO prices and per-item margins
/// are keyed by line name, not by job. Clear them on every job switch so one
/// job's overrides (e.g. a membrane qty edited to 0) don't apply to the next.
void _clearJobScopedOverrides(dynamic ref) {
  ref.read(bomLineEditsProvider.notifier).state = <String, BomLineEdit>{};
  ref.read(bomDeletedItemsProvider.notifier).state = <String>{};
  ref.read(bomManualItemsProvider.notifier).state = <ManualBomItem>[];
  ref.read(pricedItemsProvider.notifier).state = null;
  ref.read(itemMarginOverridesProvider.notifier).state = <String, double>{};
  ref.read(laborLineEditsProvider.notifier).state = <String, LaborLineEdit>{};
  ref.read(laborDeletedItemsProvider.notifier).state = <String>{};
  ref.read(laborManualItemsProvider.notifier).state = <ManualLaborItem>[];
}

/// Key under Estimate.estimatorState holding the user's BOM/labor overrides.
const kOverridesKey = 'overrides';

double? _numOrNull(dynamic v) => (v as num?)?.toDouble();

/// Serializes BOM/labor edits, deletions, manual lines and per-item margins
/// so they are saved with the estimate (they used to be lost on reload).
/// QXO prices are not stored — they are re-fetched.
Map<String, dynamic> estimateOverridesToJson(dynamic ref) {
  final Map<String, BomLineEdit> bomEdits = ref.read(bomLineEditsProvider);
  final Set<String> bomDeleted = ref.read(bomDeletedItemsProvider);
  final List<ManualBomItem> bomManual = ref.read(bomManualItemsProvider);
  final Map<String, double> margins = ref.read(itemMarginOverridesProvider);
  final Map<String, LaborLineEdit> laborEdits = ref.read(laborLineEditsProvider);
  final Set<String> laborDeleted = ref.read(laborDeletedItemsProvider);
  final List<ManualLaborItem> laborManual = ref.read(laborManualItemsProvider);
  return {
    'bomEdits': {
      for (final e in bomEdits.entries)
        e.key: {
          'description': e.value.description,
          'partNumber': e.value.partNumber,
          'qty': e.value.qty,
          'unitPrice': e.value.unitPrice,
          'unit': e.value.unit,
        },
    },
    'bomDeleted': bomDeleted.toList(),
    'bomManual': [
      for (final m in bomManual)
        {
          'id': m.id,
          'category': m.category,
          'description': m.description,
          'partNumber': m.partNumber,
          'qty': m.qty,
          'unit': m.unit,
          'unitPrice': m.unitPrice,
        },
    ],
    'itemMargins': margins,
    'laborEdits': {
      for (final e in laborEdits.entries)
        e.key: {
          'description': e.value.description,
          'rate': e.value.rate,
          'qty': e.value.qty,
        },
    },
    'laborDeleted': laborDeleted.toList(),
    'laborManual': [
      for (final m in laborManual)
        {
          'id': m.id,
          'name': m.name,
          'unit': m.unit,
          'rate': m.rate,
          'quantity': m.quantity,
        },
    ],
  };
}

/// Restores overrides saved by [estimateOverridesToJson]. Missing or
/// malformed data leaves the (already cleared) providers empty.
void applyEstimateOverrides(dynamic ref, dynamic json) {
  if (json is! Map) return;
  try {
    final bomEdits = (json['bomEdits'] as Map? ?? {});
    ref.read(bomLineEditsProvider.notifier).state = <String, BomLineEdit>{
      for (final e in bomEdits.entries)
        e.key as String: BomLineEdit(
          description: (e.value as Map)['description'] as String?,
          partNumber: (e.value as Map)['partNumber'] as String?,
          qty: _numOrNull((e.value as Map)['qty']),
          unitPrice: _numOrNull((e.value as Map)['unitPrice']),
          unit: (e.value as Map)['unit'] as String?,
        ),
    };
    ref.read(bomDeletedItemsProvider.notifier).state = <String>{
      for (final k in (json['bomDeleted'] as List? ?? [])) k as String,
    };
    ref.read(bomManualItemsProvider.notifier).state = <ManualBomItem>[
      for (final m in (json['bomManual'] as List? ?? []))
        ManualBomItem(
          id: (m as Map)['id'] as String,
          category: m['category'] as String? ?? '',
          description: m['description'] as String? ?? '',
          partNumber: m['partNumber'] as String? ?? '',
          qty: _numOrNull(m['qty']) ?? 1.0,
          unit: m['unit'] as String? ?? 'each',
          unitPrice: _numOrNull(m['unitPrice']),
        ),
    ];
    ref.read(itemMarginOverridesProvider.notifier).state = <String, double>{
      for (final e in (json['itemMargins'] as Map? ?? {}).entries)
        e.key as String: (e.value as num).toDouble(),
    };
    ref.read(laborLineEditsProvider.notifier).state = <String, LaborLineEdit>{
      for (final e in (json['laborEdits'] as Map? ?? {}).entries)
        e.key as String: LaborLineEdit(
          description: (e.value as Map)['description'] as String?,
          rate: _numOrNull((e.value as Map)['rate']),
          qty: _numOrNull((e.value as Map)['qty']),
        ),
    };
    ref.read(laborDeletedItemsProvider.notifier).state = <String>{
      for (final k in (json['laborDeleted'] as List? ?? [])) k as String,
    };
    ref.read(laborManualItemsProvider.notifier).state = <ManualLaborItem>[
      for (final m in (json['laborManual'] as List? ?? []))
        ManualLaborItem(
          id: (m as Map)['id'] as String,
          name: m['name'] as String? ?? '',
          unit: m['unit'] as String? ?? 'each',
          rate: _numOrNull(m['rate']) ?? 0.0,
          quantity: _numOrNull(m['quantity']) ?? 1.0,
        ),
    ];
  } catch (_) {
    _clearJobScopedOverrides(ref);
  }
}

/// Serialized estimator state plus overrides — what gets written to
/// Estimate.estimatorState on every save/autosave.
Map<String, dynamic> serializeEstimateState(dynamic ref, String estimateId) {
  final json = stateToJson(ref.read(estimatorProvider), estimateId);
  json[kOverridesKey] = estimateOverridesToJson(ref);
  return json;
}

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
  String jobId, {
  String jobName = '',
  String customerName = '',
}) {
  final loaded = _stateForEstimate(estimate);
  if (loaded == null) return false;

  container.read(estimatorProvider.notifier).loadState(loaded);
  _clearJobScopedOverrides(container);
  applyEstimateOverrides(container, estimate.estimatorState[kOverridesKey]);
  container.read(activeJobIdProvider.notifier).state = jobId;
  container.read(activeEstimateIdProvider.notifier).state = estimate.id;
  container.read(activeJobNameProvider.notifier).state = jobName;
  container.read(activeCustomerNameProvider.notifier).state = customerName;
  container.read(activeEstimateNameProvider.notifier).state = estimate.name;
  return true;
}

/// Also works with a WidgetRef for use inside widgets (Phase 4+).
bool loadEstimateIntoEditorRef(
  dynamic ref,
  Estimate estimate,
  String jobId, {
  String jobName = '',
  String customerName = '',
}) {
  final loaded = _stateForEstimate(estimate);
  if (loaded == null) return false;

  ref.read(estimatorProvider.notifier).loadState(loaded);
  _clearJobScopedOverrides(ref);
  applyEstimateOverrides(ref, estimate.estimatorState[kOverridesKey]);
  ref.read(activeJobIdProvider.notifier).state = jobId;
  ref.read(activeEstimateIdProvider.notifier).state = estimate.id;
  ref.read(activeJobNameProvider.notifier).state = jobName;
  ref.read(activeCustomerNameProvider.notifier).state = customerName;
  ref.read(activeEstimateNameProvider.notifier).state = estimate.name;
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
  final serialized = serializeEstimateState(container, estimateId);

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
  return loadEstimateIntoEditor(
    container, estimate, session.jobId!,
    jobName: job.jobName,
    customerName: job.customerName,
  );
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
