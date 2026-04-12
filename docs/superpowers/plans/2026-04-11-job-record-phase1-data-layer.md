# Job Record Phase 1 — Data Layer Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the data layer (models, serializers, Firestore CRUD, security rules) for the job record feature without any UI changes. This is an internal-only milestone (M0 groundwork) per `docs/superpowers/specs/2026-04-11-job-record-design.md`.

**Architecture:** Five new immutable Dart model classes (`Customer`, `Job`, `Estimate`, `EstimateVersion`, `Activity`) in `lib/models/`, each with `const` constructors, `copyWith`, `toJson`/`fromJson`, and value equality. Enum types co-located with their owning model. `FirestoreService` extended with CRUD methods for each collection and subcollection. Firestore security rules updated and deployed.

**Tech Stack:** Dart 3.x, Flutter 3.35+, Riverpod (no provider changes yet), cloud_firestore (existing). No new dependencies. Tests are pure-Dart model serialization round-trips — no Firestore emulator, no mock libraries.

**No user-visible changes.** The estimator screen, save/load flow, project list screen, and existing BOM pipeline are untouched. Phase 1 only adds inert code + deploys rules. The new rules are backward-compatible (they add new collection matches; existing rules unchanged).

---

## File Structure

### Files to create

| Path | Responsibility |
|---|---|
| `lib/models/customer.dart` | `CustomerType` enum + immutable `Customer` class with toJson/fromJson/copyWith/==/hashCode |
| `lib/models/job.dart` | `JobStatus` enum + immutable `Job` class + `JobSummary` lightweight list-view model |
| `lib/models/estimate.dart` | Immutable `Estimate` class carrying the mutable draft EstimatorState as `Map<String, dynamic>` |
| `lib/models/estimate_version.dart` | `VersionSource` enum + immutable `EstimateVersion` class carrying a frozen EstimatorState snapshot |
| `lib/models/activity.dart` | `ActivityType` + `CallDirection` + `SystemEventKind` enums + immutable `Activity` class |
| `test/models/customer_test.dart` | Round-trip, defaults, equality tests for Customer |
| `test/models/job_test.dart` | Round-trip, defaults, equality tests for Job + JobSummary |
| `test/models/estimate_test.dart` | Round-trip, defaults, equality tests for Estimate |
| `test/models/estimate_version_test.dart` | Round-trip, equality tests for EstimateVersion |
| `test/models/activity_test.dart` | Round-trip, enum parsing, type-specific field handling for Activity |

### Files to modify

| Path | Change |
|---|---|
| `lib/services/firestore_service.dart` | Add collection name constants + CRUD methods for customers, jobs, estimates (subcoll), versions (subcoll), activities (subcoll). Add cascading delete helper. |
| `firestore.rules` | Append match blocks for `protpo_customers`, `protpo_jobs` + nested `estimates`, `versions`, `activities`. Existing rules untouched. |

### Files NOT touched in Phase 1

- `lib/screens/estimator_screen.dart` — stays on old save path
- `lib/screens/project_list_screen.dart` — still the entry for Open
- `lib/providers/estimator_providers.dart` — no new providers yet (comes in Phase 2)
- `lib/widgets/settings_dialog.dart` — no new Customers tab yet (Phase 3)
- `lib/services/export_service.dart` — export flow unchanged
- Any BOM, R-value, or renderer files

---

## Task 1: Customer model and tests

**Files:**
- Create: `lib/models/customer.dart`
- Create: `test/models/customer_test.dart`

### Step 1.1 — Write the failing test

- [ ] **Create `test/models/customer_test.dart`:**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/customer.dart';

