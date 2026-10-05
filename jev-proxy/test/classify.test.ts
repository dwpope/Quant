import { describe, expect, it } from "vitest";
import {
  POSTURE_CRITERIA,
  QUESTION_ID,
  LEAN_CLEAR_SHIFT,
  SLOUCH_MIN_FORWARD_CREEP,
  SLOUCH_MAX_HEAD_DROP,
  HEAD_DROP_SLOUCH_MAX_SHIFT,
  SWIVEL_MAX_FORWARD_CREEP,
  SWIVEL_MIN_HEAD_YAW,
  isSwivelByRule,
  isClearLeanByRule,
  isLookingAwayByRule,
  isSlouchByRule,
  SLOUCH_MIN_SHOULDER_SINK,
  buildJevRequest,
  mapJevAnswer,
  parseFeatures,
  BASELINE_NOTE,
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

// Swivel wording v3 (2026-10-03), from two device sessions. v2 required forward creep below
// -0.12 and so called two of session 2's three swivels "lean": they narrowed the shoulders by
// only 5% and 10%. Narrowing alone can't separate lean from swivel (a session-1 lean narrowed
// 7%). Head yaw paired with narrowing does: swivels turned the head 60-77 degrees with the
// shoulders narrower; leans stayed at or under 39 degrees; head turns reached 60-75 degrees but
// with the shoulders WIDER than baseline.
describe("chair_swivel vs lean and a turned head (v3)", () => {
  // Every lean, swivel and head turn measured on device so far: [forward creep, head yaw].
  const swivels: Array<[number, number]> = [[-0.399, 70], [-0.052, -77], [-0.103, 60], [-0.161, -76]];
  const leans: Array<[number, number]> = [[-0.068, 39], [0.006, 28], [0.085, -13], [0.092, -3]];
  const headTurns: Array<[number, number]> = [[0.162, -75], [0.139, 60]];

  it("puts the head-yaw cut between the leans and the swivels", () => {
    expect(SWIVEL_MIN_HEAD_YAW).toBeGreaterThan(39);
    expect(SWIVEL_MIN_HEAD_YAW).toBeLessThan(60);
  });

  it("puts the narrowing cut above the weakest swivel and below baseline width", () => {
    expect(SWIVEL_MAX_FORWARD_CREEP).toBeGreaterThan(-0.052);
    expect(SWIVEL_MAX_FORWARD_CREEP).toBeLessThan(0);
  });

  it("the rule separates every capture measured so far", () => {
    for (const [fc, yaw] of swivels) expect(isSwivelByRule(fc, yaw), `${fc} ${yaw}`).toBe(true);
    for (const [fc, yaw] of leans) expect(isSwivelByRule(fc, yaw), `${fc} ${yaw}`).toBe(false);
    for (const [fc, yaw] of headTurns) expect(isSwivelByRule(fc, yaw), `${fc} ${yaw}`).toBe(false);
  });

  it("states both swivel conditions, with the same numbers the rule uses", () => {
    expect(POSTURE_CRITERIA.chair_swivel).toContain(String(SWIVEL_MIN_HEAD_YAW));
    expect(POSTURE_CRITERIA.chair_swivel).toContain(String(SWIVEL_MAX_FORWARD_CREEP));
    expect(POSTURE_CRITERIA.chair_swivel).toMatch(/BOTH/);
    expect(POSTURE_CRITERIA.chair_swivel).toMatch(/head_yaw_degrees/);
  });

  it("still says a turned head on its own is not a swivel", () => {
    expect(POSTURE_CRITERIA.chair_swivel).toMatch(/looking away/);
  });

  // Two session-2 leans moved the shoulders towards the phone as well as sideways (shift 0.37
  // and 0.10, forward creep +0.085 and +0.092) and both read as slouch.
  it("calls a clear sideways shift a lean even with mild forward creep", () => {
    expect(LEAN_CLEAR_SHIFT).toBeGreaterThan(0.102);
    expect(LEAN_CLEAR_SHIFT).toBeLessThan(0.355);
    expect(POSTURE_CRITERIA.lean).toContain(String(LEAN_CLEAR_SHIFT));
    expect(POSTURE_CRITERIA.lean).toContain(String(SWIVEL_MIN_HEAD_YAW));
  });

  // Replay of both sessions: adding the lean rule to the slouch description turned four clear
  // slouches into good_posture. It belongs to the lean description alone.
  it("keeps the slouch description free of the lean rule", () => {
    expect(POSTURE_CRITERIA.slouch).not.toContain(String(LEAN_CLEAR_SHIFT));
  });
});

// v3.2: a scale for "clearly positive". With v3's sharper lean and swivel wording, four slouches
// with forward creep +0.14 to +0.18 replayed as good_posture; under v2 they were slouch. Upright
// captures in session 2 sat at +0.024 to +0.042; the weakest real slouch was +0.081.
describe("a numeric scale for slouch and upright (v3.2)", () => {
  it("puts the slouch cut above upright noise and below the weakest slouch", () => {
    expect(SLOUCH_MIN_FORWARD_CREEP).toBeGreaterThan(0.042);
    expect(SLOUCH_MIN_FORWARD_CREEP).toBeLessThan(0.081);
  });

  it("states the cut in both the slouch and the upright descriptions", () => {
    expect(POSTURE_CRITERIA.slouch).toContain(String(SLOUCH_MIN_FORWARD_CREEP));
    expect(POSTURE_CRITERIA.good_posture).toContain(String(SLOUCH_MIN_FORWARD_CREEP));
  });
});

// v3.3: head drop reads NEGATIVE when Dave slouches. Across three sessions all 9 slouches read
// -0.020 to -0.113 while every judged upright read -0.004 or above; the rubric had told Jev a
// slouch makes head_drop positive. (The app's image y runs down, so a dropping head reads
// negative; v3.3 first put it down to the phone below eye level, corrected in v3.8.)
describe("head drop as a slouch signal (v3.3)", () => {
  const uprightHeadDrops = [0.019, 0.013, 0.019, -0.002, -0.002, -0.004];
  const slouchHeadDrops = [-0.061, -0.04, -0.113, -0.02, -0.021, -0.055, -0.02, -0.045, -0.069];

  it("puts the cut between every upright and every slouch measured", () => {
    for (const hd of uprightHeadDrops) expect(hd).toBeGreaterThan(SLOUCH_MAX_HEAD_DROP);
    for (const hd of slouchHeadDrops) expect(hd).toBeLessThanOrEqual(SLOUCH_MAX_HEAD_DROP);
  });

  it("tells Jev the direction this setup actually measures", () => {
    expect(POSTURE_CRITERIA.slouch).toContain(String(SLOUCH_MAX_HEAD_DROP));
    expect(POSTURE_CRITERIA.slouch).toMatch(/NEGATIVE/);
    expect(POSTURE_CRITERIA.slouch).not.toMatch(/head_drop is positive/);
    expect(POSTURE_CRITERIA.good_posture).toContain(String(SLOUCH_MAX_HEAD_DROP));
  });
});

// v3.4: head drop counts towards slouch only when the sideways shift is small. In v3.3, three
// leans (sideways shift 0.136, 0.356, 0.367) also read a negative head drop and became slouch. Every
// slouch so far shifted sideways 0.096 or less.
describe("head drop only for a small sideways shift (v3.4)", () => {
  it("puts the cut above every slouch's shift and below the leans v3.3 broke", () => {
    expect(HEAD_DROP_SLOUCH_MAX_SHIFT).toBeGreaterThan(0.096);
    expect(HEAD_DROP_SLOUCH_MAX_SHIFT).toBeLessThan(0.136);
  });

  it("states the condition in the slouch description, and the exception in the lean one", () => {
    expect(POSTURE_CRITERIA.slouch).toContain(String(HEAD_DROP_SLOUCH_MAX_SHIFT));
    expect(POSTURE_CRITERIA.lean).toMatch(/head_drop/);
  });
});

// v3.5: session 4's lean 9 shifted 0.185 with the head turned 57° and the shoulders not narrowed
// (forward creep +0.007). The lean wording capped head yaw at 45 and the swivel wording needs
// narrowing, so no class fitted and Jev said slouch at 83%. The head often turns while leaning
// (±24-25° on session 4's other two leans), so a clear shift is a lean unless it's a swivel.
describe("a clear shift is a lean whatever the head yaw, unless it's a swivel (v3.5)", () => {
  // Every capture measured on device so far: [sideways shift, forward creep, head yaw].
  const clearLeans: Array<[number, number, number]> = [
    [-0.355, 0.006, 28], [0.367, 0.085, -13], [-0.279, -0.005, 0], [0.356, -0.004, -10],
    [-0.173, 0.056, -4], [-0.314, -0.032, 24], [0.264, -0.04, -25], [-0.185, 0.007, 57],
  ];
  const swivels: Array<[number, number, number]> = [
    [0.118, -0.399, 70], [-0.141, -0.052, -77], [0.034, -0.103, 60], [-0.178, -0.161, -76],
    [0.026, -0.234, -76], [-0.024, -0.069, 60], [0.071, -0.146, -78],
    [-0.182, -0.277, -66], [0.103, -0.274, 60], [-0.064, -0.171, -79],
  ];
  const headTurnsAndSmallSwivels: Array<[number, number, number]> = [
    [-0.052, 0.162, -75], [0.012, 0.139, 60], [0.036, 0.061, 78], [0.037, 0.008, -77],
    [-0.103, 0.06, -75], [-0.013, 0.036, 77], [-0.109, 0.084, -60], [0.037, 0.072, 66],
    [0.051, -0.014, 66], [-0.039, -0.093, -76], [-0.13, -0.053, -71], [-0.017, 0.054, 70],
  ];

  it("calls every clear lean a lean, including the one with the head turned 57°", () => {
    for (const [lat, fc, yaw] of clearLeans) {
      expect(isClearLeanByRule(lat, fc, yaw), `${lat} ${fc} ${yaw}`).toBe(true);
    }
  });

  it("never calls a swivel, a head turn or a small swivel a clear lean", () => {
    for (const [lat, fc, yaw] of [...swivels, ...headTurnsAndSmallSwivels]) {
      expect(isClearLeanByRule(lat, fc, yaw), `${lat} ${fc} ${yaw}`).toBe(false);
    }
  });

  it("drops the blanket head-yaw cap from the lean description", () => {
    expect(POSTURE_CRITERIA.lean).not.toMatch(/head_yaw_degrees stays under/);
  });

  it("names the swivel as the one exception, with the swivel rule's numbers", () => {
    expect(POSTURE_CRITERIA.lean).toContain(String(SWIVEL_MIN_HEAD_YAW));
    expect(POSTURE_CRITERIA.lean).toContain(String(SWIVEL_MAX_FORWARD_CREEP));
  });

  it("still says a small shift with the head turned away is looking away, not a lean", () => {
    expect(POSTURE_CRITERIA.lean).toMatch(/looking away/);
  });
});

// v3.6: three inputs never varied across all 70 captures from five sessions. torso_angle_degrees
// was always 45 and torso_lean_delta_degrees always 0 (the hips are never in frame, so both are a
// clamped proxy), and depth_mode always "twoDOnly". They told Jev nothing and cost it attention.
// The app still sends them; the Worker stops forwarding them.
describe("the three dead inputs are not sent to Jev (v3.6)", () => {
  const dead = ["torso_angle_degrees", "torso_lean_delta_degrees", "depth_mode"];
  const fromTheApp = { ...valid, depth_mode: "twoDOnly" };

  it("accepts today's app payload, which still includes them", () => {
    expect(parseFeatures(fromTheApp).ok).toBe(true);
  });

  it("accepts a payload without them", () => {
    const { torso_angle_degrees, torso_lean_delta_degrees, ...without } = valid;
    expect(parseFeatures(without).ok).toBe(true);
  });

  it("leaves them out of what goes to Jev", () => {
    const r = parseFeatures(fromTheApp);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const state = buildJevRequest(r.features).state;
    for (const key of dead) expect(state, key).not.toHaveProperty(key);
  });

  it("no longer explains them in the baseline note", () => {
    expect(BASELINE_NOTE).not.toMatch(/torso_angle|torso_lean_delta|depth_mode/);
  });

  it("no posture description relies on them", () => {
    for (const [name, desc] of Object.entries(POSTURE_CRITERIA)) {
      expect(desc, name).not.toMatch(/torso_angle|torso_lean|depth_mode/);
    }
  });

  it("still sends everything the wording uses", () => {
    const r = parseFeatures(fromTheApp);
    if (!r.ok) throw new Error(r.error);
    const state = buildJevRequest(r.features).state;
    for (const key of [
      "forward_creep_fraction_of_baseline_shoulder_width", "head_drop_in_shoulder_widths",
      "lateral_lean_in_shoulder_widths", "head_yaw_degrees", "tracking_quality",
    ]) expect(state, key).toHaveProperty(key);
  });
});

// v3.7: looking away is not a slouch. Turning the head reads the shoulders wider (6 of 8 head
// turns +0.06 to +0.16), so with the head turned and the shoulders square, forward creep alone
// read as slouch: both of session 5's head turns, at 94-97%. Head height separates them: every
// head turn read head_drop -0.003 or above, every slouch -0.013 or below. The app times a head
// held turned on its own (HeadTurnTracker, same 45° and -0.03), so a slouch call there would
// also give the wrong advice.
describe("looking away is not a slouch (v3.7)", () => {
  // Every capture measured on device so far: [forward creep, head drop, sideways shift, head yaw].
  const uprights: Array<[number, number, number, number]> = [
    [0.024, 0.019, -0.011, -2], [0.042, 0.013, -0.017, -1], [0.032, 0.019, -0.013, -2],
    [0.01, -0.002, -0.006, -1], [0.023, -0.002, 0.004, -5], [0.029, -0.004, -0.001, -5],
    [0.014, -0.001, 0.013, -3], [0.044, -0.002, 0.021, -2], [0.036, -0.0, 0.024, -3],
    [0.021, -0.007, 0.002, 0], [0.02, -0.006, 0.007, -1], [0.026, -0.0, -0.002, 0],
  ];
  const slouches: Array<[number, number, number, number]> = [
    [0.157, -0.061, -0.096, -1], [-0.004, -0.04, -0.01, 36], [0.081, -0.113, -0.09, 14],
    [0.136, -0.02, -0.018, 0], [0.179, -0.021, -0.027, -7], [0.182, -0.055, -0.027, -3],
    [0.038, -0.02, 0.012, 0], [0.046, -0.045, -0.011, -2], [0.099, -0.069, 0.027, 4],
    [0.135, -0.034, 0.042, -1], [0.092, -0.186, 0.112, -2], [0.156, -0.094, 0.11, -2],
    [0.092, -0.013, -0.017, 2], [0.162, -0.129, -0.06, -37], [0.214, -0.156, -0.039, 56],
  ];
  const headTurns: Array<[number, number, number, number]> = [
    [0.162, 0.008, -0.052, -75], [0.139, 0.006, 0.012, 60], [0.061, -0.003, 0.036, 78],
    [0.008, 0.009, 0.037, -77], [0.06, 0.008, -0.103, -75], [0.036, 0.006, -0.013, 77],
    [0.119, 0.016, 0.055, 77], [0.082, 0.035, -0.016, -74],
  ];

  it("calls every measured slouch a slouch, including the one with the head turned 56°", () => {
    for (const [fc, hd, lat, yaw] of slouches) {
      expect(isSlouchByRule(fc, hd, lat, yaw), `${fc} ${hd} ${lat} ${yaw}`).toBe(true);
    }
  });

  it("calls no head turn and no upright a slouch", () => {
    for (const [fc, hd, lat, yaw] of [...headTurns, ...uprights]) {
      expect(isSlouchByRule(fc, hd, lat, yaw), `${fc} ${hd} ${lat} ${yaw}`).toBe(false);
    }
  });

  it("finds every head turn looking away, and no swivel", () => {
    for (const [fc, , , yaw] of headTurns) expect(isLookingAwayByRule(fc, yaw)).toBe(true);
    for (const [fc, yaw] of [[-0.399, 70], [-0.052, -77], [-0.279, -60], [-0.048, 60]]) {
      expect(isLookingAwayByRule(fc, yaw), `${fc} ${yaw}`).toBe(false);
    }
  });

  it("tells Jev that forward creep alone isn't a slouch while looking away", () => {
    expect(POSTURE_CRITERIA.slouch).toMatch(/looking away/);
    expect(POSTURE_CRITERIA.good_posture).toMatch(/looking away/);
  });
});


// v3.8: head_drop's explanation corrected (2026-10-05). It goes negative as the head drops towards
// the shoulders because the app's image coordinates run downward, not because the phone sits below
// eye level, as v3.3 had it. The numbers and cuts are unchanged; Jev was told a wrong reason.
describe("head_drop explained by its sign, not by the camera height (v3.8)", () => {
  it("says negative is the head dropping towards the shoulders", () => {
    expect(BASELINE_NOTE).toMatch(/head_drop[^.]*NEGATIVE[^.]*dropped towards the shoulders/);
  });

  it("no longer puts it down to the phone below eye level", () => {
    expect(BASELINE_NOTE).not.toMatch(/eye level/);
    for (const [name, desc] of Object.entries(POSTURE_CRITERIA)) {
      expect(desc, name).not.toMatch(/eye level/);
    }
  });

  it("keeps the same cut", () => {
    expect(SLOUCH_MAX_HEAD_DROP).toBe(-0.015);
  });
});

// v3.9: sinking down in the chair (2026-10-05). The head and shoulders drop together, so neither
// forward creep nor head drop moves. Session 8 measured the shoulders' own drop in the frame:
// sinks +0.086 to +0.103, uprights +0.005 to +0.020, swivels and head turns +0.018 or below.
describe("shoulder sink (v3.9)", () => {
  // Session 8 and its false start: [forward creep, head drop, sideways shift, head yaw, sink].
  const sinks: Array<[number, number, number, number, number]> = [
    [-0.052, 0.002, 0.022, 1, 0.103], [-0.046, 0.006, 0.024, 2, 0.096], [-0.033, 0.004, 0.0, 1, 0.1],
    [-0.08, 0.005, 0.012, 2, 0.088], [-0.083, 0.003, 0.034, 0, 0.086],
  ];
  const uprights: Array<[number, number, number, number, number]> = [
    [0.021, 0.001, 0.005, 2, 0.005], [0.03, 0.001, 0.008, 1, 0.008], [0.024, -0.004, 0.002, 4, 0.02],
    [-0.005, -0.003, 0.013, 1, 0.006], [-0.01, 0.002, 0.009, 0, 0.006], [-0.012, 0.002, 0.009, 0, 0.008],
  ];

  it("puts the line between every upright and every sink", () => {
    expect(SLOUCH_MIN_SHOULDER_SINK).toBeGreaterThan(0.02);
    expect(SLOUCH_MIN_SHOULDER_SINK).toBeLessThan(0.086);
  });

  it("calls every sink a slouch, and no upright", () => {
    for (const [fc, hd, lat, yaw, sink] of sinks) expect(isSlouchByRule(fc, hd, lat, yaw, sink)).toBe(true);
    for (const [fc, hd, lat, yaw, sink] of uprights) expect(isSlouchByRule(fc, hd, lat, yaw, sink)).toBe(false);
  });

  it("works without a sink, as older app builds send", () => {
    expect(isSlouchByRule(0.1, 0, 0, 0)).toBe(true);
    expect(isSlouchByRule(0.01, 0, 0, 0)).toBe(false);
  });

  it("forwards the sink when the app sends it, and nothing when it doesn't", () => {
    const withSink = parseFeatures({ ...valid, shoulder_sink_in_shoulder_widths: 0.1 });
    expect(withSink.ok).toBe(true);
    if (withSink.ok) expect(buildJevRequest(withSink.features).state).toHaveProperty("shoulder_sink_in_shoulder_widths", 0.1);
    const without = parseFeatures(valid);
    expect(without.ok).toBe(true);
    if (without.ok) expect(buildJevRequest(without.features).state).not.toHaveProperty("shoulder_sink_in_shoulder_widths");
  });

  it("rejects a sink that isn't a finite number", () => {
    expect(parseFeatures({ ...valid, shoulder_sink_in_shoulder_widths: NaN }).ok).toBe(false);
    expect(parseFeatures({ ...valid, shoulder_sink_in_shoulder_widths: "0.1" }).ok).toBe(false);
  });

  it("tells Jev what it is and where the line is", () => {
    expect(POSTURE_CRITERIA.slouch).toContain("shoulder_sink_in_shoulder_widths");
    expect(POSTURE_CRITERIA.slouch).toContain(String(SLOUCH_MIN_SHOULDER_SINK));
    expect(BASELINE_NOTE).toMatch(/shoulder_sink[^.]*lower in the frame/);
  });
});

