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