void main() {
  group('CustomerType enum', () {
    test('parses known string values via byName', () {
      expect(CustomerType.values.byName('Company'), CustomerType.Company);
      expect(CustomerType.values.byName('InsuranceCarrier'),
          CustomerType.InsuranceCarrier);
      expect(CustomerType.values.byName('PropertyManager'),
          CustomerType.PropertyManager);
      expect(CustomerType.values.byName('GeneralContractor'),
          CustomerType.GeneralContractor);
      expect(CustomerType.values.byName('Individual'),
          CustomerType.Individual);
    });
  });

  group('Customer', () {
    test('construct with defaults', () {
      final c = Customer(id: 'cust-1', name: 'Acme Properties');
      expect(c.id, 'cust-1');
      expect(c.name, 'Acme Properties');
      expect(c.customerType, CustomerType.Company);
      expect(c.primaryContactName, '');
      expect(c.phone, '');
      expect(c.email, '');
      expect(c.mailingAddress, '');
      expect(c.notes, '');
      expect(c.createdAt, isNull);
      expect(c.updatedAt, isNull);
    });

    test('toJson and fromJson round-trip preserves all fields', () {
      final original = Customer(
        id: 'cust-42',
        name: 'Property Management LLC',
        customerType: CustomerType.PropertyManager,
        primaryContactName: 'Jane Smith',
        phone: '(913) 555-0123',
        email: 'jane@propmgmt.com',
        mailingAddress: '123 Main St, Overland Park KS 66210',
        notes: 'Prefers Tuesday calls. Net-30 terms.',
        createdAt: DateTime.utc(2026, 4, 11, 9, 0),
        updatedAt: DateTime.utc(2026, 4, 11, 9, 15),
      );
      final json = original.toJson();
      final restored = Customer.fromJson('cust-42', json);
      expect(restored, original);
    });

    test('fromJson tolerates missing optional fields', () {
      final c = Customer.fromJson('cust-x', {
        'name': 'Solo Owner',
        'customerType': 'Individual',
      });
      expect(c.name, 'Solo Owner');
      expect(c.customerType, CustomerType.Individual);
      expect(c.primaryContactName, '');
      expect(c.phone, '');
      expect(c.createdAt, isNull);
    });

    test('fromJson defaults customerType to Company when missing or unknown', () {
      final missing = Customer.fromJson('cust-m', {'name': 'No Type'});
      expect(missing.customerType, CustomerType.Company);

      final unknown = Customer.fromJson('cust-u', {
        'name': 'Garbage Type',
        'customerType': 'NotARealEnumValue',
      });
      expect(unknown.customerType, CustomerType.Company);
    });

    test('copyWith replaces only specified fields', () {
      final c = Customer(id: 'cust-1', name: 'Old Name');
      final updated = c.copyWith(name: 'New Name', phone: '555-1234');
      expect(updated.id, 'cust-1');
      expect(updated.name, 'New Name');
      expect(updated.phone, '555-1234');
      expect(updated.customerType, CustomerType.Company);
    });

    test('equality: two identical customers are equal and hash the same', () {
      final a = Customer(id: 'cust-1', name: 'Same', phone: '555');
      final b = Customer(id: 'cust-1', name: 'Same', phone: '555');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equality: different ids are not equal', () {
      final a = Customer(id: 'cust-1', name: 'Same');
      final b = Customer(id: 'cust-2', name: 'Same');
      expect(a, isNot(equals(b)));
    });
  });
}
```

### Step 1.2 — Run test to verify it fails

- [ ] **Run:** `flutter test test/models/customer_test.dart`

Expected: FAIL with "Target of URI doesn't exist: 'package:protpo_app/models/customer.dart'" or similar.

### Step 1.3 — Create the Customer model

- [ ] **Create `lib/models/customer.dart`:**

```dart
/// lib/models/customer.dart
///
/// Customer entity for the ProTPO job record feature.
/// A customer can be referenced by many jobs (see models/job.dart).

/// Type of customer relationship.
/// Stored by enum name in Firestore (e.g. 'Company', 'InsuranceCarrier').
enum CustomerType {
  Company,
  InsuranceCarrier,
  PropertyManager,
  GeneralContractor,
  Individual,
}

class Customer {
  /// Document ID in `protpo_customers`. Generated client-side (UUID v4).
  final String id;

  /// Company name or individual name. Required for display.
  final String name;

  /// Customer relationship type. Defaults to Company.
  final CustomerType customerType;

  /// Main point-of-contact at the customer. Optional.
  final String primaryContactName;

  /// Phone, email, mailing address are optional free-form strings.
  final String phone;
  final String email;
  final String mailingAddress;

  /// Free-text notes (preferred POC, payment terms, etc.). Optional.
  final String notes;

