/// lib/models/estimate_version.dart
///
/// Frozen snapshot of an estimate at a point in time. Lives as a subcollection
/// under its estimate: `protpo_jobs/{jobId}/estimates/{estimateId}/versions/{vId}`.
/// Versions are immutable by Firestore rule — no updates allowed after create.

/// How the version was created.
enum VersionSource {
  /// User clicked "Save as version" in the estimator.
  manual,

  /// Auto-snapshotted before a PDF export.
  export,
}

class EstimateVersion {
  final String id;

  /// Human-readable label. Examples:
  /// - "v1 — initial walkthrough"  (manual)
  /// - "Export 2026-04-11 14:32"    (auto)
  /// - "Manual snapshot 2026-04-11 14:32" (manual with no user-provided label)
  final String label;

  final VersionSource source;

  /// Frozen EstimatorState map — same shape as Estimate.estimatorState but
  /// immutable after creation. Opaque at this model layer.
  final Map<String, dynamic> estimatorState;

  /// Server-set at create. Required — versions always carry a timestamp.
  final DateTime createdAt;

  /// Estimator name from the company profile at the time of snapshot.
  final String createdBy;

  const EstimateVersion({
    required this.id,
    required this.label,
    required this.source,
    required this.estimatorState,
    required this.createdAt,
    required this.createdBy,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'source': source.name,
        'estimatorState': estimatorState,
        'createdAt': createdAt.toIso8601String(),
        'createdBy': createdBy,
      };

  factory EstimateVersion.fromJson(String id, Map<String, dynamic> json) {
    VersionSource parseSource(dynamic v) {
      if (v is String) {
        try {
          return VersionSource.values.byName(v);
        } catch (_) {
          return VersionSource.manual;
        }
      }
      return VersionSource.manual;
    }

    DateTime parseTs(dynamic v) {
      if (v is String) {
        return DateTime.tryParse(v) ?? DateTime.now();
      }
      try {
        return (v as dynamic).toDate() as DateTime;
      } catch (_) {
        return DateTime.now();
      }
    }

    return EstimateVersion(
      id: id,
      label: (json['label'] as String?) ?? '',
      source: parseSource(json['source']),
      estimatorState: Map<String, dynamic>.from(
          (json['estimatorState'] as Map?) ?? const {}),
      createdAt: parseTs(json['createdAt']),
      createdBy: (json['createdBy'] as String?) ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EstimateVersion &&
          id == other.id &&
          label == other.label &&
          source == other.source &&
          estimatorState.length == other.estimatorState.length &&
          createdAt == other.createdAt &&
          createdBy == other.createdBy;

  @override
  int get hashCode => Object.hash(
        id,
        label,
        source,
        estimatorState.length,
        createdAt,
        createdBy,
      );
}
