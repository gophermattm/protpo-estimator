/// test/models/drainage_zone_test.dart
///
/// TDD tests for ScupperLocation, TaperDefaults, DrainageZone, DrainageZoneOverride.

import 'package:flutter_test/flutter_test.dart';
import 'package:protpo_app/models/drainage_zone.dart';

void main() {
  // ─── ScupperLocation ──────────────────────────────────────────────────────

  group('ScupperLocation', () {
    test('creates with edgeIndex and position', () {
      const s = ScupperLocation(edgeIndex: 2, position: 0.5);
      expect(s.edgeIndex, 2);
      expect(s.position, 0.5);
    });

    test('copyWith updates fields', () {
      const s = ScupperLocation(edgeIndex: 0, position: 0.25);
      final updated = s.copyWith(edgeIndex: 3, position: 0.75);
      expect(updated.edgeIndex, 3);
      expect(updated.position, 0.75);
      // original unchanged
      expect(s.edgeIndex, 0);
      expect(s.position, 0.25);
    });

    test('equality by value — same values equal', () {
      const a = ScupperLocation(edgeIndex: 1, position: 0.5);
      const b = ScupperLocation(edgeIndex: 1, position: 0.5);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equality by value — different values not equal', () {
      const a = ScupperLocation(edgeIndex: 1, position: 0.5);
      const b = ScupperLocation(edgeIndex: 2, position: 0.5);
      expect(a, isNot(equals(b)));
    });
  });

  // ─── TaperDefaults ────────────────────────────────────────────────────────

  group('TaperDefaults', () {
    test('initial() factory creates correct defaults', () {
      final d = TaperDefaults.initial();
      expect(d.taperRate, '1/4:12');
      expect(d.minThickness, 1.0);
      expect(d.manufacturer, 'Versico');
      expect(d.profileType, 'extended');
      expect(d.attachmentMethod, 'Mechanically Attached');
    });

    test('copyWith updates manufacturer while preserving other fields', () {
      final d = TaperDefaults.initial();
      final updated = d.copyWith(manufacturer: 'TRI-BUILT');
      expect(updated.manufacturer, 'TRI-BUILT');
      expect(updated.taperRate, '1/4:12');
      expect(updated.minThickness, 1.0);
      expect(updated.profileType, 'extended');
      expect(updated.attachmentMethod, 'Mechanically Attached');
    });
  });

  // ─── DrainageZone ─────────────────────────────────────────────────────────

  group('DrainageZone', () {
    test('creates internal_drain zone with null overrides', () {
      const z = DrainageZone(
        id: 'zone-1',
        type: 'internal_drain',
        lowPointIndex: 0,
      );
      expect(z.id, 'zone-1');
      expect(z.type, 'internal_drain');
      expect(z.lowPointIndex, 0);
      expect(z.taperRateOverride, isNull);
      expect(z.minThicknessOverride, isNull);
      expect(z.manufacturerOverride, isNull);
      expect(z.profileTypeOverride, isNull);
    });

    test('creates scupper zone with taperRateOverride and manufacturerOverride', () {
      const z = DrainageZone(
        id: 'zone-2',
        type: 'scupper',
        lowPointIndex: 1,
        taperRateOverride: '1/8:12',
        manufacturerOverride: 'TRI-BUILT',
      );
      expect(z.type, 'scupper');
      expect(z.taperRateOverride, '1/8:12');
      expect(z.manufacturerOverride, 'TRI-BUILT');
      expect(z.minThicknessOverride, isNull);
      expect(z.profileTypeOverride, isNull);
    });

    test('equality by value — same id equal', () {
      const a = DrainageZone(id: 'zone-1', type: 'internal_drain', lowPointIndex: 0);
      const b = DrainageZone(id: 'zone-1', type: 'internal_drain', lowPointIndex: 0);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equality by value — different id not equal', () {
      const a = DrainageZone(id: 'zone-1', type: 'internal_drain', lowPointIndex: 0);
      const b = DrainageZone(id: 'zone-2', type: 'internal_drain', lowPointIndex: 0);
      expect(a, isNot(equals(b)));
    });
  });

  // ─── DrainageZoneOverride ─────────────────────────────────────────────────

  group('DrainageZoneOverride', () {
    test('creates with zoneId and partial overrides — only taperRateOverride set', () {
      const o = DrainageZoneOverride(
        zoneId: 'zone-1',
        taperRateOverride: '1/8:12',
      );
      expect(o.zoneId, 'zone-1');
      expect(o.taperRateOverride, '1/8:12');
      expect(o.minThicknessOverride, isNull);
      expect(o.manufacturerOverride, isNull);
      expect(o.profileTypeOverride, isNull);
    });
  });
}
