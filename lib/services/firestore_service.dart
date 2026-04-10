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
}
