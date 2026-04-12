/// lib/models/activity.dart
///
/// Activity entity — entries in a job's timeline. Lives as a subcollection:
/// `protpo_jobs/{jobId}/activities/{activityId}`.
///
/// Four types share one document shape. Type-specific fields are nullable
/// and only populated when the type matches.

enum ActivityType {
  note,
  task,
  call,
  system,
}

/// Direction of a logged call. `in_` is used instead of `in` because `in` is
/// a reserved Dart keyword. Serialized as 'in' / 'out' strings in Firestore.
enum CallDirection {
  in_,
  out;

  String get serialized => this == CallDirection.in_ ? 'in' : 'out';

  static CallDirection parse(dynamic v) {
    if (v == 'in') return CallDirection.in_;
    return CallDirection.out;
  }
}

class Activity {
  final String id;
  final ActivityType type;

  /// When the event actually happened. User-settable for backdated entries;
  /// defaults to now at creation time.
  final DateTime timestamp;

  /// Estimator name from the company profile. "system" for auto-generated
  /// system events.
  final String author;

  /// Free text body. Semantics depend on type:
  /// - note: the note content
  /// - task: the task description
  /// - call: the call summary
  /// - system: human-readable event description
  final String body;

  // ── Task-specific ────────────────────────────────────────────────────
  final DateTime? taskDueDate;
  final bool? taskCompleted;
  final DateTime? taskCompletedAt;

  // ── Call-specific ────────────────────────────────────────────────────
  final CallDirection? callDirection;
  final int? callDurationMinutes;

  // ── System-specific ──────────────────────────────────────────────────
  /// One of: 'status_changed', 'version_saved', 'export_created',
  /// 'job_created', 'estimate_created'. See design spec.
  final String? systemEventKind;

  /// Structured payload. Shape depends on eventKind.
  /// E.g. `{ 'from': 'Lead', 'to': 'Quoted' }` for status_changed.
  final Map<String, dynamic>? systemEventData;

  const Activity({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.author,
    required this.body,
    this.taskDueDate,
    this.taskCompleted,
    this.taskCompletedAt,
    this.callDirection,
    this.callDurationMinutes,
    this.systemEventKind,
    this.systemEventData,
  });

  Activity copyWith({
    DateTime? timestamp,
    String? author,
    String? body,
    DateTime? taskDueDate,
    bool? taskCompleted,
    DateTime? taskCompletedAt,
    CallDirection? callDirection,
    int? callDurationMinutes,
    String? systemEventKind,
    Map<String, dynamic>? systemEventData,
  }) =>
      Activity(
        id: id,
        type: type,
        timestamp: timestamp ?? this.timestamp,
        author: author ?? this.author,
        body: body ?? this.body,
        taskDueDate: taskDueDate ?? this.taskDueDate,
        taskCompleted: taskCompleted ?? this.taskCompleted,
        taskCompletedAt: taskCompletedAt ?? this.taskCompletedAt,
        callDirection: callDirection ?? this.callDirection,
        callDurationMinutes: callDurationMinutes ?? this.callDurationMinutes,
        systemEventKind: systemEventKind ?? this.systemEventKind,
        systemEventData: systemEventData ?? this.systemEventData,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'author': author,
        'body': body,
        if (taskDueDate != null)
          'taskDueDate': taskDueDate!.toIso8601String(),
        if (taskCompleted != null) 'taskCompleted': taskCompleted,
        if (taskCompletedAt != null)
          'taskCompletedAt': taskCompletedAt!.toIso8601String(),
        if (callDirection != null) 'callDirection': callDirection!.serialized,
        if (callDurationMinutes != null)
          'callDurationMinutes': callDurationMinutes,
        if (systemEventKind != null) 'systemEventKind': systemEventKind,
        if (systemEventData != null) 'systemEventData': systemEventData,
      };

  factory Activity.fromJson(String id, Map<String, dynamic> json) {
    ActivityType parseType(dynamic v) {
      if (v is String) {
        try {
          return ActivityType.values.byName(v);
        } catch (_) {
          return ActivityType.note;
        }
      }
      return ActivityType.note;
    }

    DateTime parseTs(dynamic v) {
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      try {
        return (v as dynamic).toDate() as DateTime;
      } catch (_) {
        return DateTime.now();
      }
    }

    DateTime? parseOptionalTs(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      try {
        return (v as dynamic).toDate() as DateTime?;
      } catch (_) {
        return null;
      }
    }

    return Activity(
      id: id,
      type: parseType(json['type']),
      timestamp: parseTs(json['timestamp']),
      author: (json['author'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      taskDueDate: parseOptionalTs(json['taskDueDate']),
      taskCompleted: json['taskCompleted'] as bool?,
      taskCompletedAt: parseOptionalTs(json['taskCompletedAt']),
      callDirection: json['callDirection'] != null
          ? CallDirection.parse(json['callDirection'])
          : null,
      callDurationMinutes: (json['callDurationMinutes'] as num?)?.toInt(),
      systemEventKind: json['systemEventKind'] as String?,
      systemEventData: json['systemEventData'] == null
          ? null
          : Map<String, dynamic>.from(json['systemEventData'] as Map),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Activity &&
          id == other.id &&
          type == other.type &&
          timestamp == other.timestamp &&
          author == other.author &&
          body == other.body &&
          taskDueDate == other.taskDueDate &&
          taskCompleted == other.taskCompleted &&
          taskCompletedAt == other.taskCompletedAt &&
          callDirection == other.callDirection &&
          callDurationMinutes == other.callDurationMinutes &&
          systemEventKind == other.systemEventKind &&
          _mapEquals(systemEventData, other.systemEventData);

  @override
  int get hashCode => Object.hash(
        id,
        type,
        timestamp,
        author,
        body,
        taskDueDate,
        taskCompleted,
        taskCompletedAt,
        callDirection,
        callDurationMinutes,
        systemEventKind,
        systemEventData?.length,
      );
}

bool _mapEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key)) return false;
    if (a[key] != b[key]) return false;
  }
  return true;
}
