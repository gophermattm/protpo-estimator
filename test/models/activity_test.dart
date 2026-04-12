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
