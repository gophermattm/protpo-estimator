import 'package:cloud_functions/cloud_functions.dart';

class QxoPricingService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Fetches pricing for a list of SKU IDs from the QXO Cloud Function.
  /// Returns a map of { skuId: { uom: price } }
  Future<Map<String, Map<String, double>>> getPricing(List<String> skuIds) async {
    if (skuIds.isEmpty) return {};

    final result = await _functions
        .httpsCallable('getQxoPricing')
        .call({'skuIds': skuIds});

    final data = Map<String, dynamic>.from(result.data['prices'] ?? {});
    final prices = <String, Map<String, double>>{};

    for (final entry in data.entries) {
      final uomMap = Map<String, dynamic>.from(entry.value);
      prices[entry.key] = uomMap.map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    return prices;
  }
}
