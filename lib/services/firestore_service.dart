/// lib/services/firestore_service.dart
///
/// All Firestore persistence for ProTPO projects.
///
/// Collection:  protpo_projects
/// Document ID: UUID generated on first save, stored in EstimatorState.projectId
///
/// Each document contains the full serialised EstimatorState plus metadata
/// fields (projectName, customerName, savedAt, totalArea) for efficient
/// list-view rendering without deserialising the whole document.

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/estimator_state.dart';
import 'serialization.dart';
import '../models/customer.dart';
import '../models/job.dart';
import '../models/estimate.dart';
import '../models/estimate_version.dart';
import '../models/activity.dart';

// ─── PROJECT SUMMARY ─────────────────────────────────────────────────────────
// Lightweight snapshot used in the project list screen.

class ProjectSummary {
  final String   projectId;
  final String   projectName;
  final String   customerName;
  final String   address;
  final DateTime savedAt;
  final double   totalArea;
  final int      buildingCount;

  const ProjectSummary({
    required this.projectId,
    required this.projectName,
    required this.customerName,
    required this.address,
    required this.savedAt,
    required this.totalArea,
    required this.buildingCount,
  });

  factory ProjectSummary.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ProjectSummary(
      projectId:     doc.id,
      projectName:   d['projectName']  as String? ?? 'Untitled Project',
      customerName:  d['customerName'] as String? ?? '',
      address:       d['address']      as String? ?? '',
      savedAt:       (d['savedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalArea:     (d['totalArea']   as num?)?.toDouble() ?? 0.0,
      buildingCount: (d['buildingCount'] as int?) ?? 1,
    );
  }
}

// ─── SERVICE ─────────────────────────────────────────────────────────────────

class FirestoreService {
  static final FirestoreService instance = FirestoreService._();
  FirestoreService._();

  final _db       = FirebaseFirestore.instance;
  final _uuid     = const Uuid();
  final _colName  = 'protpo_projects';

  static const _customersCol = 'protpo_customers';
  static const _jobsCol = 'protpo_jobs';
  static const _estimatesSubcol = 'estimates';
  static const _versionsSubcol = 'versions';
  static const _activitiesSubcol = 'activities';

  CollectionReference<Map<String, dynamic>> get _col => _db.collection(_colName);

  // ── Save ─────────────────────────────────────────────────────────────────

