// Pure helpers: call the gorilla-integrations gateway and normalize QXO's raw
// payloads into the shapes lib/services/qxo_api_service.dart expects.

const DEFAULT_GATEWAY_URL = "https://gorilla-integrations.vercel.app";

async function callGateway(path, body, { apiKey, gatewayUrl = DEFAULT_GATEWAY_URL, fetchImpl = fetch } = {}) {
  if (!apiKey) throw new Error("GORILLA_GATEWAY_KEY is not configured");
  const res = await fetchImpl(`${gatewayUrl.replace(/\/+$/, "")}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-gorilla-key": apiKey },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(60_000),
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok || payload.ok === false) {
    const detail = typeof payload.error === "string" ? payload.error : `gateway returned ${res.status}`;
    const err = new Error(`${payload.stage ? payload.stage + ": " : ""}${detail}`);
    err.status = res.status;
    throw err;
  }
  return payload;
}

// QXO returns pricing as { sku: { uom: price } } or as an array of rows.
// A 0 price means "not quotable on this account" — drop it so the line shows
// as unpriced instead of a $0 line.
function normalizePricing(raw) {
  const prices = {};
  const inner = (raw && (raw.result || raw)) || {};
  const info = inner.priceInfo || inner.prices || (raw && raw.priceInfo);
  const record = (sku, uom, value) => {
    const price = Number(value);
    if (!sku || !Number.isFinite(price) || price <= 0) return;
    (prices[sku] ||= {})[uom || "EA"] = price;
  };
  if (Array.isArray(info)) {
    for (const row of info) record(row && row.skuId, row && row.uom, row && row.price);
  } else if (info && typeof info === "object") {
    for (const [sku, uomMap] of Object.entries(info)) {
      if (uomMap && typeof uomMap === "object") {
        for (const [uom, value] of Object.entries(uomMap)) record(sku, uom, value);
      }
    }
  }
  return prices;
}

// "1,000 carton" → 1000. Returns null when no count is stated.
function parsePackQty(text) {
  if (!text) return null;
  const m = String(text).match(/([\d,]+)\s*(?:ct|count|carton|case|box|bx|bucket|pail|pl|bag|bundle|pack|pk|roll|each|pc|pcs|piece)s?\b/i);
  if (!m) return null;
  const n = parseInt(m[1].replace(/,/g, ""), 10);
  return Number.isFinite(n) && n > 1 ? n : null;
}

function normalizeItems(raw) {
  const items = (raw && raw.items) || [];
  return items.map((item) => {
    const sku = item.currentSKU || {};
    const packaging = sku.variations && Array.isArray(sku.variations.packaging) ? sku.variations.packaging[0] : null;
    return {
      itemNumber: String(sku.itemNumber || item.itemNumber || ""),
      productName: sku.variantName || item.productName || item.internalProductName || "",
      internalProductName: item.internalProductName || "",
      brand: item.brand || "",
      productId: item.productId || "",
      packQty: parsePackQty(packaging) ?? parsePackQty(sku.variantName || item.variantName),
      uom: sku.currentUOM || null,
    };
  });
}

module.exports = { callGateway, normalizePricing, normalizeItems, parsePackQty, DEFAULT_GATEWAY_URL };
