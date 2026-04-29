import 'package:cloud_firestore/cloud_firestore.dart';

/// One row in the QXO catalog alignment table.
///
/// Identified by `(skuKey, attributes)` — the same skuKey may have multiple
/// rows if SKUs differ by attribute (e.g. fastener length, membrane thickness).
class QxoSkuMapping {
  /// Stable BOM identifier (e.g. `tpo_membrane_field`, `plate_3in_insulation`).
  final String skuKey;

  /// Variant attributes that discriminate sub-SKUs sharing the same skuKey.
  /// Empty/null for single-SKU products.
  final Map<String, dynamic> attributes;

  /// Stable hash of `attributes` used to build the Firestore doc ID.
  final String attributesHash;

  /// QXO/Beacon item number (e.g. "VWPLATE3"). Null when not yet mapped.
  final String? qxoItemNumber;

  /// QXO product description (mirrored from the catalog at mapping time).
  final String? qxoProductName;

  /// Free-text notes from the operator.
  final String? notes;

  /// Last edit timestamp.
  final DateTime? lastUpdated;

  /// User who last edited.
  final String? updatedBy;

  const QxoSkuMapping({
    required this.skuKey,
    required this.attributes,
    required this.attributesHash,
    this.qxoItemNumber,
    this.qxoProductName,
    this.notes,
    this.lastUpdated,
    this.updatedBy,
  });

  bool get isMapped => qxoItemNumber != null && qxoItemNumber!.isNotEmpty;

  String get docId => attributesHash.isEmpty ? skuKey : '${skuKey}__$attributesHash';

  Map<String, dynamic> toFirestore() => {
        'skuKey':         skuKey,
        'attributes':     attributes,
        'attributesHash': attributesHash,
        if (qxoItemNumber != null)  'qxoItemNumber':  qxoItemNumber,
        if (qxoProductName != null) 'qxoProductName': qxoProductName,
        if (notes != null)          'notes':          notes,
        'lastUpdated': FieldValue.serverTimestamp(),
        if (updatedBy != null)      'updatedBy':      updatedBy,
      };

  factory QxoSkuMapping.fromFirestore(String docId, Map<String, dynamic> data) {
    final attrs = (data['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final ts = data['lastUpdated'];
    return QxoSkuMapping(
      skuKey:         data['skuKey'] as String? ?? '',
      attributes:     attrs,
      attributesHash: data['attributesHash'] as String? ?? '',
      qxoItemNumber:  data['qxoItemNumber'] as String?,
      qxoProductName: data['qxoProductName'] as String?,
      notes:          data['notes'] as String?,
      lastUpdated:    ts is Timestamp ? ts.toDate() : null,
      updatedBy:      data['updatedBy'] as String?,
    );
  }
}

/// Firestore-backed service for the BOM-to-QXO catalog mapping table.
///
/// Document ID convention: `{skuKey}__{attributesHash}` so a single
/// `.doc().get()` resolves a deterministic mapping with no fan-out queries.
class QxoSkuMappingService {
  static const String collection = 'qxo_sku_mappings';

  final FirebaseFirestore _db;

  QxoSkuMappingService([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection(collection);

  /// Stable hash of attribute values. Keys are sorted so the order in which
  /// the BOM emits attributes never affects the lookup ID.
  static String hashAttributes(Map<String, dynamic>? attrs) {
    if (attrs == null || attrs.isEmpty) return '';
    final keys = attrs.keys.toList()..sort();
    return keys.map((k) => '$k=${attrs[k]}').join('|');
  }

  static String buildDocId(String skuKey, Map<String, dynamic>? attributes) {
    final hash = hashAttributes(attributes);
    return hash.isEmpty ? skuKey : '${skuKey}__$hash';
  }

  /// Look up a single mapping. Returns null when no mapping exists yet.
  Future<QxoSkuMapping?> lookup(String skuKey, Map<String, dynamic>? attributes) async {
    final id = buildDocId(skuKey, attributes);
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return QxoSkuMapping.fromFirestore(doc.id, doc.data()!);
  }

  /// Batch lookup. Returns a map keyed by the same docId used to look it up,
  /// so callers can correlate results to their original requests.
  Future<Map<String, QxoSkuMapping?>> lookupMany(
      List<({String skuKey, Map<String, dynamic>? attributes})> requests) async {
    if (requests.isEmpty) return {};
    final results = <String, QxoSkuMapping?>{};
    // Fetch in parallel — Firestore handles small fan-out efficiently.
    await Future.wait(requests.map((req) async {
      final id = buildDocId(req.skuKey, req.attributes);
      results[id] = await lookup(req.skuKey, req.attributes);
    }));
    return results;
  }

  /// Save or upsert a mapping. Uses `mapping.docId` as the document ID so
  /// repeated saves for the same (skuKey, attributes) overwrite cleanly.
  Future<void> save(QxoSkuMapping mapping) async {
    await _col.doc(mapping.docId).set(mapping.toFirestore(), SetOptions(merge: true));
  }

  /// Delete a mapping (revert to "unmapped").
  Future<void> delete(String skuKey, Map<String, dynamic>? attributes) async {
    await _col.doc(buildDocId(skuKey, attributes)).delete();
  }

  /// Stream every mapping in the collection — for the admin page list view.
  Stream<List<QxoSkuMapping>> watchAll() {
    return _col.orderBy('skuKey').snapshots().map(
          (snap) => snap.docs
              .map((d) => QxoSkuMapping.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  /// Stream all mappings for a single skuKey (typically multiple variants).
  Stream<List<QxoSkuMapping>> watchByKey(String skuKey) {
    return _col
        .where('skuKey', isEqualTo: skuKey)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => QxoSkuMapping.fromFirestore(d.id, d.data()))
            .toList());
  }
}
