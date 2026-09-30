// ProTPO Cloud Functions. QXO access goes through the gorilla-integrations
// gateway, which owns QXO OAuth; this layer only holds the gateway key
// (Firebase secret GORILLA_GATEWAY_KEY) so it never ships in the web bundle.
//
// Named *Gw so they deploy alongside the older Python getQxoPricing /
// searchQxoItems (source not in this repo) instead of replacing them.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { callGateway, normalizePricing, normalizeItems } = require("./qxo");

const GATEWAY_KEY = defineSecret("GORILLA_GATEWAY_KEY");
const opts = { region: "us-central1", secrets: [GATEWAY_KEY], timeoutSeconds: 90 };

function toHttpsError(err) {
  return new HttpsError(err.status === 400 ? "invalid-argument" : "unavailable",
    String((err && err.message) || err));
}

exports.getQxoPricingGw = onCall(opts, async (request) => {
  const skuIds = (request.data && request.data.skuIds) || [];
  if (!Array.isArray(skuIds) || skuIds.length === 0) return { prices: {} };
  try {
    const payload = await callGateway("/api/qxo/pricing",
      { environment: "prod", skuIds: skuIds.map(String) },
      { apiKey: GATEWAY_KEY.value() });
    return { prices: normalizePricing(payload.data || {}) };
  } catch (err) {
    throw toHttpsError(err);
  }
});

exports.searchQxoItemsGw = onCall(opts, async (request) => {
  const query = String((request.data && request.data.query) || "").trim();
  if (query.length < 2) return { items: [], totalCount: 0 };
  try {
    const payload = await callGateway("/api/qxo/product",
      { environment: "prod", query, pageSize: 25 },
      { apiKey: GATEWAY_KEY.value() });
    const data = payload.data || {};
    const items = normalizeItems(data);
    return { items, totalCount: data.totalNumRecs ?? items.length };
  } catch (err) {
    throw toHttpsError(err);
  }
});
