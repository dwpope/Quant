/**
 * Pure request/response logic for the Jev posture proxy.
 *
 * Deliberately free of Worker APIs so it can be unit-tested directly; src/index.ts is a thin
 * shell over it. Same seam discipline as the Swift side.
 */

/** The question id Jev answers under. Stable, because the app keys off it. */
export const QUESTION_ID = "posture" as const;

export const TRACKING_QUALITY = ["good", "degraded", "poor", "lost"] as const;
export type TrackingQuality = (typeof TRACKING_QUALITY)[number];

/**
 * The five posture classes, as a Jev `choice` rubric.
 *
 * This text is the product. It lives here rather than in the app precisely so it can be revised
 * and re-measured without an app rebuild — which is what the evaluation loop needs.
 *
 * Two constraints from the Jev docs shape it. Descriptions must *separate the options from each
 * other*, so each one says what distinguishes it from its nearest neighbour rather than merely
 * describing itself. And Jev has no built-in abstain class — `probabilities` always sums to 1
 * over the options supplied — so `ambiguous` has to be an explicit option.
 */
export const POSTURE_CRITERIA: Record<string, string> = {
  good_posture:
    "Sitting upright, close to the calibration baseline. Forward creep and head drop are near zero, shoulder rounding is small, and there is no sustained lean or twist.",
  slouch:
    "Collapsed forward or downward relative to baseline: positive forward creep and/or head drop, usually with increased shoulder rounding. The torso sags toward the screen rather than tipping to one side.",
  lean:
    "The torso is displaced to one side while otherwise upright: lateral lean is clearly non-zero and holds its sign, without the forward collapse that marks a slouch.",
  chair_swivel:
    "The whole body has rotated in the chair rather than the posture degrading. Twist is large and lateral lean follows it, while forward creep and head drop stay near baseline. This is a comfortable, neutral posture seen off-axis — not bad posture. Choose this over 'lean' when the lean is explained by the rotation.",
  ambiguous:
    "The signals disagree with each other, or tracking quality is degraded enough that the options above cannot be told apart. Prefer this over guessing; the caller gates on confidence and will fall back to its own thresholds.",
};

/**
 * Every delta the app sends is relative to a calibration snapshot, in units that mean nothing
 * on their own. Stating that in the payload is not decoration: without a frame of reference a
 * prose rubric has nothing to bind the numbers to.
 */
export const BASELINE_NOTE =
  "All *_relative values are deltas from a calibration baseline captured while the user sat upright; 0 means exactly at baseline. Angles are degrees. Signed values carry direction: positive lateral lean is one side, negative the other.";

const NUMERIC_FIELDS = [
  "head_yaw_degrees",
  "head_pitch_degrees",
  "head_roll_degrees",
  "forward_creep_fraction_of_baseline_shoulder_width",
  "head_drop_in_shoulder_widths",
  "shoulder_rounding_degrees",
  "lateral_lean_signed_normalised",
  "twist_signed_degrees",
  "torso_angle_degrees",
] as const;

export type Features = { [K in (typeof NUMERIC_FIELDS)[number]]: number } & {
  tracking_quality: TrackingQuality;
  depth_mode?: string;
};

export type Parsed = { ok: true; features: Features } | { ok: false; error: string };

/**
 * Validate and NARROW the incoming body.
 *
 * Unknown keys are dropped rather than rejected: it keeps the app free to evolve, and it bounds
 * what this endpoint will forward to a paid API no matter what is sent to it — which matters
 * while the Worker is unauthenticated.
 */
export function parseFeatures(body: unknown): Parsed {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, error: "body must be a JSON object" };
  }
  const src = body as Record<string, unknown>;
  const out: Record<string, unknown> = {};

  for (const key of NUMERIC_FIELDS) {
    const v = src[key];
    if (typeof v !== "number" || !Number.isFinite(v)) {
      return { ok: false, error: `${key} must be a finite number` };
    }
    out[key] = v;
  }

  const q = src.tracking_quality;
  if (typeof q !== "string" || !(TRACKING_QUALITY as readonly string[]).includes(q)) {
    return { ok: false, error: `tracking_quality must be one of ${TRACKING_QUALITY.join(", ")}` };
  }
  out.tracking_quality = q;

  if (typeof src.depth_mode === "string" && src.depth_mode.length <= 32) {
    out.depth_mode = src.depth_mode;
  }

  return { ok: true, features: out as Features };
}

export interface JevRequest {
  state: Record<string, unknown>;
  model: string;
  questions: Record<string, { type: string; instructions: string; criteria: Record<string, string> }>;
}

export function buildJevRequest(features: Features): JevRequest {
  return {
    state: { ...features, baseline_note: BASELINE_NOTE },
    model: "jev-latest",
    questions: {
      [QUESTION_ID]: {
        type: "choice",
        instructions:
          "Classify this seated posture from the sensor deltas. Judge the posture itself, not whether the numbers are large: a rotation in the chair is not bad posture.",
        criteria: POSTURE_CRITERIA,
      },
    },
  };
}

export interface Classification {
  posture: string;
  confidence: number;
  probabilities: Record<string, number>;
  model: string;
}

export type Mapped = { ok: true; result: Classification } | { ok: false; error: string };

export function mapJevAnswer(json: unknown): Mapped {
  if (typeof json !== "object" || json === null) return { ok: false, error: "response was not an object" };
  const root = json as Record<string, any>;
  const answer = root.answers?.[QUESTION_ID];
  if (!answer) return { ok: false, error: `no '${QUESTION_ID}' answer in response` };
  if (answer.type !== "choice") return { ok: false, error: `expected a choice answer, got '${answer.type}'` };
  if (typeof answer.choice !== "string" || typeof answer.confidence !== "number") {
    return { ok: false, error: "choice answer was missing choice or confidence" };
  }
  return {
    ok: true,
    result: {
      posture: answer.choice,
      confidence: answer.confidence,
      probabilities: answer.probabilities ?? {},
      model: typeof root.model === "string" ? root.model : "unknown",
    },
  };
}
