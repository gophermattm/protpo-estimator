/// lib/services/qxo_api_service.dart
///
/// HTTP client for QXO/Beacon Partner Integrations API.
///
/// Routes all requests through Firebase Cloud Functions which handle
/// authentication, cookies, and secrets server-side.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

class QxoApiService {
  // Singleton
  static final QxoApiService _instance = QxoApiService._();
  factory QxoApiService() => _instance;
  QxoApiService._();

  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Search QXO item catalog by text query.
  Future<QxoSearchResult> searchItems(String query) async {
    debugPrint('[QXO] Searching via Cloud Function: "$query"');
    final result = await _functions.httpsCallable('searchQxoItems').call({
      'query': query,
    });

    final data = result.data as Map<String, dynamic>;
    final items = (data['items'] as List? ?? []).map((item) {
      return QxoItem(
        itemNumber: item['itemNumber']?.toString() ?? '',
        productName: _cleanHtml(item['productName']?.toString() ?? ''),
        internalName:
            _cleanHtml(item['internalProductName']?.toString() ?? ''),
        brand: item['brand']?.toString() ?? '',
        productId: item['productId']?.toString() ?? '',
        packQty: item['packQty'] as int?,
        uom: item['uom']?.toString(),
      );
    }).toList();

    return QxoSearchResult(
      items: items,
      totalCount: data['totalCount'] ?? items.length,
      message: '',
    );
  }

  /// Fetch pricing for a list of item numbers (SKU IDs).
  Future<Map<String, Map<String, double>>> getPricing(
      List<String> itemNumbers) async {
    if (itemNumbers.isEmpty) return {};

    debugPrint('[QXO] Fetching pricing via Cloud Function for ${itemNumbers.length} items');
    final result = await _functions.httpsCallable('getQxoPricing').call({
      'skuIds': itemNumbers,
    });

    final data = result.data as Map<String, dynamic>;
    final priceInfo = data['prices'] as Map<String, dynamic>? ?? {};
    final prices = <String, Map<String, double>>{};

    for (final entry in priceInfo.entries) {
      if (entry.value is Map) {
        final uomMap = Map<String, dynamic>.from(entry.value as Map);
        prices[entry.key] =
            uomMap.map((k, v) => MapEntry(k, (v as num).toDouble()));
      }
    }
    return prices;
  }

  /// Submit a quote to QXO/Beacon.
  Future<Map<String, dynamic>> submitQuote({
    required String quoteName,
    required List<QxoQuoteItem> items,
    String? address1,
    String? city,
    String? state,
    String? postalCode,
    String? jobName,
    String? quoteNotes,
    String workType = 'R',
  }) async {
    debugPrint('[QXO] Submitting quote via Cloud Function: "$quoteName"');
    final result = await _functions.httpsCallable('submitQxoQuote').call({
      'projectName': quoteName.length > 50 ? quoteName.substring(0, 50) : quoteName,
      'items': items.map((item) {
        return {
          'skuId': item.itemNumber,
          'quantity': item.quantity,
          'uom': item.uom,
        };
      }).toList(),
    });

    return result.data as Map<String, dynamic>;
  }

  static String _cleanHtml(String s) => s
      .replaceAll(RegExp(r'&[a-zA-Z]+;'), '')
      .replaceAll(RegExp(r'<[^>]+>'), '');
}

// ─── Data Models ──────────────────────────────────────────────────────────────

class QxoItem {
  final String itemNumber;
  final String productName;
  final String internalName;
  final String brand;
  final String productId;
  final int? packQty;  // e.g. 250 for "250 bucket"
  final String? uom;   // e.g. "BKT", "RL", "PC"

  const QxoItem({
    required this.itemNumber,
    required this.productName,
    required this.internalName,
    required this.brand,
    required this.productId,
    this.packQty,
    this.uom,
  });
}

class QxoSearchResult {
  final List<QxoItem> items;
  final int totalCount;
  final String message;

  const QxoSearchResult({
    required this.items,
    required this.totalCount,
    required this.message,
  });
}

class QxoQuoteItem {
  final String itemNumber;
  final int quantity;
  final String uom;
  final String displayName;

  const QxoQuoteItem({
    required this.itemNumber,
    required this.quantity,
    required this.uom,
    required this.displayName,
  });
}
