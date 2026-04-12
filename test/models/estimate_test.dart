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
