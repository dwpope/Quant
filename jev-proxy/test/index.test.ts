import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";

const KEY = "sk-typesafe-secret-value-0001";
const env = { TYPESAFE_KEY: KEY } as any;

const valid = {
  head_yaw_degrees: 3.2,
  head_pitch_degrees: -8.1,
  head_roll_degrees: 1,
  forward_creep_fraction_of_baseline_shoulder_width: 0.12,
  head_drop_in_shoulder_widths: 0.04,
  shoulder_rounding_degrees: 6,
  lateral_lean_signed_normalised: 0.08,
  twist_signed_degrees: 12,
  torso_angle_degrees: 4,
  tracking_quality: "good",
};

const post = (body: unknown, path = "/classify") =>
  new Request(`https://proxy.example${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

const upstreamOK = () =>
  vi.fn(async () =>
    new Response(
      JSON.stringify({
        model: "jev-1.13.0",
        answers: {
          posture: {
            type: "choice",
            choice: "chair_swivel",
            probabilities: { chair_swivel: 0.81, lean: 0.12, slouch: 0.04, good_posture: 0.02, ambiguous: 0.01 },
            confidence: 0.81,
          },
        },
        usage: { input_tokens: 300, output_tokens: 20 },
      }),
      { status: 200, headers: { "content-type": "application/json", "x-typesafe-request-id": "req_abc" } },
    ),
  );

afterEach(() => vi.unstubAllGlobals());

describe("routing", () => {
  it("rejects anything but POST", async () => {
    const r = await worker.fetch(new Request("https://proxy.example/classify"), env);
    expect(r.status).toBe(405);
  });

  it("rejects an unknown path", async () => {
    const r = await worker.fetch(post(valid, "/"), env);
    expect(r.status).toBe(404);
  });
});

describe("fail closed", () => {
  it("returns 503 and makes NO upstream call when the key is unset", async () => {
    const f = upstreamOK();
    vi.stubGlobal("fetch", f);
    const r = await worker.fetch(post(valid), {} as any);
    expect(r.status).toBe(503);
    expect(f).not.toHaveBeenCalled();
  });

  it("returns 400 for an invalid payload without calling upstream", async () => {
    const f = upstreamOK();
    vi.stubGlobal("fetch", f);
    const r = await worker.fetch(post({ ...valid, head_yaw_degrees: "x" }), env);
    expect(r.status).toBe(400);
    expect(f).not.toHaveBeenCalled();
  });

  it("returns 413 for an oversized body without calling upstream", async () => {
    const f = upstreamOK();
    vi.stubGlobal("fetch", f);
    const r = await worker.fetch(post({ ...valid, junk: "x".repeat(200_000) }), env);
    expect(r.status).toBe(413);
    expect(f).not.toHaveBeenCalled();
  });
});

describe("the happy path", () => {
  it("sends the bearer token upstream and returns the mapped classification", async () => {
    const f = upstreamOK();
    vi.stubGlobal("fetch", f);

    const r = await worker.fetch(post(valid), env);
    expect(r.status).toBe(200);
    expect(await r.json()).toMatchObject({ posture: "chair_swivel", confidence: 0.81 });

    const [url, init] = f.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://api.typesafe.ai/v1/systemone");
    expect((init.headers as Record<string, string>).Authorization).toBe(`Bearer ${KEY}`);
    // The rubric is ours, server-side, so the app cannot send its own.
    expect(JSON.parse(init.body as string).questions.posture.criteria).toHaveProperty("chair_swivel");
  });

  it("echoes the upstream request id for debugging", async () => {
    vi.stubGlobal("fetch", upstreamOK());
    const r = await worker.fetch(post(valid), env);
    expect(r.headers.get("x-typesafe-request-id")).toBe("req_abc");
  });
});

describe("upstream failures", () => {
  it("passes 429 and 529 through so the client can back off", async () => {
    for (const status of [429, 529]) {
      vi.stubGlobal("fetch", vi.fn(async () => new Response("slow down", { status })));
      const r = await worker.fetch(post(valid), env);
      expect(r.status, `status ${status}`).toBe(status);
    }
  });

  it("returns 502 when upstream returns something unmappable", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ answers: {} }), { status: 200 })));
    const r = await worker.fetch(post(valid), env);
    expect(r.status).toBe(502);
  });

  it("NEVER leaks the key, in any response", async () => {
    const cases: Array<() => void> = [
      () => vi.stubGlobal("fetch", vi.fn(async () => new Response(`upstream said ${KEY}`, { status: 500 }))),
      () => vi.stubGlobal("fetch", vi.fn(async () => { throw new Error(`connect failed with ${KEY}`); })),
      () => vi.stubGlobal("fetch", vi.fn(async () => new Response("{", { status: 200 }))),
    ];
    for (const stub of cases) {
      stub();
      const r = await worker.fetch(post(valid), env);
      expect(await r.text()).not.toContain(KEY);
      vi.unstubAllGlobals();
    }
  });
});
