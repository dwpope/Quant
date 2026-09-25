import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";

const KEY = "sk-typesafe-secret-value-0001";

const valid = {
  head_yaw_degrees: 2,
  head_pitch_degrees: -14,
  head_roll_degrees: 0.5,
  forward_creep_fraction_of_baseline_shoulder_width: 0.22,
  head_drop_in_shoulder_widths: 0.18,
  torso_lean_delta_degrees: 11,
  lateral_lean_in_shoulder_widths: 0.05,
  shoulder_tilt_signed_degrees: 1,
  torso_angle_degrees: 9,
  tracking_quality: "good",
};

/** Records the keys it was asked about and answers from a script. */
const limiter = (allow: boolean) => ({
  calls: [] as string[],
  async limit({ key }: { key: string }) {
    this.calls.push(key);
    return { success: allow };
  },
});

const post = (ip?: string) =>
  new Request("https://proxy.example/classify", {
    method: "POST",
    headers: ip
      ? { "content-type": "application/json", "cf-connecting-ip": ip }
      : { "content-type": "application/json" },
    body: JSON.stringify(valid),
  });

const upstreamOK = () =>
  vi.fn(async () =>
    new Response(
      JSON.stringify({
        model: "jev-1.13.0",
        answers: { posture: { type: "choice", choice: "slouch", probabilities: { slouch: 1 }, confidence: 1 } },
        usage: { input_tokens: 1, output_tokens: 1 },
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    ),
  );

afterEach(() => vi.unstubAllGlobals());

describe("rate limiting", () => {
  it("lets a request through when under the limit", async () => {
    const f = upstreamOK();
    vi.stubGlobal("fetch", f);
    const rl = limiter(true);

    const r = await worker.fetch(post("203.0.113.7"), { TYPESAFE_KEY: KEY, RATE_LIMITER: rl } as any);

    expect(r.status).toBe(200);
    expect(f).toHaveBeenCalledOnce();
  });

  it("returns 429 when over the limit, and makes NO upstream call", async () => {
    const f = upstreamOK();
    vi.stubGlobal("fetch", f);

    const r = await worker.fetch(post("203.0.113.7"), { TYPESAFE_KEY: KEY, RATE_LIMITER: limiter(false) } as any);

    expect(r.status).toBe(429);
    expect(f).not.toHaveBeenCalled();
    expect(await r.json()).toMatchObject({ error: expect.stringContaining("rate") });
  });

  it("tells the client when to come back", async () => {
    vi.stubGlobal("fetch", upstreamOK());
    const r = await worker.fetch(post("203.0.113.7"), { TYPESAFE_KEY: KEY, RATE_LIMITER: limiter(false) } as any);
    expect(r.headers.get("retry-after")).toBe("60");
  });

  it("keys on the client IP", async () => {
    vi.stubGlobal("fetch", upstreamOK());
    const rl = limiter(true);

    await worker.fetch(post("198.51.100.42"), { TYPESAFE_KEY: KEY, RATE_LIMITER: rl } as any);

    expect(rl.calls).toEqual(["198.51.100.42"]);
  });

  /// Without a key every caller would share one bucket, so a single flood would lock everyone
  /// out. A distinct constant is still one shared bucket, but it is an explicit, documented one
  /// rather than an accident — and CF-Connecting-IP is always present on a real Cloudflare
  /// request, so this only fires off-platform.
  it("falls back to a marked key when the IP header is absent", async () => {
    vi.stubGlobal("fetch", upstreamOK());
    const rl = limiter(true);

    await worker.fetch(post(), { TYPESAFE_KEY: KEY, RATE_LIMITER: rl } as any);

    expect(rl.calls).toEqual(["no-ip"]);
  });

  /// The limit is checked before the key check, so a flood against a misconfigured proxy is
  /// still cheap to reject. 503 would mean we did the configuration work first.
  it("rate-limits before it checks whether the proxy is configured", async () => {
    const f = upstreamOK();
    vi.stubGlobal("fetch", f);

    const r = await worker.fetch(post("203.0.113.7"), { RATE_LIMITER: limiter(false) } as any);

    expect(r.status).toBe(429);
    expect(f).not.toHaveBeenCalled();
  });

  /// The binding is declared in wrangler.toml so it is always present in deployment. It is
  /// absent only in unit tests and in `wrangler dev` without the binding, where limiting is
  /// not the thing under test.
  it("proceeds when no limiter is bound at all", async () => {
    const f = upstreamOK();
    vi.stubGlobal("fetch", f);

    const r = await worker.fetch(post("203.0.113.7"), { TYPESAFE_KEY: KEY } as any);

    expect(r.status).toBe(200);
    expect(f).toHaveBeenCalledOnce();
  });

  it("does not rate-limit a request it would reject on routing anyway", async () => {
    const rl = limiter(false);
    const r = await worker.fetch(new Request("https://proxy.example/"), { RATE_LIMITER: rl } as any);

    expect(r.status).toBe(404);
    expect(rl.calls).toEqual([]);
  });
});