  /// Server-set timestamps. Null until the customer has been written to
  /// Firestore at least once.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Customer({
    required this.id,
    required this.name,
    this.customerType = CustomerType.Company,
    this.primaryContactName = '',
    this.phone = '',
    this.email = '',
    this.mailingAddress = '',
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  Customer copyWith({
    String? name,
    CustomerType? customerType,
    String? primaryContactName,
    String? phone,
    String? email,
    String? mailingAddress,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Customer(
        id: id,
        name: name ?? this.name,
        customerType: customerType ?? this.customerType,
        primaryContactName: primaryContactName ?? this.primaryContactName,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        mailingAddress: mailingAddress ?? this.mailingAddress,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'customerType': customerType.name,
        'primaryContactName': primaryContactName,
        'phone': phone,
        'email': email,
        'mailingAddress': mailingAddress,
        'notes': notes,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  factory Customer.fromJson(String id, Map<String, dynamic> json) {
    CustomerType parseType(dynamic v) {
      if (v is String) {
        try {
          return CustomerType.values.byName(v);
        } catch (_) {
          return CustomerType.Company;
        }
      }
      return CustomerType.Company;
    }

    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      // Firestore Timestamps arrive as Timestamp objects with toDate();
      // handled via dynamic to avoid importing cloud_firestore in the model.
      try {
        return (v as dynamic).toDate() as DateTime?;
      } catch (_) {
        return null;
      }
    }

    return Customer(
      id: id,
      name: (json['name'] as String?) ?? '',
      customerType: parseType(json['customerType']),
      primaryContactName: (json['primaryContactName'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      mailingAddress: (json['mailingAddress'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      createdAt: parseTs(json['createdAt']),
      updatedAt: parseTs(json['updatedAt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Customer &&
          id == other.id &&
          name == other.name &&
          customerType == other.customerType &&
          primaryContactName == other.primaryContactName &&
          phone == other.phone &&
          email == other.email &&
          mailingAddress == other.mailingAddress &&
          notes == other.notes &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        customerType,
        primaryContactName,
        phone,
        email,
        mailingAddress,
        notes,
        createdAt,
        updatedAt,
      );
}
```

### Step 1.4 — Run test to verify it passes

- [ ] **Run:** `flutter test test/models/customer_test.dart`

Expected: All 7 tests pass. If the round-trip test fails on `updatedAt`, verify `toJson` emits ISO strings and `fromJson` parses them (it does).

### Step 1.5 — Commit

- [ ] **Run:**

```bash
git add lib/models/customer.dart test/models/customer_test.dart
git commit -m "feat(models): add Customer entity for job record feature

Immutable model with CustomerType enum, toJson/fromJson, copyWith,
and value equality. Part of Phase 1 data layer for the job record
spec at docs/superpowers/specs/2026-04-11-job-record-design.md.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Job model and tests

**Files:**
- Create: `lib/models/job.dart`
- Create: `test/models/job_test.dart`

### Step 2.1 — Write the failing test

- [ ] **Create `test/models/job_test.dart`:**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/job.dart';

void main() {
  group('JobStatus enum', () {
    test('contains all six workflow states', () {
      expect(JobStatus.values.length, 6);
      expect(JobStatus.values, contains(JobStatus.Lead));
      expect(JobStatus.values, contains(JobStatus.Quoted));
      expect(JobStatus.values, contains(JobStatus.Won));
      expect(JobStatus.values, contains(JobStatus.InProgress));
      expect(JobStatus.values, contains(JobStatus.Complete));
      expect(JobStatus.values, contains(JobStatus.Lost));
    });

    test('isActive returns true for Lead, Quoted, Won, InProgress', () {
      expect(JobStatus.Lead.isActive, isTrue);
      expect(JobStatus.Quoted.isActive, isTrue);
      expect(JobStatus.Won.isActive, isTrue);
      expect(JobStatus.InProgress.isActive, isTrue);
      expect(JobStatus.Complete.isActive, isFalse);
      expect(JobStatus.Lost.isActive, isFalse);
    });
  });

  group('Job', () {
    test('construct with defaults', () {
      final j = Job(
        id: 'job-1',
        customerId: 'cust-1',
        customerName: 'Acme',
        jobName: 'Building A TPO',
      );
      expect(j.status, JobStatus.Lead);
      expect(j.activeEstimateId, isNull);
      expect(j.tags, isEmpty);
      expect(j.siteAddress, '');
      expect(j.siteZip, '');
    });

    test('toJson and fromJson round-trip preserves all fields', () {
      final original = Job(
        id: 'job-42',
        customerId: 'cust-7',
        customerName: 'Property Mgmt LLC',
        jobName: 'Warehouse Re-Roof',
        siteAddress: '4500 Industrial Blvd, Lenexa KS',
        siteZip: '66215',
        status: JobStatus.Quoted,
        activeEstimateId: 'est-abc',
        tags: ['insurance', 'hail-2026'],
        createdAt: DateTime.utc(2026, 4, 11),
        updatedAt: DateTime.utc(2026, 4, 11, 12),
      );
      final json = original.toJson();
      final restored = Job.fromJson('job-42', json);
      expect(restored, original);
    });

    test('fromJson defaults status to Lead when missing or unknown', () {
      final missing = Job.fromJson('job-m', {
        'customerId': 'c',
        'customerName': 'c',
        'jobName': 'j',
      });
      expect(missing.status, JobStatus.Lead);

      final unknown = Job.fromJson('job-u', {
        'customerId': 'c',
        'customerName': 'c',
        'jobName': 'j',
        'status': 'NotReal',
      });
      expect(unknown.status, JobStatus.Lead);
    });

    test('copyWith replaces status and activeEstimateId', () {
      final j = Job(
        id: 'job-1',
        customerId: 'c',
        customerName: 'c',
        jobName: 'j',
      );
      final u = j.copyWith(
        status: JobStatus.Won,
        activeEstimateId: 'est-new',
      );
      expect(u.status, JobStatus.Won);
      expect(u.activeEstimateId, 'est-new');
      expect(u.jobName, 'j');
    });

    test('equality: identical jobs are equal', () {
      final a = Job(
        id: 'job-1',
        customerId: 'c',
        customerName: 'c',
        jobName: 'j',
      );
      final b = Job(
        id: 'job-1',
        customerId: 'c',
        customerName: 'c',
        jobName: 'j',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('JobSummary', () {
    test('construct and equality', () {
      final a = JobSummary(
        id: 'job-1',
        jobName: 'Name',
        customerName: 'Customer',
        siteAddress: 'Addr',
        status: JobStatus.Lead,
        lastActivityAt: DateTime.utc(2026, 4, 11),
      );
      final b = JobSummary(
        id: 'job-1',
        jobName: 'Name',
        customerName: 'Customer',
        siteAddress: 'Addr',
        status: JobStatus.Lead,
        lastActivityAt: DateTime.utc(2026, 4, 11),
      );
      expect(a, equals(b));
    });
  });
}
```

### Step 2.2 — Run test to verify it fails

- [ ] **Run:** `flutter test test/models/job_test.dart`

Expected: FAIL with import error.

### Step 2.3 — Create the Job model

- [ ] **Create `lib/models/job.dart`:**

```dart
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
```

### Step 2.4 — Run test to verify it passes

- [ ] **Run:** `flutter test test/models/job_test.dart`

Expected: All tests pass.

### Step 2.5 — Commit

- [ ] **Run:**

```bash
git add lib/models/job.dart test/models/job_test.dart
git commit -m "feat(models): add Job and JobSummary models with JobStatus enum

Includes isActive extension for filter chip logic. JobSummary is the
lightweight list-view projection used by the Job List Sheet. Part of
Phase 1 data layer.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Estimate model and tests

**Files:**
- Create: `lib/models/estimate.dart`
- Create: `test/models/estimate_test.dart`

### Step 3.1 — Write the failing test

- [ ] **Create `test/models/estimate_test.dart`:**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/estimate.dart';

void main() {
  group('Estimate', () {
    test('construct with defaults', () {
      final e = Estimate(
        id: 'est-1',
        name: 'TPO Original Bid',
      );
      expect(e.id, 'est-1');
      expect(e.name, 'TPO Original Bid');
      expect(e.estimatorState, isEmpty);
      expect(e.activeVersionId, isNull);
      expect(e.totalArea, 0);
      expect(e.totalValue, 0);
      expect(e.buildingCount, 0);
    });

    test('toJson and fromJson round-trip preserves estimatorState map', () {
      // estimatorState is an opaque map — we only verify it round-trips,
      // not that it follows any specific schema. That's the job of
      // serialization.dart when Phase 2 hydrates the estimator.
      final state = {
        'schemaVersion': 2,
        'projectInfo': {'projectName': 'Test', 'zipCode': '66210'},
        'buildings': [
          {'id': 'b1', 'buildingName': 'Main'}
        ],
      };
      final original = Estimate(
        id: 'est-42',
        name: 'PVC Alternate',
        estimatorState: state,
        activeVersionId: 'ver-abc',
        totalArea: 12500.0,
        totalValue: 87500.50,
        buildingCount: 2,
        createdAt: DateTime.utc(2026, 4, 11),
        updatedAt: DateTime.utc(2026, 4, 11, 13),
      );
      final json = original.toJson();
      final restored = Estimate.fromJson('est-42', json);
      expect(restored.id, 'est-42');
      expect(restored.name, 'PVC Alternate');
      expect(restored.estimatorState, state);
      expect(restored.activeVersionId, 'ver-abc');
      expect(restored.totalArea, 12500.0);
      expect(restored.totalValue, 87500.50);
      expect(restored.buildingCount, 2);
      expect(restored.createdAt, DateTime.utc(2026, 4, 11));
      expect(restored.updatedAt, DateTime.utc(2026, 4, 11, 13));
    });

    test('copyWith replaces estimatorState and denormalized fields', () {
      final e = Estimate(id: 'est-1', name: 'Bid');
      final u = e.copyWith(
        estimatorState: {'hello': 'world'},
        totalArea: 5000,
        buildingCount: 1,
      );
      expect(u.estimatorState, {'hello': 'world'});
      expect(u.totalArea, 5000);
      expect(u.buildingCount, 1);
      expect(u.name, 'Bid');
    });

    test('equality: identical estimates are equal', () {
      final a = Estimate(id: 'est-1', name: 'A', buildingCount: 1);
      final b = Estimate(id: 'est-1', name: 'A', buildingCount: 1);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
```

### Step 3.2 — Run test to verify it fails

- [ ] **Run:** `flutter test test/models/estimate_test.dart`

Expected: FAIL with import error.

### Step 3.3 — Create the Estimate model

- [ ] **Create `lib/models/estimate.dart`:**

```dart
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
```

### Step 3.4 — Run test to verify it passes

- [ ] **Run:** `flutter test test/models/estimate_test.dart`

Expected: All tests pass.

### Step 3.5 — Commit

- [ ] **Run:**

```bash
git add lib/models/estimate.dart test/models/estimate_test.dart
git commit -m "feat(models): add Estimate model carrying mutable draft state

estimatorState is an opaque Map<String, dynamic> — its schema is owned
by lib/services/serialization.dart. The model carries denormalized
totalArea/totalValue/buildingCount for fast list rendering.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: EstimateVersion model and tests

**Files:**
- Create: `lib/models/estimate_version.dart`
- Create: `test/models/estimate_version_test.dart`

### Step 4.1 — Write the failing test

- [ ] **Create `test/models/estimate_version_test.dart`:**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/estimate_version.dart';

void main() {
  group('VersionSource enum', () {
    test('parses manual and export', () {
      expect(VersionSource.values.byName('manual'), VersionSource.manual);
      expect(VersionSource.values.byName('export'), VersionSource.export);
    });
  });

  group('EstimateVersion', () {
    test('construct with required fields', () {
      final v = EstimateVersion(
        id: 'ver-1',
        label: 'v1 — initial',
        source: VersionSource.manual,
        estimatorState: const {},
        createdAt: DateTime.utc(2026, 4, 11),
        createdBy: 'Matt Moore',
      );
      expect(v.id, 'ver-1');
      expect(v.source, VersionSource.manual);
    });

    test('toJson and fromJson round-trip', () {
      final v = EstimateVersion(
        id: 'ver-42',
        label: 'Export 2026-04-11 14:32',
        source: VersionSource.export,
        estimatorState: {
          'schemaVersion': 2,
          'projectInfo': {'projectName': 'Test'},
        },
        createdAt: DateTime.utc(2026, 4, 11, 14, 32),
        createdBy: 'Matt Moore',
      );
      final json = v.toJson();
      final restored = EstimateVersion.fromJson('ver-42', json);
      expect(restored.id, 'ver-42');
      expect(restored.label, 'Export 2026-04-11 14:32');
      expect(restored.source, VersionSource.export);
      expect(restored.estimatorState['schemaVersion'], 2);
      expect(restored.createdAt, DateTime.utc(2026, 4, 11, 14, 32));
      expect(restored.createdBy, 'Matt Moore');
    });

    test('fromJson defaults source to manual when unknown', () {
      final v = EstimateVersion.fromJson('ver-x', {
        'label': 'Unknown source',
        'source': 'garbage',
        'estimatorState': {},
        'createdAt': '2026-04-11T00:00:00.000Z',
        'createdBy': 'Matt',
      });
      expect(v.source, VersionSource.manual);
    });

    test('equality: identical versions are equal', () {
      final a = EstimateVersion(
        id: 'ver-1',
        label: 'v1',
        source: VersionSource.manual,
        estimatorState: const {},
        createdAt: DateTime.utc(2026, 4, 11),
        createdBy: 'Matt',
      );
      final b = EstimateVersion(
        id: 'ver-1',
        label: 'v1',
        source: VersionSource.manual,
        estimatorState: const {},
        createdAt: DateTime.utc(2026, 4, 11),
        createdBy: 'Matt',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
```

### Step 4.2 — Run test to verify it fails

- [ ] **Run:** `flutter test test/models/estimate_version_test.dart`

Expected: FAIL with import error.

### Step 4.3 — Create the EstimateVersion model

- [ ] **Create `lib/models/estimate_version.dart`:**

```dart
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
```

### Step 4.4 — Run test to verify it passes

- [ ] **Run:** `flutter test test/models/estimate_version_test.dart`

Expected: All tests pass.

### Step 4.5 — Commit

- [ ] **Run:**

```bash
git add lib/models/estimate_version.dart test/models/estimate_version_test.dart
git commit -m "feat(models): add EstimateVersion frozen snapshot model

Versions are immutable by design — Firestore rules will reject updates
in a later task in this plan.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Activity model and tests

**Files:**
- Create: `lib/models/activity.dart`
- Create: `test/models/activity_test.dart`

### Step 5.1 — Write the failing test

- [ ] **Create `test/models/activity_test.dart`:**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/activity.dart';

void main() {
  group('enums', () {
    test('ActivityType parses known values', () {
      expect(ActivityType.values.byName('note'), ActivityType.note);
      expect(ActivityType.values.byName('task'), ActivityType.task);
      expect(ActivityType.values.byName('call'), ActivityType.call);
      expect(ActivityType.values.byName('system'), ActivityType.system);
    });

    test('CallDirection parses in/out', () {
      expect(CallDirection.values.byName('in'), CallDirection.in_);
      expect(CallDirection.values.byName('out'), CallDirection.out);
    },
        // Dart won't let us name a value `in` because it's reserved.
        // We alias as `in_` and serialize as 'in'. See model below.
        skip: true);

    test('CallDirection.serialized returns in/out strings', () {
      expect(CallDirection.in_.serialized, 'in');
      expect(CallDirection.out.serialized, 'out');
    });

    test('CallDirection.parse handles in/out and defaults to out', () {
      expect(CallDirection.parse('in'), CallDirection.in_);
      expect(CallDirection.parse('out'), CallDirection.out);
      expect(CallDirection.parse('garbage'), CallDirection.out);
      expect(CallDirection.parse(null), CallDirection.out);
    });
  });

  group('Activity — note', () {
    test('construct a note activity', () {
      final a = Activity(
        id: 'act-1',
        type: ActivityType.note,
        timestamp: DateTime.utc(2026, 4, 11, 10, 0),
        author: 'Matt',
        body: 'Owner prefers fully-adhered system.',
      );
      expect(a.type, ActivityType.note);
      expect(a.body, 'Owner prefers fully-adhered system.');
      expect(a.taskDueDate, isNull);
      expect(a.callDirection, isNull);
      expect(a.systemEventKind, isNull);
    });

    test('note round-trip', () {
      final a = Activity(
        id: 'act-1',
        type: ActivityType.note,
        timestamp: DateTime.utc(2026, 4, 11),
        author: 'Matt',
        body: 'Test note',
      );
      final restored = Activity.fromJson('act-1', a.toJson());
      expect(restored, a);
    });
  });

  group('Activity — task', () {
    test('construct a task with due date', () {
      final a = Activity(
        id: 'act-2',
        type: ActivityType.task,
        timestamp: DateTime.utc(2026, 4, 11),
        author: 'Matt',
        body: 'Call adjuster',
        taskDueDate: DateTime.utc(2026, 4, 15),
        taskCompleted: false,
      );
      expect(a.type, ActivityType.task);
      expect(a.taskDueDate, DateTime.utc(2026, 4, 15));
      expect(a.taskCompleted, isFalse);
      expect(a.taskCompletedAt, isNull);
    });

    test('task round-trip with completion', () {
      final a = Activity(
        id: 'act-2',
        type: ActivityType.task,
        timestamp: DateTime.utc(2026, 4, 11),
        author: 'Matt',
        body: 'Call adjuster',
        taskDueDate: DateTime.utc(2026, 4, 15),
        taskCompleted: true,
        taskCompletedAt: DateTime.utc(2026, 4, 14),
      );
      final restored = Activity.fromJson('act-2', a.toJson());
      expect(restored, a);
    });
  });

  group('Activity — call', () {
    test('construct a call with direction and duration', () {
      final a = Activity(
        id: 'act-3',
        type: ActivityType.call,
        timestamp: DateTime.utc(2026, 4, 11, 14),
        author: 'Matt',
        body: 'Discussed pricing',
        callDirection: CallDirection.out,
        callDurationMinutes: 12,
      );
      expect(a.callDirection, CallDirection.out);
      expect(a.callDurationMinutes, 12);
    });

    test('call round-trip', () {
      final a = Activity(
        id: 'act-3',
        type: ActivityType.call,
        timestamp: DateTime.utc(2026, 4, 11, 14),
        author: 'Matt',
        body: 'Discussed pricing',
        callDirection: CallDirection.in_,
        callDurationMinutes: 7,
      );
      final restored = Activity.fromJson('act-3', a.toJson());
      expect(restored.callDirection, CallDirection.in_);
      expect(restored.callDurationMinutes, 7);
    });
  });

  group('Activity — system', () {
    test('construct a system event with structured data', () {
      final a = Activity(
        id: 'act-4',
        type: ActivityType.system,
        timestamp: DateTime.utc(2026, 4, 11),
        author: 'system',
        body: 'Status changed from Lead to Quoted',
        systemEventKind: 'status_changed',
        systemEventData: {'from': 'Lead', 'to': 'Quoted'},
      );
      expect(a.systemEventKind, 'status_changed');
      expect(a.systemEventData, {'from': 'Lead', 'to': 'Quoted'});
    });

    test('system event round-trip', () {
      final a = Activity(
        id: 'act-4',
        type: ActivityType.system,
        timestamp: DateTime.utc(2026, 4, 11),
        author: 'system',
        body: 'Version saved',
        systemEventKind: 'version_saved',
        systemEventData: {'versionId': 'ver-xyz', 'label': 'v2'},
      );
      final restored = Activity.fromJson('act-4', a.toJson());
      expect(restored, a);
    });
  });
}
```

### Step 5.2 — Run test to verify it fails

- [ ] **Run:** `flutter test test/models/activity_test.dart`

Expected: FAIL with import error.

### Step 5.3 — Create the Activity model

- [ ] **Create `lib/models/activity.dart`:**

```dart
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
```

### Step 5.4 — Run test to verify it passes

- [ ] **Run:** `flutter test test/models/activity_test.dart`

Expected: All tests pass.

### Step 5.5 — Commit

- [ ] **Run:**

```bash
git add lib/models/activity.dart test/models/activity_test.dart
git commit -m "feat(models): add Activity model for job timeline entries

One document shape covers note/task/call/system types with nullable
type-specific fields. CallDirection uses in_ to avoid the 'in' Dart
keyword and serializes as 'in'/'out' strings.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Extend FirestoreService with job record CRUD

**Files:**
- Modify: `lib/services/firestore_service.dart` (append new methods to the existing class — do not refactor the existing code)

FirestoreService is a thin wrapper over the Firestore SDK. We do NOT write unit tests for these methods because testing them without a real or emulated Firestore is just asserting that we called the SDK. Integration validation comes later (manual smoke test at the end of this task, plus the Phase 9 integration test in the spec).

### Step 6.1 — Add collection name constants and imports

- [ ] **Edit `lib/services/firestore_service.dart`.** Find the existing `import` block at the top and the existing class-level constants. Add the new imports and constants:

Find the existing imports:
```dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/estimator_state.dart';
import 'serialization.dart';
```

Add these imports immediately after:
```dart
import '../models/customer.dart';
import '../models/job.dart';
import '../models/estimate.dart';
import '../models/estimate_version.dart';
import '../models/activity.dart';
```

Find the existing constant `_colName`:
```dart
final _colName  = 'protpo_projects';
```

Add these constants immediately after:
```dart
static const _customersCol = 'protpo_customers';
static const _jobsCol = 'protpo_jobs';
static const _estimatesSubcol = 'estimates';
static const _versionsSubcol = 'versions';
static const _activitiesSubcol = 'activities';
```

### Step 6.2 — Add customer CRUD methods

- [ ] **Append the following methods to the `FirestoreService` class** (just before the final closing `}`):

```dart
// ═══════════════════════════════════════════════════════════════════════
// CUSTOMERS
// ═══════════════════════════════════════════════════════════════════════

CollectionReference<Map<String, dynamic>> get _customers =>
    _db.collection(_customersCol);

/// Creates a new customer. Returns the generated ID.
Future<String> createCustomer(Customer c) async {
  final id = c.id.isNotEmpty ? c.id : _uuid.v4();
  await _customers.doc(id).set({
    ...c.toJson(),
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  return id;
}

/// Updates an existing customer.
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
```

### Step 6.3 — Add job CRUD methods

- [ ] **Append the following methods directly after the customer methods:**

```dart
// ═══════════════════════════════════════════════════════════════════════
// JOBS
// ═══════════════════════════════════════════════════════════════════════

CollectionReference<Map<String, dynamic>> get _jobs =>
    _db.collection(_jobsCol);

/// Creates a job with server-set timestamps. Returns the generated ID.
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

/// Deletes a job and cascades to its subcollections (estimates, versions,
/// activities). Firestore does not cascade automatically — this helper
/// deletes children explicitly in batches.
Future<void> deleteJobCascade(String jobId) async {
  final jobRef = _jobs.doc(jobId);

  // Delete all estimates (and their versions subcollection)
  final estimates = await jobRef.collection(_estimatesSubcol).get();
  for (final est in estimates.docs) {
    final versions = await est.reference.collection(_versionsSubcol).get();
    for (final v in versions.docs) {
      await v.reference.delete();
    }
    await est.reference.delete();
  }

  // Delete all activities
  final activities = await jobRef.collection(_activitiesSubcol).get();
  for (final a in activities.docs) {
    await a.reference.delete();
  }

  // Finally delete the job doc itself
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
```

### Step 6.4 — Add estimate subcollection CRUD

- [ ] **Append the following methods directly after the job methods:**

```dart
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

/// Writes the full estimate document (including the mutable draft state).
/// Called by the estimator's autosave path in Phase 2 — Phase 1 just
/// provides the method signature.
Future<void> updateEstimate(String jobId, Estimate e) async {
  await _estimates(jobId).doc(e.id).set({
    ...e.toJson(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> deleteEstimate(String jobId, String estimateId) async {
  final estRef = _estimates(jobId).doc(estimateId);
  // Delete versions subcollection first
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
```

### Step 6.5 — Add version subcollection CRUD (append-only)

- [ ] **Append the following methods directly after the estimate methods:**

```dart
// ═══════════════════════════════════════════════════════════════════════
// VERSIONS (subcollection of estimates, append-only)
// ═══════════════════════════════════════════════════════════════════════

CollectionReference<Map<String, dynamic>> _versions(
        String jobId, String estimateId) =>
    _estimates(jobId).doc(estimateId).collection(_versionsSubcol);

/// Writes a frozen version snapshot. Versions are immutable — Firestore
/// rules reject updates (see firestore.rules). Returns the generated ID.
Future<String> createVersion(
    String jobId, String estimateId, EstimateVersion v) async {
  final id = v.id.isNotEmpty ? v.id : _uuid.v4();
  await _versions(jobId, estimateId).doc(id).set({
    ...v.toJson(),
    // Server timestamp for createdAt so ordering is consistent even if
    // client clocks drift.
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
```

### Step 6.6 — Add activity subcollection CRUD

- [ ] **Append the following methods directly after the version methods:**

```dart
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

/// Only task activities support updates (the completion toggle).
/// Firestore rules enforce this at the server side.
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
```

### Step 6.7 — Verify firestore_service.dart compiles

- [ ] **Run:** `flutter analyze lib/services/firestore_service.dart`

Expected: `No issues found!`

If there are warnings about unused imports (e.g., `dart:convert` if you accidentally removed code that used it), leave them — we're only adding, not removing.

### Step 6.8 — Verify the whole project still analyzes cleanly

- [ ] **Run:** `flutter analyze lib/`

Expected: The same set of pre-existing analyzer warnings as before, **no new errors** introduced by Phase 1. If there are new errors, fix them before committing. The most likely issues are missing semicolons or mismatched braces at the method insertion points.

### Step 6.9 — Commit

- [ ] **Run:**

```bash
git add lib/services/firestore_service.dart
git commit -m "feat(services): add FirestoreService CRUD for job record entities

Adds methods for customers, jobs, estimates (subcoll), versions
(subcoll, append-only), and activities (subcoll, task-only updates).
Thin wrappers over cloud_firestore SDK — unit tests skipped in
Phase 1; manual smoke test at end of task plus integration test
in Phase 9 per spec.

Includes deleteJobCascade helper for cleaning up subcollections
since Firestore does not cascade automatically.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Update Firestore security rules

**Files:**
- Modify: `firestore.rules`

### Step 7.1 — Edit firestore.rules

- [ ] **Open `firestore.rules`.** Find the closing `}` of the `match /databases/{database}/documents {` block and insert the new rules **immediately before** the `// ── Default deny ──` comment block.

Find this block near the bottom of the file:
```
    // ── Default deny ─────────────────────────────────────────────────────
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

Insert the following **directly above** the `// ── Default deny ──` line, with the same indentation as the existing blocks:

```
    // ── Customers ────────────────────────────────────────────────────────
    // Used by FirestoreService.createCustomer / updateCustomer / etc.
    match /protpo_customers/{docId} {
      allow read: if true;
      allow create, update: if
        request.resource.data.keys().hasAny(['name', 'customerType']) &&
        request.resource.size() < 50 * 1024;
      allow delete: if true;
    }

    // ── Jobs and their subcollections ────────────────────────────────────
    // Estimates and versions carry full EstimatorState so they share the
    // same 900KB cap as the legacy protpo_projects collection.
    match /protpo_jobs/{jobId} {
      allow read: if true;
      allow create, update: if
        request.resource.data.keys().hasAny(['jobName', 'customerId']) &&
        request.resource.size() < 100 * 1024;
      allow delete: if true;

      match /estimates/{estimateId} {
        allow read: if true;
        allow create, update: if request.resource.size() < 900 * 1024;
        allow delete: if true;

        match /versions/{versionId} {
          allow read: if true;
          allow create: if request.resource.size() < 900 * 1024;
          // Versions are immutable — no updates permitted.
          allow update: if false;
          allow delete: if true;
        }
      }

      match /activities/{activityId} {
        allow read: if true;
        allow create: if request.resource.size() < 50 * 1024;
        // Only task activities can be updated (completion toggle).
        allow update: if request.resource.data.type == 'task' &&
                         request.resource.size() < 50 * 1024;
        allow delete: if true;
      }
    }

```

### Step 7.2 — Validate rules syntax locally

- [ ] **Run:** `firebase deploy --only firestore --project tpo-pro-245d1 --dry-run 2>&1 | tail -20`

Expected: Contains `rules file firestore.rules compiled successfully` and does NOT contain `Error`. The `--dry-run` flag validates without deploying.

If it fails because the Firebase CLI token is expired, run `firebase login --reauth` first, then retry.

### Step 7.3 — Deploy rules

- [ ] **Run (as a single shell line):** `cd /Users/mattmoore/My_Project/protpo_app && firebase deploy --only firestore --project tpo-pro-245d1 2>&1 | tail -10`

Expected: `✔  firestore: released rules firestore.rules to cloud.firestore` and `✔  Deploy complete!`

If you see `Authentication Error: Your credentials are no longer valid`, run `firebase login --reauth` in a separate terminal (it is interactive and cannot be automated from this plan).

### Step 7.4 — Commit

- [ ] **Run:**

```bash
git add firestore.rules
git commit -m "feat(rules): add job record collections to Firestore security rules

Adds locked-down rules for protpo_customers, protpo_jobs, and the
estimates/versions/activities subcollections under each job. Same
philosophy as existing rules — client is unauthenticated, size caps
enforce sanity, default-deny on everything else. Versions are
immutable (no update rule).

Deployed to tpo-pro-245d1.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Final verification and plan completion

**Files:** none modified

### Step 8.1 — Run the full test suite

- [ ] **Run:** `flutter test test/models/ 2>&1 | tail -20`

Expected: All 5 new model test files pass. Total new test count: roughly 30+ tests across the 5 files.

### Step 8.2 — Run flutter analyze on the whole project

- [ ] **Run:** `flutter analyze 2>&1 | tail -10`

Expected: No new errors introduced by Phase 1 beyond the pre-existing analyzer warnings. The final `N issues found` count should be approximately the same as before Phase 1 started (174 at the time the plan was written, likely still around that number since Phase 1 only adds files).

### Step 8.3 — Manual smoke test via Firebase console

- [ ] **Open:** https://console.firebase.google.com/project/tpo-pro-245d1/firestore/rules

- [ ] **Verify** the deployed rules now include the `protpo_customers` and `protpo_jobs` match blocks. The rules tab shows the most recent deployment timestamp.

- [ ] **Optionally verify:** open the "Data" tab. No `protpo_customers` or `protpo_jobs` collections exist yet — they will be created when the first document is written from Phase 3+ code. This is expected for Phase 1.

### Step 8.4 — Push to GitHub

- [ ] **Run:** `git push origin main 2>&1 | tail -5`

Expected: Push succeeds. All Phase 1 commits (6 commits: 5 model tasks + 1 services task + 1 rules task, potentially batched) are now on origin/main.

### Step 8.5 — Phase 1 complete checkpoint

Phase 1 is done when all of the following are true:

- [ ] `lib/models/customer.dart`, `job.dart`, `estimate.dart`, `estimate_version.dart`, `activity.dart` exist and pass their tests
- [ ] `lib/services/firestore_service.dart` contains CRUD methods for customers, jobs, estimates, versions, activities (visible via grep for `createCustomer`, `createJob`, `createEstimate`, `createVersion`, `createActivity`, `deleteJobCascade`)
- [ ] `firestore.rules` contains match blocks for `protpo_customers` and `protpo_jobs`
- [ ] Locked-down rules are deployed to `tpo-pro-245d1` Firebase project
- [ ] `flutter test test/models/` passes all new tests
- [ ] `flutter analyze` shows no new errors
- [ ] All Phase 1 commits are pushed to `origin/main`
- [ ] The running app at `tpo-pro-245d1.web.app` is unchanged — no UI, save flow, or existing functionality has been modified

No user-visible change has been made. The data layer is ready for Phase 2 to start wiring up Riverpod providers.

---

## Notes for the implementing engineer

- **TDD strictness:** each model task follows red → green → commit. Do not skip the "run and verify it fails" step — it is there to confirm the test is wired correctly before you make it pass.
- **Don't refactor existing code:** Phase 1 only adds new files and appends to `FirestoreService`. Do not touch the existing save/load path, `serialization.dart`, or any model outside `lib/models/customer.dart`, `job.dart`, `estimate.dart`, `estimate_version.dart`, `activity.dart`.
- **The estimatorState map is opaque:** Phase 1 treats `Map<String, dynamic>` as a black box. Do not validate or transform its contents in the model layer. That is serialization.dart's job, and Phase 2 wires the two together.
- **No new dependencies:** if you feel tempted to add `fake_cloud_firestore`, `mockito`, `freezed`, or `json_annotation`, stop and re-read the "Tech Stack" section. Phase 1 uses zero new deps on purpose.
- **One commit per task:** tasks 1-5 each produce one commit. Task 6 produces one commit. Task 7 produces one commit. Final push in task 8.5. Total: 7 commits + 1 push.
- **If a step fails:** stop and diagnose. Do not force-progress through failures. The plan is designed so each step is independently verifiable.
