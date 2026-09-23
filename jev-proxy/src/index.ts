/**
 * jev-proxy — holds the TypeSafe Jev key so the Aware app never does.
 *
 * The app sends posture features; this Worker adds `Authorization: Bearer $TYPESAFE_KEY` and
 * forwards to Jev. That makes the key's absence from the app structural rather than procedural:
 * there is no delivery channel to secure, nothing in the bundle, nothing in `strings`, and
 * nothing credential-shaped in the repo.
 *
 * The rubric lives here too (src/classify.ts), so the `criteria` prose can be revised and
 * re-measured without rebuilding and reinstalling the app.
 *
 * Deliberate properties:
 *   - Fail closed. No key ⇒ 503 and NO upstream call, never a request with empty auth.
 *   - Never echo the key. Upstream bodies and thrown errors are not passed through verbatim.
 *   - Never log payloads. Posture features are personal data; only status and request id.
 *   - Pass 429 and 529 through, so the client's exponential backoff has something to act on.
 *   - Bound the input. Unknown keys are dropped and oversized bodies rejected, because this
 *     endpoint is unauthenticated and its URL is extractable from the app binary.
 */
import { buildJevRequest, mapJevAnswer, parseFeatures } from "./classify";

const UPSTREAM = "https://api.typesafe.ai/v1/systemone";
const PATH = "/classify";

/** Generous for ~10 numeric fields; far below Jev's 32k-token state budget. */
const MAX_BODY_BYTES = 8 * 1024;

export interface Env {
  TYPESAFE_KEY?: string;
}

const json = (body: unknown, status: number, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== PATH) return json({ error: "not found" }, 404);
    if (request.method !== "POST") return json({ error: "method not allowed" }, 405);

    // Fail closed before anything else, so a misconfigured Worker cannot make a request with
    // empty credentials and cannot be told apart from a working one by probing.
    const key = env.TYPESAFE_KEY;
    if (!key || key.trim().length === 0) {
      return json({ error: "proxy is not configured" }, 503);
    }

    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) return json({ error: "payload too large" }, 413);

    let body: unknown;
    try {
      body = JSON.parse(raw);
    } catch {
      return json({ error: "body was not valid JSON" }, 400);
    }

    const parsed = parseFeatures(body);
    if (!parsed.ok) return json({ error: parsed.error }, 400);

    let upstream: Response;
    try {
      upstream = await fetch(UPSTREAM, {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "content-type": "application/json" },
        body: JSON.stringify(buildJevRequest(parsed.features)),
      });
    } catch {
      // Swallow the thrown error rather than reporting it: a network error message can quote
      // the request that produced it, and that request carries the key.
      return json({ error: "upstream unreachable" }, 502);
    }

    const requestId = upstream.headers.get("x-typesafe-request-id") ?? "";
    const idHeader: Record<string, string> = requestId ? { "x-typesafe-request-id": requestId } : {};

    // Pass rate limiting and overload straight through; the client backs off on these.
    if (upstream.status === 429 || upstream.status === 529) {
      return json({ error: "upstream busy", status: upstream.status }, upstream.status, idHeader);
    }

    if (!upstream.ok) {
      // Report the status, never the body: an upstream error body can echo the request.
      console.log(`upstream ${upstream.status} req=${requestId}`);
      return json({ error: "upstream error", status: upstream.status }, 502, idHeader);
    }

    let payload: unknown;
    try {
      payload = await upstream.json();
    } catch {
      return json({ error: "upstream returned invalid JSON" }, 502, idHeader);
    }

    const mapped = mapJevAnswer(payload);
    if (!mapped.ok) return json({ error: mapped.error }, 502, idHeader);

    return json(mapped.result, 200, idHeader);
  },
};
