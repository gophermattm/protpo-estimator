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
