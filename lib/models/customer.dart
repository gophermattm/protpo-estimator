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
