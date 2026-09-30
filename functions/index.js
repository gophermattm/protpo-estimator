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

// ── VersiBot ──────────────────────────────────────────────────────────────────
// askVersico2 replaces the Python askVersico (retired models). Named *2 so the
// old function stays untouched until this one is confirmed.
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { initializeApp, getApps } = require("firebase-admin/app");
const { GoogleAuth } = require("google-auth-library");
const versibot = require("./versibot");

const ANTHROPIC_KEY = defineSecret("ANTHROPIC_API_KEY");
if (!getApps().length) initializeApp();
const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] });

exports.askVersico2 = onCall(
  { region: "us-central1", secrets: [ANTHROPIC_KEY], timeoutSeconds: 60, memory: "1GiB" },
  async (request) => {
    const data = request.data || {};
    const mode = data.mode;
    if (mode === "audit" || mode === "nl" || mode === "sow") {
      if (!data.prompt) throw new HttpsError("invalid-argument", "prompt required");
      try {
        const text = await versibot.claude({
          prompt: data.prompt,
          system: data.system || "",
          maxTokens: mode === "audit" ? 1000 : 300,
          apiKey: ANTHROPIC_KEY.value(),
        });
        return { result: { result: text } };
      } catch (err) {
        throw new HttpsError("internal", String((err && err.message) || err));
      }
    }

    const question = data.question;
    if (!question) return { answer: "Please ask a question!", sources: [] };
    try {
      const token = await auth.getAccessToken();
      const vector = await versibot.embed(question, token);
      const snap = await getFirestore().collection("versico_technical_data").findNearest({
        vectorField: "embedding",
        queryVector: FieldValue.vector(vector),
        limit: 20,
        distanceMeasure: "COSINE",
      }).get();
      const { contextText, sources } = versibot.shapeHits(snap.docs.map((d) => d.data()));
      const answer = await versibot.generate(versibot.buildPrompt(contextText, question), token);
      return { answer, sources };
    } catch (err) {
      console.error("VersiBot error", err);
      return { answer: `VersiBot hit a snag: ${String((err && err.message) || err)}`, sources: [] };
    }
  });
