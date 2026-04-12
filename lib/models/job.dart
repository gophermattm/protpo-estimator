/// lib/models/job.dart
///
/// Job entity — the top-level work record that owns estimates and activities.
/// Links to a Customer by ID. Part of the job record feature data layer.

/// Linear workflow states for a job. See design spec section "User decisions"
/// for the rationale behind choosing the simple workflow.
enum JobStatus {
  Lead,
  Quoted,
  Won,
  InProgress,
  Complete,
  Lost,
}

extension JobStatusX on JobStatus {
  /// True for statuses that represent open work. Used by the "Active" filter
  /// chip in the Job List Sheet.
  bool get isActive =>
      this == JobStatus.Lead ||
      this == JobStatus.Quoted ||
      this == JobStatus.Won ||
      this == JobStatus.InProgress;
}

class Job {
  final String id;
  final String customerId;

  /// Denormalized customer name for list-view rendering without a cross-doc
  /// lookup. Kept in sync when the Customer is updated (done in Phase 2).
  final String customerName;

  final String jobName;
  final String siteAddress;
  final String siteZip;
  final JobStatus status;

  /// ID of the estimate that loads by default ("current bid"). Null until
  /// the first estimate is created on the job.
  final String? activeEstimateId;

  /// Reserved for later use. Empty list by default.
  final List<String> tags;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Job({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.jobName,
    this.siteAddress = '',
    this.siteZip = '',
    this.status = JobStatus.Lead,
    this.activeEstimateId,
    this.tags = const [],
    this.createdAt,
    this.updatedAt,
  });

  Job copyWith({
    String? customerId,
    String? customerName,
    String? jobName,
    String? siteAddress,
    String? siteZip,
    JobStatus? status,
    String? activeEstimateId,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Job(
        id: id,
        customerId: customerId ?? this.customerId,
        customerName: customerName ?? this.customerName,
        jobName: jobName ?? this.jobName,
        siteAddress: siteAddress ?? this.siteAddress,
        siteZip: siteZip ?? this.siteZip,
        status: status ?? this.status,
        activeEstimateId: activeEstimateId ?? this.activeEstimateId,
        tags: tags ?? this.tags,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'customerId': customerId,
        'customerName': customerName,
        'jobName': jobName,
        'siteAddress': siteAddress,
        'siteZip': siteZip,
        'status': status.name,
        if (activeEstimateId != null) 'activeEstimateId': activeEstimateId,
        'tags': tags,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  factory Job.fromJson(String id, Map<String, dynamic> json) {
    JobStatus parseStatus(dynamic v) {
      if (v is String) {
        try {
          return JobStatus.values.byName(v);
        } catch (_) {
          return JobStatus.Lead;
        }
      }
      return JobStatus.Lead;
    }

    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      try {
        return (v as dynamic).toDate() as DateTime?;
      } catch (_) {
        return null;
      }
    }

    return Job(
      id: id,
      customerId: (json['customerId'] as String?) ?? '',
      customerName: (json['customerName'] as String?) ?? '',
      jobName: (json['jobName'] as String?) ?? '',
      siteAddress: (json['siteAddress'] as String?) ?? '',
      siteZip: (json['siteZip'] as String?) ?? '',
      status: parseStatus(json['status']),
      activeEstimateId: json['activeEstimateId'] as String?,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      createdAt: parseTs(json['createdAt']),
      updatedAt: parseTs(json['updatedAt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Job &&
          id == other.id &&
          customerId == other.customerId &&
          customerName == other.customerName &&
          jobName == other.jobName &&
          siteAddress == other.siteAddress &&
          siteZip == other.siteZip &&
          status == other.status &&
          activeEstimateId == other.activeEstimateId &&
          _listEquals(tags, other.tags) &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        customerId,
        customerName,
        jobName,
        siteAddress,
        siteZip,
        status,
        activeEstimateId,
        Object.hashAll(tags),
        createdAt,
        updatedAt,
      );
}

/// Lightweight snapshot used by the Job List Sheet for fast render without
/// loading full job documents.
class JobSummary {
  final String id;
  final String jobName;
  final String customerName;
  final String siteAddress;
  final JobStatus status;
  final DateTime? lastActivityAt;

  const JobSummary({
    required this.id,
    required this.jobName,
    required this.customerName,
    required this.siteAddress,
    required this.status,
    required this.lastActivityAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobSummary &&
          id == other.id &&
          jobName == other.jobName &&
          customerName == other.customerName &&
          siteAddress == other.siteAddress &&
          status == other.status &&
          lastActivityAt == other.lastActivityAt;

  @override
  int get hashCode => Object.hash(
        id,
        jobName,
        customerName,
        siteAddress,
        status,
        lastActivityAt,
      );
}

/// Internal helper — Flutter's `listEquals` lives in foundation.dart which
/// pulls Flutter into the pure-Dart model layer. We implement it locally so
/// models stay free of Flutter imports.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
