import 'package:flutter/foundation.dart';
import 'qxo_api_service.dart';

/// Pricing service that searches QXO catalog by BOM item names,
/// resolves them to Beacon item numbers, then fetches live pricing.
class QxoPricingService {
  final _api = QxoApiService();

  /// Given a list of BOM item names and their quantities,
  /// searches QXO for matching products, fetches pricing, and returns
  /// a map of { bomItemName: QxoPricedItem } with pack-adjusted order quantities.
  ///
  /// [bomItems] maps item name → BOM quantity needed (e.g. 109 screws).
  Future<Map<String, QxoPricedItem>> fetchBomPricing(
      List<String> bomItemNames,
      {Map<String, int> bomQuantities = const {}}) async {
    if (bomItemNames.isEmpty) return {};

    final result = <String, QxoPricedItem>{};
    final resolvedItems = <String, QxoItem>{}; // bomName → QxoItem

    // Step 1: Search for each BOM item sequentially (avoid flooding the API)
    final confidences = <String, double>{};
    for (final bomName in bomItemNames) {
      try {
        final query = _buildSearchQuery(bomName);
        final isDirectSku = RegExp(r'^\d{6}$').hasMatch(query);
        debugPrint('[QXO] Searching: "$query" (for "$bomName")');
        final searchResult = await _api.searchItems(query);
        if (searchResult.items.isEmpty) {
          debugPrint('[QXO]   → No results');
          continue;
        }

        // Direct-SKU lookups (fastener length map) return the exact item
        // by number — no scoring needed, treat as full confidence.
        if (isDirectSku) {
          resolvedItems[bomName] = searchResult.items.first;
          confidences[bomName] = 1.0;
          debugPrint('[QXO]   → SKU match: ${searchResult.items.first.itemNumber} '
              '${searchResult.items.first.productName}');
          continue;
        }

        // Otherwise score the top candidates and pick the best match.
        final best = _selectBest(searchResult.items, bomName, query);
        if (best == null) {
          debugPrint('[QXO]   → No scoreable candidates');
          continue;
        }
        resolvedItems[bomName] = best.$1;
        confidences[bomName] = best.$2;

        final scoreStr = best.$2.toStringAsFixed(2);
        if (best.$2 < kLowConfidenceThreshold) {
          debugPrint('[QXO]   → LOW CONFIDENCE ($scoreStr): '
              '${best.$1.itemNumber} ${best.$1.productName} — verify manually');
        } else {
          debugPrint('[QXO]   → Match ($scoreStr): '
              '${best.$1.itemNumber} ${best.$1.productName}');
        }
      } catch (e) {
        debugPrint('[QXO]   → Search error: $e');
      }
    }

    if (resolvedItems.isEmpty) return result;

    // Step 2: Batch pricing call for all resolved item numbers at once
    final itemNumbers = resolvedItems.values.map((i) => i.itemNumber).toSet().toList();
    debugPrint('[QXO] Fetching pricing for ${itemNumbers.length} items: ${itemNumbers.join(",")}');

    Map<String, Map<String, double>> prices = {};
    try {
      prices = await _api.getPricing(itemNumbers);
      debugPrint('[QXO] Got pricing for ${prices.length} items');
    } catch (e) {
      debugPrint('[QXO] Pricing error: $e');
    }

    // Step 3: Combine search results with pricing + pack-adjusted order qty
    for (final entry in resolvedItems.entries) {
      final bomName = entry.key;
      final item = entry.value;
      final priceMap = prices[item.itemNumber];

      double? unitPrice;
      String? uom;
      if (priceMap != null && priceMap.isNotEmpty) {
        final priceEntry = priceMap.entries.first;
        uom = priceEntry.key;
        unitPrice = priceEntry.value;
      }

      // Calculate order quantity: how many packages needed to cover BOM qty
      final bomQty = bomQuantities[bomName];
      int? orderQty;
      if (bomQty != null && bomQty > 0) {
        final packSize = item.packQty ?? 1;
        if (packSize > 1) {
          // Ceiling division: 109 screws / 250 per bucket = 1 bucket
          orderQty = (bomQty / packSize).ceil();
          debugPrint('[QXO]   Pack adjust: $bomName needs $bomQty, '
              'pack of $packSize ${item.uom ?? uom ?? "EA"} → order $orderQty');
        } else {
          orderQty = bomQty;
        }
      }

      result[bomName] = QxoPricedItem(
        bomName: bomName,
        qxoItemNumber: item.itemNumber,
        qxoProductName: item.productName,
        qxoBrand: item.brand,
        unitPrice: unitPrice,
        uom: uom,
        packQty: item.packQty,
        orderQty: orderQty,
        confidence: confidences[bomName],
      );
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CANDIDATE SCORING
  //
  // QXO search often returns 10+ items for a query. The original implementation
  // blindly took items.first, which produced frequent mismatches (e.g. searching
  // for "scupper" returned the first scupper-adjacent product rather than the
  // actual TPO roof scupper we wanted).
  //
  // The scorer below ranks candidates by: token overlap between BOM name and
  // product name, brand match against the query's implied brand, membrane
  // thickness (mil), and roll width. The best-scoring candidate wins, and a
  // normalized score in [0,1] is returned so low-confidence matches can be
  // surfaced to the user.
  // ═══════════════════════════════════════════════════════════════════════

  /// Scores [items] against [bomName] and returns (best_item, score) or
  /// null if the list is empty. Only the top 10 candidates are considered
  /// to keep the work bounded for large QXO result sets.
  (QxoItem, double)? _selectBest(List<QxoItem> items, String bomName, String query) {
    if (items.isEmpty) return null;
    QxoItem? best;
    double bestScore = -1;
    for (final item in items.take(10)) {
      final s = _scoreCandidate(item, bomName, query);
      if (s > bestScore) {
        best = item;
        bestScore = s;
      }
    }
    if (best == null) return null;
    return (best, bestScore.clamp(0.0, 1.0));
  }

  /// Returns a score in approximately [0,1] for how well [item] matches
  /// the BOM line [bomName]. Higher is better.
  double _scoreCandidate(QxoItem item, String bomName, String query) {
    final bomTokens = _tokenize(bomName).toSet();
    final productText = '${item.brand} ${item.productName} ${item.internalName}';
    final productTokens = _tokenize(productText).toSet();

    if (bomTokens.isEmpty || productTokens.isEmpty) return 0.0;

    // Jaccard token overlap as the base signal.
    final intersection = bomTokens.intersection(productTokens);
    final union = bomTokens.union(productTokens);
    double score = union.isEmpty ? 0.0 : intersection.length / union.length;

    // Brand boost: reward exact matches on brands we explicitly asked for,
    // penalize mismatches. Uses the QUERY (which our _buildSearchQuery
    // heuristics enrich with brand hints) rather than the raw BOM name.
    final queryLower = query.toLowerCase();
    final brandLower = '${item.brand} ${item.productName}'.toLowerCase();
    const brandHints = {
      'versico': ['versico'],
      'tri-built': ['tri-built', 'tribuilt', 'tri built'],
      'carlisle': ['carlisle'],
      'johns manville': ['johns manville', 'jm'],
      'firestone': ['firestone'],
      'gaf': ['gaf'],
    };
    for (final entry in brandHints.entries) {
      if (queryLower.contains(entry.key)) {
        final matches = entry.value.any((alias) => brandLower.contains(alias));
        if (matches) {
          score += 0.15;
        } else {
          score -= 0.10;
        }
        break; // only one brand hint should apply
      }
    }

    // Membrane thickness — reward exact "60 mil" match, penalize a
    // different mil value in the candidate.
    final milMatch = RegExp(r'(\d+)\s*mil').firstMatch(bomName.toLowerCase());
    if (milMatch != null) {
      final mil = milMatch.group(1)!;
      if (RegExp('${RegExp.escape(mil)}\\s*mil').hasMatch(productText.toLowerCase())) {
        score += 0.10;
      } else if (RegExp(r'\d+\s*mil').hasMatch(productText.toLowerCase())) {
        score -= 0.10;
      }
    }

    // Roll width — 6' vs 10' for TPO rolls.
    final widthMatch = RegExp(r"(\d+)'").firstMatch(bomName);
    if (widthMatch != null) {
      final w = widthMatch.group(1)!;
      final hasWidth = productText.contains("$w'") ||
          productText.toLowerCase().contains('$w ft') ||
          productText.toLowerCase().contains('$w foot');
      if (hasWidth) score += 0.10;
    }

    // Rigid insulation thickness — "1.5\"" or "2\"" should match same value.
    final inchMatch = RegExp(r'(\d+(?:\.\d+)?)\s*["\u201d]').firstMatch(bomName);
    if (inchMatch != null) {
      final inches = inchMatch.group(1)!;
      if (productText.contains('$inches"') ||
          productText.toLowerCase().contains('$inches in')) {
        score += 0.08;
      }
    }

    // Tapered panel letter — "Panel X" in BOM should map to a product that
    // mentions the same letter. Uses word boundaries to avoid false hits.
    final panelMatch = RegExp(r'Panel\s+([A-Z]{1,2})\b').firstMatch(bomName);
    if (panelMatch != null) {
      final letter = panelMatch.group(1)!;
      if (RegExp('\\b$letter\\b').hasMatch(productText)) {
        score += 0.12;
      }
    }

    return score;
  }

  /// Lowercases, strips punctuation, removes short words and generic
  /// stopwords, and returns the token list for Jaccard comparison.
  List<String> _tokenize(String s) {
    const stop = {
      'the', 'and', 'for', 'with', 'from', 'roofing', 'inch', 'inches',
      'each', 'per', 'box', 'case', 'pack', 'bundle', 'roll', 'sheet',
      'item', 'layer', 'sf', 'lf',
    };
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2 && !stop.contains(t))
        .toList();
  }

  /// Extracts meaningful search terms from a BOM item name.
  String _buildSearchQuery(String bomName) {
    final lower = bomName.toLowerCase();

    // ── MEMBRANE ──
    // BOM field name:    "60 mil TPO — Field (10'×100')"
    // BOM flashing name: "60 mil TPO — Flashing (6'×100' roll, 600 sf)"

    // Field TPO — 10' wide rolls for the main roof field
    if (lower.contains('tpo') && lower.contains('field')) {
      // Extract thickness (e.g. "60 mil") for more specific search
      final thickness = _extractMembraneThickness(bomName);
      if (thickness != null) {
        return 'Versico VersiWeld TPO $thickness 10';
      }
      return 'Versico VersiWeld TPO membrane 10 wide';
    }
    // Flashing TPO — 6' wide rolls for perimeter/parapet/corner zones
    if (lower.contains('tpo') && lower.contains('flashing') &&
        (lower.contains("6'") || lower.contains('6 '))) {
      final thickness = _extractMembraneThickness(bomName);
      if (thickness != null) {
        return 'Versico VersiWeld TPO $thickness 6 wide';
      }
      return 'Versico VersiWeld TPO reinforced 6 wide';
    }
    // Fallback for any other TPO roll
    if (lower.contains('tpo') &&
        (lower.contains("x100'") || lower.contains('roll'))) {
      return 'Versico VersiWeld TPO membrane';
    }

    // ── INSULATION ──

    // Tapered polyiso panels — each panel letter (X, Y, Z, ZZ, etc.) has its
    // own thickness range and its own QXO SKU. Extract the letter and include
    // it in the search to get per-panel pricing.
    // BOM name format: "Tapered Polyiso — Panel X (Versico 1/4:12)"
    if (lower.contains('tapered') && lower.contains('polyiso')) {
      final brand = lower.contains('versico')
          ? 'Versico VersiCore'
          : 'TRI-BUILT';
      final letter = _extractPanelLetter(bomName);
      final rate = _extractTaperRate(bomName);
      if (letter != null && rate != null) {
        // e.g. "Versico VersiCore tapered polyiso X 1/4" for panel X at 1/4:12
        return '$brand tapered polyiso $letter $rate';
      }
      if (letter != null) {
        return '$brand tapered polyiso $letter';
      }
      return '$brand tapered polyiso';
    }
    // Flat fill polyiso — extract thickness so QXO returns the right SKU
    if (lower.contains('flat fill') && lower.contains('polyiso')) {
      final thickness = _extractFlatFillThickness(bomName);
      if (thickness != null) {
        if (lower.contains('versico')) {
          return 'Versico polyiso $thickness';
        }
        return 'TRI-BUILT polyiso $thickness';
      }
      return 'polyiso insulation';
    }
    if (lower.contains('polyiso')) return 'polyiso insulation';
    if (lower.contains('eps') && (lower.contains('insulation') || lower.contains('layer'))) {
      return 'TRI-BUILT rigid roof insulation';
    }
    if (lower.contains('cover board')) return 'TRI-Built cover board';

    // ── DETAILS & ACCESSORIES ──

    if (lower.contains('inside corner')) return 'Versico TPO inside corner';
    if (lower.contains('outside corner')) return 'Versico TPO outside corner';
    if (lower.contains('t-joint') || lower.contains('t joint')) return 'Versico TPO T-joint cover';
    if (lower.contains('curb wrap corner')) return 'Versico TPO curb wrap corner';
    if (lower.contains('curb flashing')) return 'Versico TPO flashing';
    if (lower.contains('wall flashing')) return 'Versico TPO wall flashing';
    if (lower.contains('pipe boot')) return 'Versico TPO pipe boot';
    if (lower.contains('pitch pan') || lower.contains('sealant pocket')) {
      return 'Versico VersiWeld TPO molded sealant pocket';
    }
    if (lower.contains('scupper')) return 'scupper';
    if (lower.contains('drain assembly') || lower.contains('drain (')) {
      return 'TPO roof drain assembly';
    }
    if (lower.contains('skylight')) return 'TPO skylight flashing curb';
    if (lower.contains('expansion joint')) return 'expansion joint roofing';
    if (lower.contains('walkway pad') || lower.contains('walkway roll')) {
      return 'TPO walkway pad heat weldable';
    }

    // ── METAL SCOPE ──

    if (lower.contains('termination bar') || lower.contains('lip termination')) {
      return 'TRI-BUILT lip termination bar';
    }
    if (lower.contains('coping cap') || lower.contains('coping —')) {
      return 'TRI-BUILT trim coil';  // rolled metal for custom coping fabrication
    }
    if (lower.contains('gutter')) return 'K-style gutter aluminum';
    if (lower.contains('downspout')) return 'downspout roofing';
    if (lower.contains('drip edge')) return 'steel drip edge roofing';

    // ── FASTENERS & PLATES ──
    // Fastener searches must include length to match the correct QXO SKU.
    // QXO treats each length as a separate item number.

    if (lower.contains('#14 hp') || lower.contains('standard drill point')) {
      final len = _extractFastenerLength(bomName);
      if (len != null) return len; // direct SKU search
      return 'TRI-BUILT standard drill point roofing fastener';
    }
    if (lower.contains('wood screw') || lower.contains('heavy duty roofing fastener')) {
      final len = _extractFastenerLength(bomName);
      if (len != null) return len; // direct SKU search
      return 'TRI-BUILT heavy duty roofing fastener';
    }
    if (lower.contains('concrete anchor') || lower.contains('concrete fastener')) {
      return 'Carlisle SynTec concrete fastener';
    }
    if (lower.contains('masonry anchor')) return 'TRI-BUILT zinc masonry anchor';
    if (lower.contains('tek screw') || lower.contains('self-drilling')) {
      return 'self tapping metal screw roofing';
    }
    if (lower.contains('gypsum fastener') || lower.contains('tectum fastener') ||
        lower.contains('lw concrete anchor')) {
      final len = _extractFastenerLength(bomName);
      if (len != null) return len;
      return 'TRI-BUILT standard drill point roofing fastener';
    }
    if (lower.contains('stress plate') || lower.contains('seam stress')) return 'seam plate';
    if (lower.contains('insulation plate')) return 'TRI-BUILT insulation seam steel plates';
    if (lower.contains('seam fastening plate')) return 'Versico seam fastening plate';
    if (lower.contains('rhinobond') && lower.contains('plate')) return 'Versico Rhinobond plate';

    // ── ADHESIVES & SEALANTS ──

    if (lower.contains('cav-grip 3v') || lower.contains('cav-grip 3v low-voc')) {
      return 'CAV-Grip 3v Low-VOC';
    }
    if (lower.contains('bonding adhesive') && lower.contains('cav-grip')) {
      return 'Carlisle SynTec CAV-GRIP III Low-VOC';
    }
    if (lower.contains('un-tack')) return 'Carlisle UN-TACK';
    if (lower.contains('cut edge sealant') || lower.contains('cut-edge sealant')) {
      return 'Versico cut edge sealant';
    }
    if (lower.contains('water cut-off mastic')) return 'Versico water cut-off mastic';
    if (lower.contains('water block')) return 'water block mastic';
    if (lower.contains('single-ply sealant') || lower.contains('single ply sealant')) {
      return 'single ply sealant Versico';
    }
    if (lower.contains('lap sealant')) return 'Versico lap sealant';
    if (lower.contains('tpo primer') && !lower.contains('adhesive')) return 'Versico TPO primer';
    if (lower.contains('seam tape') && lower.contains('tpo')) return 'Versico TPO seam tape';
    if (lower.contains('substrate primer') || lower.contains('bituminous deck')) {
      return 'Versico low-VOC primer';
    }

    // ── OTHER ──

    if (lower.contains('vapor retarder') || lower.contains('vapor barrier')) {
      return 'self-adhered vapor retarder roofing';
    }
    if (lower.contains('russ')) return 'Versico RUSS securement strip';
    if (lower.contains('overlayment strip') || lower.contains('cover strip')) {
      return 'Versico TPO reinforced overlayment strip';
    }
    if (lower.contains('hook blade')) return 'hook blades';
    if (lower.contains('cleaner') || lower.contains('rags')) return 'TPO membrane cleaner';

    // ── Generic cleanup for anything not matched above ──

    var q = bomName
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll('—', ' ')
        .replaceAll('–', ' ')
        .replaceAll('&', ' ')
        .replaceAll(RegExp(r'\d+\.?\d*["\u201d]'), '')
        .replaceAll(RegExp(r'Layer \d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Brand hints
    if (q.toLowerCase().contains('tpo') && !q.toLowerCase().contains('versico')) {
      q = 'Versico $q';
    }

    return q;
  }

  /// Extract membrane thickness like "60 mil" or "45 mil" from the BOM name.
  String? _extractMembraneThickness(String bomName) {
    final match = RegExp(r'(\d+)\s*mil', caseSensitive: false).firstMatch(bomName);
    if (match == null) return null;
    return '${match.group(1)} mil';
  }

  /// Extract the tapered panel letter (X, Y, Z, ZZ, AA, A, B, C, D, E, F, FF,
  /// Q, SS, TT) from a BOM name like "Tapered Polyiso — Panel X (Versico ...)"
  String? _extractPanelLetter(String bomName) {
    // Match "Panel X" or "Panel ZZ" — letters only, 1-2 chars
    final match = RegExp(r'Panel\s+([A-Z]{1,2})\b').firstMatch(bomName);
    return match?.group(1);
  }

  /// Extract the taper rate (e.g. "1/4", "1/8", "1/2", "3/16", "3/8") from
  /// a BOM name like "(Versico 1/4:12)". Returns the fraction part only.
  String? _extractTaperRate(String bomName) {
    final match = RegExp(r'(\d+/\d+):12').firstMatch(bomName);
    return match?.group(1);
  }

  /// Extract flat fill polyiso thickness from BOM name and return a QXO
  /// search term like "1 inch" or "2 inch".
  /// E.g. "Flat Fill Polyiso 1.0\" (Versico)" → "1 inch"
  String? _extractFlatFillThickness(String bomName) {
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*["\u201d]').firstMatch(bomName);
    if (match == null) return null;
    final raw = match.group(1)!;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return null;
    // Round to nearest half-inch for QXO search terms
    if (value == value.roundToDouble()) {
      return '${value.toInt()} inch';
    }
    return '${value.toStringAsFixed(1)} inch';
  }

  /// Extract fastener length from BOM name (e.g. "Wood Screw 8" — ...")
  /// and return the direct QXO item number for that type + length.
  /// Returns null if length can't be determined or no SKU mapping exists.
  String? _extractFastenerLength(String bomName) {
    final lower = bomName.toLowerCase();

    // Extract length in inches from patterns like '8"', '3-1/2"', '4.5"'
    final match = RegExp(r'(\d+(?:[-.]\d+(?:/\d+)?)?)\s*["\u201d]').firstMatch(bomName);
    if (match == null) return null;

    final rawLen = match.group(1)!;
    // Normalize: "3-1/2" → 3, "4.5" → 4, "8" → 8 (round to nearest whole inch for SKU lookup)
    int lengthIn;
    if (rawLen.contains('/')) {
      // e.g. "3-1/2" → take the integer part
      lengthIn = int.tryParse(rawLen.split(RegExp(r'[-/]')).first) ?? 0;
      // Add 1 for half-inch fractions to round up
      if (rawLen.contains('1/2') || rawLen.contains('.5')) lengthIn += 1;
    } else if (rawLen.contains('.')) {
      lengthIn = double.tryParse(rawLen)?.round() ?? 0;
    } else {
      lengthIn = int.tryParse(rawLen) ?? 0;
    }

    if (lengthIn < 2 || lengthIn > 14) return null;

    // Determine fastener family
    final bool isHeavyDuty = lower.contains('wood screw') ||
        lower.contains('heavy duty');
    final bool isStdDrill = lower.contains('#14 hp') ||
        lower.contains('standard drill') ||
        lower.contains('gypsum') ||
        lower.contains('tectum') ||
        lower.contains('lw concrete');

    // TRI-BUILT Heavy Duty Roofing Fasteners (wood deck) SKU map
    const heavyDutySKU = {
      3: '560420', 4: '560422', 5: '560424',
      6: '560426', 7: '560427', 8: '560428',
      9: '560429', 10: '560430', 12: '560432', 14: '560433',
    };

    // TRI-BUILT Standard Drill Point Roofing Fasteners (metal deck) SKU map
    const stdDrillSKU = {
      2: '560393', 3: '560387', 4: '560388',
      5: '560389', 6: '560390', 7: '560391', 8: '560392',
    };

    String? sku;
    if (isHeavyDuty) {
      sku = heavyDutySKU[lengthIn];
      // Try nearest length if exact not found
      if (sku == null) {
        final nearest = heavyDutySKU.keys.reduce((a, b) =>
            (a - lengthIn).abs() < (b - lengthIn).abs() ? a : b);
        sku = heavyDutySKU[nearest];
      }
    } else if (isStdDrill) {
      sku = stdDrillSKU[lengthIn];
      if (sku == null) {
        final nearest = stdDrillSKU.keys.reduce((a, b) =>
            (a - lengthIn).abs() < (b - lengthIn).abs() ? a : b);
        sku = stdDrillSKU[nearest];
      }
    }

    return sku; // Returns the item number as the search query — QXO finds it directly
  }
}

/// A BOM item matched to a QXO catalog item with pricing.
class QxoPricedItem {
  final String bomName;
  final String qxoItemNumber;
  final String qxoProductName;
  final String qxoBrand;
  final double? unitPrice;
  final String? uom;
  final int? packQty;    // units per package (e.g. 250 screws/bucket)
  final int? orderQty;   // packages needed to cover BOM quantity

  /// Match confidence 0.0-1.0, where 1.0 = perfect match.
  /// Null when confidence is not available (e.g. fastener direct-SKU lookup).
  /// Values below [kLowConfidenceThreshold] should be surfaced in the UI
  /// so the user can verify the match manually.
  final double? confidence;

  const QxoPricedItem({
    required this.bomName,
    required this.qxoItemNumber,
    required this.qxoProductName,
    required this.qxoBrand,
    this.unitPrice,
    this.uom,
    this.packQty,
    this.orderQty,
    this.confidence,
  });

  /// Total cost = unitPrice * orderQty (or null if either is missing)
  double? get totalCost =>
      unitPrice != null && orderQty != null ? unitPrice! * orderQty! : null;

  /// True when [confidence] is below the low-confidence threshold.
  /// Items flagged as low confidence should be reviewed by the user
  /// before trusting the price.
  bool get isLowConfidence =>
      confidence != null && confidence! < kLowConfidenceThreshold;
}

/// Match scores below this threshold are considered low confidence and
/// should be surfaced to the user for manual verification.
const double kLowConfidenceThreshold = 0.35;
