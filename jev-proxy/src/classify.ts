/**
 * Pure request/response logic for the Jev posture proxy.
 *
 * Deliberately free of Worker APIs so it can be unit-tested directly; src/index.ts is a thin
 * shell over it. Same seam discipline as the Swift side.
 */

/** The question id Jev answers under. Stable, because the app keys off it. */
export const QUESTION_ID = "posture" as const;

// Exactly PostureLogic's TrackingQuality cases (TrackingQuality.swift:1-4). "poor" was in the
// first draft and is unreachable from Swift; an accepted-but-impossible value is a lie.
export const TRACKING_QUALITY = ["good", "degraded", "lost"] as const;
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
    "Sitting upright, close to the calibration baseline. forward_creep, head_drop and torso_lean_delta are all near zero and lateral lean is small.",
  slouch:
    "Collapsed toward the screen or downward. forward_creep is clearly POSITIVE (the shoulders appear wider because the torso moved closer to the camera) and/or head_drop is positive, usually with a positive torso_lean_delta. Lateral lean is not the story.",
  lean:
    "The torso has translated sideways while staying square to the camera. lateral_lean_in_shoulder_widths is clearly non-zero and holds its sign, while forward_creep stays near zero — a sideways shift barely changes apparent shoulder width.",
  chair_swivel:
    "The whole body has ROTATED in the chair rather than the posture degrading. The tell is a NEGATIVE forward_creep together with a non-zero lateral lean: rotating about the vertical axis foreshortens the shoulders, so they appear NARROWER than baseline, while the midpoint shifts sideways. head_drop stays near zero. This is a comfortable neutral posture seen off-axis, not bad posture — prefer it over 'lean' whenever forward_creep is negative rather than near zero.",
  ambiguous:
    "The signals disagree with each other, or tracking_quality is 'degraded' or 'lost' so the values cannot be trusted. Prefer this over guessing; the caller gates on confidence and falls back to its own thresholds.",
};

/**
 * Every delta the app sends is relative to a calibration snapshot, in units that mean nothing
 * on their own. Stating that in the payload is not decoration: without a frame of reference a
 * prose rubric has nothing to bind the numbers to.
 */
export const BASELINE_NOTE = [
  "All values except the head angles and torso_angle are deltas from a calibration snapshot taken while the user sat upright; 0 means exactly at baseline.",
  "forward_creep is the fractional change in APPARENT shoulder width: positive means the shoulders look wider (torso closer to the camera), negative means narrower (torso rotated away from square).",
  "head_drop is in shoulder-widths; positive means the head is carried lower than baseline.",
  "lateral_lean_in_shoulder_widths is the sideways shift of the shoulder midpoint, divided by baseline shoulder width so it is dimensionless in both camera modes.",
  "shoulder_tilt_signed_degrees is one shoulder higher than the other, not axial rotation.",
  "torso_lean_delta_degrees is the change in torso lean angle, not shoulder protraction.",
  "torso_angle_degrees is camera-absolute, not a delta, and when the hips are out of frame it is a clamped proxy derived from head-to-shoulder height rather than a measured angle. Weigh it lightly.",
  "Head angles are camera-absolute degrees and read 0 both when centred and when unavailable.",
].join(" ");

const NUMERIC_FIELDS = [
  "head_yaw_degrees",
  "head_pitch_degrees",
  "head_roll_degrees",
  "forward_creep_fraction_of_baseline_shoulder_width",
  "head_drop_in_shoulder_widths",
  "torso_lean_delta_degrees",
  "lateral_lean_in_shoulder_widths",
  "shoulder_tilt_signed_degrees",
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
