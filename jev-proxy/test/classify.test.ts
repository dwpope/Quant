import { describe, expect, it } from "vitest";
import {
  POSTURE_CRITERIA,
  QUESTION_ID,
  buildJevRequest,
  mapJevAnswer,
  parseFeatures,
} from "../src/classify";

const valid = {
  head_yaw_degrees: 3.2,
  head_pitch_degrees: -8.1,
  head_roll_degrees: 1,
  forward_creep_fraction_of_baseline_shoulder_width: 0.12,
  head_drop_in_shoulder_widths: 0.04,
  torso_lean_delta_degrees: 6,
  lateral_lean_in_shoulder_widths: 0.08,
  shoulder_tilt_signed_degrees: 12,
  torso_angle_degrees: 4,
  tracking_quality: "good",
};

describe("parseFeatures", () => {
  it("rejects a body that is not an object", () => {
    expect(parseFeatures("nope").ok).toBe(false);
    expect(parseFeatures(null).ok).toBe(false);
    expect(parseFeatures([1, 2]).ok).toBe(false);
  });

  it("rejects a missing required field", () => {
    const { head_pitch_degrees, ...missing } = valid;
    const r = parseFeatures(missing);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toContain("head_pitch_degrees");
  });

  it("rejects non-finite numbers", () => {
    expect(parseFeatures({ ...valid, head_yaw_degrees: NaN }).ok).toBe(false);
    expect(parseFeatures({ ...valid, head_yaw_degrees: Infinity }).ok).toBe(false);
    expect(parseFeatures({ ...valid, head_yaw_degrees: "3.2" }).ok).toBe(false);
  });

  it("rejects an unknown tracking_quality", () => {
    expect(parseFeatures({ ...valid, tracking_quality: "excellent" }).ok).toBe(false);
  });

  // Bounds what an unauthenticated endpoint will forward, whatever is sent to it.
  it("drops unknown keys rather than forwarding them", () => {
    const r = parseFeatures({ ...valid, padding: "x".repeat(5000), nested: { a: 1 } });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.features).not.toHaveProperty("padding");
      expect(r.features).not.toHaveProperty("nested");
    }
  });

  it("accepts a valid payload", () => {
    const r = parseFeatures(valid);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.features.head_pitch_degrees).toBe(-8.1);
  });
});

describe("buildJevRequest", () => {
  const req = buildJevRequest(parseFeatures(valid).ok ? (parseFeatures(valid) as any).features : ({} as any));

  it("asks one choice question under a stable id", () => {
    expect(req.model).toBe("jev-latest");
    expect(Object.keys(req.questions)).toEqual([QUESTION_ID]);
    expect(req.questions[QUESTION_ID].type).toBe("choice");
  });

  it("offers the five posture classes plus an explicit ambiguous option", () => {
    // Jev has no built-in abstain class: probabilities always sum to 1 over the options
    // supplied, so 'ambiguous' has to be one of them.
    expect(Object.keys(req.questions[QUESTION_ID].criteria).sort()).toEqual(
      ["ambiguous", "chair_swivel", "good_posture", "lean", "slouch"],
    );
  });

  it("gives every class a non-empty rubric description", () => {
    for (const [name, desc] of Object.entries(POSTURE_CRITERIA)) {
      expect(desc, name).toBeTruthy();
      expect((desc as string).length, name).toBeGreaterThan(20);
    }
  });

  // The metrics are baseline-relative deltas in unusual units. Without saying so, a prose
  // rubric has no frame of reference and the classification is meaningless.
  it("states the baseline frame of reference in the state it sends", () => {
    expect(JSON.stringify(req.state)).toMatch(/baseline/i);
  });

  it("stays far inside Jev's 32k-token state budget", () => {
    expect(JSON.stringify(req.state).length).toBeLessThan(4000);
  });
});

describe("mapJevAnswer", () => {
  const answer = {
    model: "jev-1.13.0",
    answers: {
      posture: {
        type: "choice",
        choice: "slouch",
        probabilities: { slouch: 0.72, good_posture: 0.2, lean: 0.05, chair_swivel: 0.02, ambiguous: 0.01 },
        confidence: 0.72,
      },
    },
    usage: { input_tokens: 296, output_tokens: 20 },
  };

  it("maps a choice answer to a classification", () => {
    const r = mapJevAnswer(answer);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.result.posture).toBe("slouch");
      expect(r.result.confidence).toBeCloseTo(0.72);
      expect(r.result.probabilities.slouch).toBeCloseTo(0.72);
      expect(r.result.model).toBe("jev-1.13.0");
    }
  });

  it("errors when the expected answer is absent", () => {
    expect(mapJevAnswer({ model: "m", answers: {} }).ok).toBe(false);
  });

  it("errors when the answer is not a choice", () => {
    const noul = { model: "m", answers: { posture: { type: "noul", noul: 0.9 } } };
    expect(mapJevAnswer(noul).ok).toBe(false);
  });
});