  /// Saves [state] to Firestore and returns the project ID used.
  /// Pass [projectId] to overwrite an existing project; omit to create new.
  Future<String> save(EstimatorState state, {String? projectId}) async {
    final id  = projectId ?? _uuid.v4();
    final doc = stateToJson(state, id);

    // Top-level metadata for list queries (avoids deserialising full payload)
    doc['projectName']   = state.projectInfo.projectName.isNotEmpty
        ? state.projectInfo.projectName : 'Untitled Project';
    doc['customerName']  = state.projectInfo.customerName;
    doc['address']       = state.projectInfo.projectAddress;
    doc['savedAt']       = FieldValue.serverTimestamp();
    doc['totalArea']     = state.buildings
        .fold(0.0, (sum, b) => sum + b.roofGeometry.totalArea);
    doc['buildingCount'] = state.buildings.length;

    await _col.doc(id).set(doc);
    return id;
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  /// Loads a project by ID. Returns null if not found or deserialization fails.
  Future<EstimatorState?> load(String projectId) async {
    final snap = await _col.doc(projectId).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return stateFromJson(data);
  }

  // ── List ─────────────────────────────────────────────────────────────────

  /// Returns all saved projects as lightweight summaries, newest first.
  Future<List<ProjectSummary>> listProjects() async {
    final snap = await _col
        .orderBy('savedAt', descending: true)
        .limit(100)
        .get();
    return snap.docs.map(ProjectSummary.fromDoc).toList();
  }

  /// Stream version — updates in real time.
  Stream<List<ProjectSummary>> watchProjects() {
    return _col
        .orderBy('savedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map(ProjectSummary.fromDoc).toList());
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> delete(String projectId) async {
    await _col.doc(projectId).delete();
  }

  // ── Duplicate ─────────────────────────────────────────────────────────────

  /// Creates a copy of an existing project with " (Copy)" appended to name.
  Future<String?> duplicate(String projectId) async {
    final state = await load(projectId);
    if (state == null) return null;
    final copied = state.copyWith(
      projectInfo: state.projectInfo.copyWith(
        projectName: '${state.projectInfo.projectName} (Copy)',
        estimateDate: DateTime.now(),
      ),
    );
    return save(copied);
  }

  // ── Company Profile (user-level settings) ──────────────────────────────

  static const _settingsCol = 'protpo_settings';
  static const _profileDocId = 'company_profile';

  /// Saves company profile (without logo bytes — those are stored separately).
  Future<void> saveCompanyProfile(Map<String, dynamic> profileJson) async {
    await _db.collection(_settingsCol).doc(_profileDocId).set({
      ...profileJson,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Saves the logo bytes as a separate document (Firestore 1MB limit per doc).
  Future<void> saveCompanyLogo(List<int> logoBytes) async {
    // Store as base64 string to fit in a Firestore document
    final base64 = base64Encode(logoBytes);
    await _db.collection(_settingsCol).doc('company_logo').set({
      'data': base64,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCompanyLogo() async {
    await _db.collection(_settingsCol).doc('company_logo').delete();
  }

  /// Loads company profile JSON (without logo).
  Future<Map<String, dynamic>?> loadCompanyProfile() async {
    final snap = await _db.collection(_settingsCol).doc(_profileDocId).get();
    return snap.data();
  }

  /// Loads company logo bytes.
  Future<List<int>?> loadCompanyLogo() async {
    final snap = await _db.collection(_settingsCol).doc('company_logo').get();
    final data = snap.data();
    if (data == null) return null;
    final b64 = data['data'] as String?;
    if (b64 == null || b64.isEmpty) return null;
    return base64Decode(b64);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CUSTOMERS
  // ═══════════════════════════════════════════════════════════════════════

  CollectionReference<Map<String, dynamic>> get _customers =>
      _db.collection(_customersCol);

  Future<String> createCustomer(Customer c) async {
    final id = c.id.isNotEmpty ? c.id : _uuid.v4();
    await _customers.doc(id).set({
      ...c.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<void> updateCustomer(Customer c) async {
    await _customers.doc(c.id).set({
      ...c.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteCustomer(String customerId) async {
    await _customers.doc(customerId).delete();
  }

  Future<Customer?> getCustomer(String customerId) async {
    final snap = await _customers.doc(customerId).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return Customer.fromJson(snap.id, data);
  }

  Stream<List<Customer>> streamCustomers() {
    return _customers.orderBy('name').snapshots().map((s) =>
        s.docs.map((d) => Customer.fromJson(d.id, d.data())).toList());
  }

  // ═══════════════════════════════════════════════════════════════════════
  // JOBS
  // ═══════════════════════════════════════════════════════════════════════

  CollectionReference<Map<String, dynamic>> get _jobs =>
      _db.collection(_jobsCol);

  Future<String> createJob(Job j) async {
    final id = j.id.isNotEmpty ? j.id : _uuid.v4();
    await _jobs.doc(id).set({
      ...j.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<void> updateJob(Job j) async {
    await _jobs.doc(j.id).set({
      ...j.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteJobCascade(String jobId) async {
    final jobRef = _jobs.doc(jobId);

    final estimates = await jobRef.collection(_estimatesSubcol).get();
    for (final est in estimates.docs) {
      final versions = await est.reference.collection(_versionsSubcol).get();
      for (final v in versions.docs) {
        await v.reference.delete();
      }
      await est.reference.delete();
    }

    final activities = await jobRef.collection(_activitiesSubcol).get();
    for (final a in activities.docs) {
      await a.reference.delete();
    }

    await jobRef.delete();
  }

  Future<Job?> getJob(String jobId) async {
    final snap = await _jobs.doc(jobId).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return Job.fromJson(snap.id, data);
  }

  Stream<Job?> streamJob(String jobId) {
    return _jobs.doc(jobId).snapshots().map((s) {
      if (!s.exists) return null;
      final data = s.data();
      if (data == null) return null;
      return Job.fromJson(s.id, data);
    });
  }

  Stream<List<Job>> streamJobs() {
    return _jobs
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map((d) => Job.fromJson(d.id, d.data())).toList());
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ESTIMATES (subcollection of jobs)
  // ═══════════════════════════════════════════════════════════════════════

  CollectionReference<Map<String, dynamic>> _estimates(String jobId) =>
      _jobs.doc(jobId).collection(_estimatesSubcol);

  Future<String> createEstimate(String jobId, Estimate e) async {
    final id = e.id.isNotEmpty ? e.id : _uuid.v4();
    await _estimates(jobId).doc(id).set({
      ...e.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<void> updateEstimate(String jobId, Estimate e) async {
    await _estimates(jobId).doc(e.id).set({
      ...e.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteEstimate(String jobId, String estimateId) async {
    final estRef = _estimates(jobId).doc(estimateId);
    final versions = await estRef.collection(_versionsSubcol).get();
    for (final v in versions.docs) {
      await v.reference.delete();
    }
    await estRef.delete();
  }

  Future<Estimate?> getEstimate(String jobId, String estimateId) async {
    final snap = await _estimates(jobId).doc(estimateId).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return Estimate.fromJson(snap.id, data);
  }

  Stream<List<Estimate>> streamEstimates(String jobId) {
    return _estimates(jobId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => Estimate.fromJson(d.id, d.data())).toList());
  }

  // ═══════════════════════════════════════════════════════════════════════
  // VERSIONS (subcollection of estimates, append-only)
  // ═══════════════════════════════════════════════════════════════════════

  CollectionReference<Map<String, dynamic>> _versions(
          String jobId, String estimateId) =>
      _estimates(jobId).doc(estimateId).collection(_versionsSubcol);

  Future<String> createVersion(
      String jobId, String estimateId, EstimateVersion v) async {
    final id = v.id.isNotEmpty ? v.id : _uuid.v4();
    await _versions(jobId, estimateId).doc(id).set({
      ...v.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<void> deleteVersion(
      String jobId, String estimateId, String versionId) async {
    await _versions(jobId, estimateId).doc(versionId).delete();
  }

  Future<List<EstimateVersion>> listVersions(
      String jobId, String estimateId) async {
    final snap = await _versions(jobId, estimateId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .map((d) => EstimateVersion.fromJson(d.id, d.data()))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ACTIVITIES (subcollection of jobs)
  // ═══════════════════════════════════════════════════════════════════════

  CollectionReference<Map<String, dynamic>> _activities(String jobId) =>
      _jobs.doc(jobId).collection(_activitiesSubcol);

  Future<String> createActivity(String jobId, Activity a) async {
    final id = a.id.isNotEmpty ? a.id : _uuid.v4();
    await _activities(jobId).doc(id).set(a.toJson());
    return id;
  }

  Future<void> updateTaskCompletion(
      String jobId, String activityId, bool completed) async {
    await _activities(jobId).doc(activityId).set({
      'taskCompleted': completed,
      if (completed)
        'taskCompletedAt': FieldValue.serverTimestamp()
      else
        'taskCompletedAt': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteActivity(String jobId, String activityId) async {
    await _activities(jobId).doc(activityId).delete();
  }

  Stream<List<Activity>> streamActivities(String jobId) {
    return _activities(jobId)
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => Activity.fromJson(d.id, d.data())).toList());
  }

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
}
