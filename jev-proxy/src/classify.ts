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
/**
 * Chair swivel, v3 (2026-10-03), from two device sessions.
 *
 * A swivel needs BOTH a head turned past `SWIVEL_MIN_HEAD_YAW` (the head turns with the body)
 * AND shoulders narrower than baseline, forward creep at or below `SWIVEL_MAX_FORWARD_CREEP`
 * (rotation foreshortens them). Each signal alone misleads:
 * - Narrowing alone: v2 required forward creep below -0.12 and called two of session 2's three
 *   swivels "lean"; they narrowed the shoulders by only 5% and 10%, while a session-1 lean
 *   narrowed 7%.
 * - Head yaw alone: session 2's head turns reached 60-75 degrees with the shoulders WIDER than
 *   baseline. Someone looking away is not a swivel.
 * Measured so far: swivels 60-77 degrees with narrowing; leans at most 39 degrees. Four swivels,
 * four leans and two head turns: revise as sessions accumulate. `isSwivelByRule` is the same rule
 * in code, for tests.
 */
export const SWIVEL_MIN_HEAD_YAW = 45;
export const SWIVEL_MAX_FORWARD_CREEP = -0.03;

/**
 * A sideways shift this large is a lean even with mild forward creep: two session-2 leans moved
 * the shoulders towards the phone too (forward creep +0.085, +0.092) and read as slouch. Only
 * with the head below the swivel yaw, since a swivel also shifts the shoulder midpoint.
 */
export const LEAN_CLEAR_SHIFT = 0.15;

/**
 * Where "clearly positive" forward creep starts: shoulders this much wider than baseline is more
 * than they vary sitting still upright. Session 2's upright captures sat at +0.024 to +0.042; the
 * weakest real slouch so far was +0.081. Without a number here, v3's sharper lean and swivel
 * wording left four clear slouches (+0.14 to +0.18) reading as good_posture in replay.
 */
export const SLOUCH_MIN_FORWARD_CREEP = 0.06;

/** The swivel rule above, in code: what the wording tells Jev, made testable. */
export function isSwivelByRule(forwardCreep: number, headYawDegrees: number): boolean {
  return Math.abs(headYawDegrees) >= SWIVEL_MIN_HEAD_YAW && forwardCreep <= SWIVEL_MAX_FORWARD_CREEP;
}

export const POSTURE_CRITERIA: Record<string, string> = {
  good_posture:
    `Sitting upright, close to the calibration baseline. forward_creep stays under ${SLOUCH_MIN_FORWARD_CREEP} (sitting still, it wanders a few hundredths either side of zero), head_drop and torso_lean_delta are near zero and lateral lean is small. The head may be turned: head angles alone do not make a posture bad.`,
  // Kept free of the lean rule: v3 first added it here and four clear slouches dropped to
  // good_posture in replay. The lean rule lives only in the lean description.
  slouch:
    `Collapsed toward the screen or downward. forward_creep is clearly POSITIVE, ${SLOUCH_MIN_FORWARD_CREEP} or more (the shoulders appear wider because the torso moved closer to the camera; slouches so far measured +0.08 to +0.18), and/or head_drop is positive, usually with a positive torso_lean_delta. Lateral lean is not the story.`,
  lean:
    `The torso has shifted sideways. lateral_lean_in_shoulder_widths is clearly non-zero and holds its sign, and head_yaw_degrees stays under ${SWIVEL_MIN_HEAD_YAW} either way. A clear shift, ${LEAN_CLEAR_SHIFT} or more either way, is a lean even if forward_creep is mildly positive: leaning sideways often brings the shoulders a little toward the camera. Shoulders slightly narrower than baseline are fine for a lean when the head is not turned past ${SWIVEL_MIN_HEAD_YAW} degrees.`,
  chair_swivel:
    `The whole body has ROTATED in the chair rather than the posture degrading. It needs BOTH of these: head_yaw_degrees at least ${SWIVEL_MIN_HEAD_YAW} either way, because the head turns with the body, AND forward_creep at or below ${SWIVEL_MAX_FORWARD_CREEP}, because rotating about the vertical axis makes the shoulders look narrower (by 5% to 40% so far). A head turned that far with the shoulders at or wider than baseline (forward_creep above ${SWIVEL_MAX_FORWARD_CREEP}) is someone looking away, not a swivel: judge that pose by the other signals. Narrower shoulders with head_yaw_degrees under ${SWIVEL_MIN_HEAD_YAW} is not a swivel either. The shoulder midpoint usually shifts sideways in a swivel too, so a sideways shift does not make it a lean. head_drop stays near zero. A swivel is a comfortable neutral posture seen off-axis, not bad posture.`,
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
