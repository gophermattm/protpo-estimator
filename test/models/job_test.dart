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
