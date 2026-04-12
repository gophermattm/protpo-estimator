/// lib/models/estimate.dart
///
/// Estimate entity — lives as a subcollection under a job
/// (`protpo_jobs/{jobId}/estimates/{estimateId}`). Holds the mutable draft
/// `estimatorState` map plus denormalized list-view fields.
///
/// The `estimatorState` map is intentionally opaque at this layer — its shape
/// is defined by `lib/services/serialization.dart` and is the same shape as
/// today's `protpo_projects` documents. This model just carries it around.

class Estimate {
  final String id;
  final String name;

  /// Full serialized EstimatorState as a map. This is the mutable draft that
  /// autosave writes to. Opaque to this model.
  final Map<String, dynamic> estimatorState;

  /// ID of the version this draft was last snapshotted from. Null if no
  /// snapshot has been taken yet.
  final String? activeVersionId;

  /// Denormalized list-view fields. Updated whenever estimatorState is saved.
  final double totalArea;
  final double totalValue;
  final int buildingCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Estimate({
    required this.id,
    required this.name,
    this.estimatorState = const {},
    this.activeVersionId,
    this.totalArea = 0,
    this.totalValue = 0,
    this.buildingCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  Estimate copyWith({
    String? name,
    Map<String, dynamic>? estimatorState,
    String? activeVersionId,
    double? totalArea,
    double? totalValue,
    int? buildingCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Estimate(
        id: id,
        name: name ?? this.name,
        estimatorState: estimatorState ?? this.estimatorState,
        activeVersionId: activeVersionId ?? this.activeVersionId,
        totalArea: totalArea ?? this.totalArea,
        totalValue: totalValue ?? this.totalValue,
        buildingCount: buildingCount ?? this.buildingCount,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'estimatorState': estimatorState,
        if (activeVersionId != null) 'activeVersionId': activeVersionId,
        'totalArea': totalArea,
        'totalValue': totalValue,
        'buildingCount': buildingCount,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  factory Estimate.fromJson(String id, Map<String, dynamic> json) {
    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      try {
        return (v as dynamic).toDate() as DateTime?;
      } catch (_) {
        return null;
      }
    }

    return Estimate(
      id: id,
      name: (json['name'] as String?) ?? '',
      estimatorState: Map<String, dynamic>.from(
          (json['estimatorState'] as Map?) ?? const {}),
      activeVersionId: json['activeVersionId'] as String?,
      totalArea: (json['totalArea'] as num?)?.toDouble() ?? 0,
      totalValue: (json['totalValue'] as num?)?.toDouble() ?? 0,
      buildingCount: (json['buildingCount'] as num?)?.toInt() ?? 0,
      createdAt: parseTs(json['createdAt']),
      updatedAt: parseTs(json['updatedAt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Estimate &&
          id == other.id &&
          name == other.name &&
          _mapEquals(estimatorState, other.estimatorState) &&
          activeVersionId == other.activeVersionId &&
          totalArea == other.totalArea &&
          totalValue == other.totalValue &&
          buildingCount == other.buildingCount &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        estimatorState.length, // shallow hash — map content compared in ==
        activeVersionId,
        totalArea,
        totalValue,
        buildingCount,
        createdAt,
        updatedAt,
      );
}

/// Deep map equality — avoids importing Flutter's collection utilities.
bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key)) return false;
    final av = a[key];
    final bv = b[key];
    if (av is Map && bv is Map) {
      if (!_mapEquals(
          Map<String, dynamic>.from(av), Map<String, dynamic>.from(bv))) {
        return false;
      }
    } else if (av is List && bv is List) {
      if (av.length != bv.length) return false;
      for (var i = 0; i < av.length; i++) {
        if (av[i] != bv[i]) return false;
      }
    } else if (av != bv) {
      return false;
    }
  }
  return true;
}
