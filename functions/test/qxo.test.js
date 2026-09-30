const test = require("node:test");
const assert = require("node:assert");
const { normalizePricing, normalizeItems, parsePackQty, callGateway } = require("../qxo");

test("pricing object shape, drops 0 prices", () => {
  assert.deepStrictEqual(
    normalizePricing({ result: { priceInfo: { "124278": { PL: 538.28 }, "999": { TB: 0 } } } }),
    { "124278": { PL: 538.28 } });
});

test("pricing array shape", () => {
  assert.deepStrictEqual(
    normalizePricing({ priceInfo: [{ skuId: "1", uom: "CTN", price: 10 }, { skuId: "2", price: 5 }] }),
    { "1": { CTN: 10 }, "2": { EA: 5 } });
});

test("pack qty parsing", () => {
  assert.strictEqual(parsePackQty("1,000 carton"), 1000);
  assert.strictEqual(parsePackQty("Versico 12 in #15 HPVX Fasteners 500 carton"), 500);
  assert.strictEqual(parsePackQty("1 gal can"), null);
  assert.strictEqual(parsePackQty(null), null);
});

test("items use the current SKU", () => {
  const [i] = normalizeItems({ items: [{
    productId: "C-124270", productName: "Versico #14 HPV Fasteners",
    internalProductName: "#14 HPV Fasteners", brand: "Versico", itemNumber: "124278",
    currentSKU: { itemNumber: "124278", currentUOM: "PL",
      variantName: "Versico 6 in #14 HPV Fasteners 1,000 carton",
      variations: { packaging: ["1,000 carton"] } } }] });
  assert.deepStrictEqual(i, {
    itemNumber: "124278", productName: "Versico 6 in #14 HPV Fasteners 1,000 carton",
    internalProductName: "#14 HPV Fasteners", brand: "Versico", productId: "C-124270",
    packQty: 1000, uom: "PL" });
});

test("gateway errors carry stage and fail without key", async () => {
  await assert.rejects(callGateway("/x", {}, { apiKey: "" }), /not configured/);
  const fetchImpl = async () => ({ ok: false, status: 500, json: async () => ({ ok: false, stage: "auth", error: "expired" }) });
  await assert.rejects(callGateway("/x", {}, { apiKey: "k", fetchImpl }), /auth: expired/);
});
