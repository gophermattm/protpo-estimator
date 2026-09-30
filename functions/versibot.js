// VersiBot: RAG over Versico spec documents (Firestore `versico_technical_data`,
// 768-dim text-embedding-004 vectors) + Claude for the audit / nl / sow modes.
// Port of the Python askVersico (~/dev/_archive/protpo-python/functions/main.py)
// with current models — gemini-2.0-flash-001 and claude-sonnet-4-20250514 were
// retired, which broke every VersiBot mode. Responses keep the old shapes.

const PROJECT_ID = "tpo-pro-245d1";
const LOCATION = "us-central1";
const EMBED_MODEL = "text-embedding-004";
const GEMINI_MODEL = "gemini-2.5-flash";
const CLAUDE_MODEL = "claude-sonnet-5";

const VERTEX = `https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/publishers/google/models`;

function buildPrompt(contextText, question) {
  return (
    "You are VersiBot, a senior roofing engineer. Your goal is to synthesize an answer " +
    "from the provided technical documentation snippets. Many questions require combining " +
    "details from different pages (e.g., insulation R-values + fastening patterns + wall details).\n\n" +
    "If the data contains R-value per inch, perform the math for the user. " +
    "If multiple documents provide different parts of the system (fasteners vs. drains), " +
    "combine them into a cohesive roofing assembly guide.\n\n" +
    `TECHNICAL CONTEXT:\n${contextText}\n\n` +
    `USER QUESTION: ${question}`
  );
}

// Context text + de-duplicated "file (Page n)" labels from Firestore hits.
function shapeHits(docs) {
  const parts = [];
  const sources = [];
  for (const d of docs) {
    parts.push(d.content || "No content available.");
    const label = `${d.source_file || "Unknown Document"} (Page ${d.page_number ?? "N/A"})`;
    if (!sources.includes(label)) sources.push(label);
  }
  return { contextText: parts.join("\n---\n"), sources };
}

async function vertexPost(path, body, accessToken, fetchImpl = fetch) {
  const res = await fetchImpl(`${VERTEX}/${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Vertex ${path.split(":")[0]} ${res.status}: ${json.error?.message || "request failed"}`);
  return json;
}

async function embed(question, accessToken, fetchImpl) {
  const json = await vertexPost(`${EMBED_MODEL}:predict`, {
    instances: [{ content: question }],
    parameters: { outputDimensionality: 768 },
  }, accessToken, fetchImpl);
  return json.predictions[0].embeddings.values;
}

async function generate(prompt, accessToken, fetchImpl) {
  const json = await vertexPost(`${GEMINI_MODEL}:generateContent`, {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
  }, accessToken, fetchImpl);
  const parts = json.candidates?.[0]?.content?.parts || [];
  return parts.map((p) => p.text || "").join("");
}

async function claude({ prompt, system, maxTokens, apiKey, fetchImpl = fetch }) {
  const body = { model: CLAUDE_MODEL, max_tokens: maxTokens, messages: [{ role: "user", content: prompt }] };
  if (system) body.system = system;
  const res = await fetchImpl("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Claude ${res.status}: ${json.error?.message || "request failed"}`);
  return (json.content || []).filter((c) => c.type === "text").map((c) => c.text).join("");
}

module.exports = { buildPrompt, shapeHits, embed, generate, claude, EMBED_MODEL, GEMINI_MODEL, CLAUDE_MODEL };
