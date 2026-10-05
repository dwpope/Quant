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
 * the shoulders towards the phone too (forward creep +0.085, +0.092) and read as slouch. Any
 * head yaw, unless it's a swivel by rule, since a swivel also shifts the shoulder midpoint: until
 * v3.5 the head had to stay under the swivel yaw, and session 4's lean with the head turned 57°
 * (shoulders not narrowed) fitted no class and read as slouch.
 */
export const LEAN_CLEAR_SHIFT = 0.15;

/**
 * Where "clearly positive" forward creep starts: shoulders this much wider than baseline is more
 * than they vary sitting still upright. Session 2's upright captures sat at +0.024 to +0.042; the
 * weakest real slouch so far was +0.081. Without a number here, v3's sharper lean and swivel
 * wording left four clear slouches (+0.14 to +0.18) reading as good_posture in replay.
 */
export const SLOUCH_MIN_FORWARD_CREEP = 0.06;

/**
 * Head drop at or below this reads as a slouch. Across three sessions all 9 of Dave's slouches
 * read -0.020 to -0.113 while every judged upright read -0.004 or above. It's negative because the
 * app measures in image coordinates whose y runs down, so a head dropping towards the shoulders
 * comes out negative (v3.3 put it down to the phone sitting below eye level; corrected in v3.8).
 * The wording used to say a slouch makes head_drop positive, and three slouches whose shoulders
 * barely came forward replayed as good_posture at 97-100%.
 */
export const SLOUCH_MAX_HEAD_DROP = -0.015;

/**
 * Head drop counts towards slouch only below this sideways shift. In v3.3 three leans (shift
 * 0.136, 0.356, 0.367) also read a negative head drop and became slouch; every slouch so far shifted
 * sideways 0.096 or less.
 */
export const HEAD_DROP_SLOUCH_MAX_SHIFT = 0.1;

/**
 * Shoulder sink at or above this is a slouch: sinking down in the chair, where the head and
 * shoulders drop together and neither forward creep nor head drop moves. Session 8 (2026-10-05):
 * sinks +0.086 to +0.103, uprights +0.005 to +0.020, swivels and head turns +0.018 or below. Sent
 * by app builds from 2026-10-05 on; absent from older ones.
 */
export const SLOUCH_MIN_SHOULDER_SINK = 0.05;

/** The swivel rule above, in code: what the wording tells Jev, made testable. */
export function isSwivelByRule(forwardCreep: number, headYawDegrees: number): boolean {
  return Math.abs(headYawDegrees) >= SWIVEL_MIN_HEAD_YAW && forwardCreep <= SWIVEL_MAX_FORWARD_CREEP;
}

/**
 * Looking away: the head turned past the swivel yaw with the shoulders still square, so the neck
 * is turned and the chair isn't. The app times this on its own (HeadTurnTracker, the same 45° and
 * -0.03), and nudges for it with different advice from a slouch.
 */
export function isLookingAwayByRule(forwardCreep: number, headYawDegrees: number): boolean {
  return Math.abs(headYawDegrees) >= SWIVEL_MIN_HEAD_YAW && forwardCreep > SWIVEL_MAX_FORWARD_CREEP;
}

/**
 * The slouch rule, in code: shoulders clearly forward, or the head clearly higher with little
 * sideways shift. Not forward creep alone while looking away: turning the head reads the
 * shoulders wider (6 of 8 head turns +0.06 to +0.16), and every head turn read head_drop -0.003 or
 * above while every slouch read -0.013 or below.
 */
export function isSlouchByRule(
  forwardCreep: number,
  headDrop: number,
  lateralShift: number,
  headYawDegrees: number,
  shoulderSink?: number,
): boolean {
  const byCreep =
    forwardCreep >= SLOUCH_MIN_FORWARD_CREEP && !isLookingAwayByRule(forwardCreep, headYawDegrees);
  const byHeadHeight =
    headDrop <= SLOUCH_MAX_HEAD_DROP && Math.abs(lateralShift) < HEAD_DROP_SLOUCH_MAX_SHIFT;
  const bySink = shoulderSink !== undefined && shoulderSink >= SLOUCH_MIN_SHOULDER_SINK;
  return byCreep || byHeadHeight || bySink;
}

/** The clear-lean rule, in code: a clear sideways shift that isn't a swivel, whatever the yaw. */
export function isClearLeanByRule(
  lateralShift: number,
  forwardCreep: number,
  headYawDegrees: number,
): boolean {
  return Math.abs(lateralShift) >= LEAN_CLEAR_SHIFT && !isSwivelByRule(forwardCreep, headYawDegrees);
}

export const POSTURE_CRITERIA: Record<string, string> = {
  good_posture:
    `Sitting upright, close to the calibration baseline. forward_creep stays under ${SLOUCH_MIN_FORWARD_CREEP} (sitting still, it wanders a few hundredths either side of zero), head_drop stays above ${SLOUCH_MAX_HEAD_DROP}, shoulder_sink_in_shoulder_widths (when present) stays under ${SLOUCH_MIN_SHOULDER_SINK}, and lateral lean is small. The head may be turned: head angles alone do not make a posture bad. Someone looking away (head_yaw_degrees at least ${SWIVEL_MIN_HEAD_YAW} either way with forward_creep above ${SWIVEL_MAX_FORWARD_CREEP}) is good posture even with forward_creep well above ${SLOUCH_MIN_FORWARD_CREEP}, unless head_drop is ${SLOUCH_MAX_HEAD_DROP} or lower.`,
  // Kept free of the lean rule: v3 first added it here and four clear slouches dropped to
  // good_posture in replay. The lean rule lives only in the lean description.
  slouch:
    `Collapsed toward the screen or downward. forward_creep is clearly POSITIVE, ${SLOUCH_MIN_FORWARD_CREEP} or more (the shoulders appear wider because the torso moved closer to the camera; slouches so far measured +0.08 to +0.18), and/or head_drop is NEGATIVE, ${SLOUCH_MAX_HEAD_DROP} or lower, while lateral_lean_in_shoulder_widths stays under ${HEAD_DROP_SLOUCH_MAX_SHIFT} either way (it goes negative as the head drops towards the shoulders; slouches so far measured -0.02 to -0.11, uprights -0.004 or above). Either signal alone is enough, with one exception: while looking away (head_yaw_degrees at least ${SWIVEL_MIN_HEAD_YAW} either way with forward_creep above ${SWIVEL_MAX_FORWARD_CREEP}), forward_creep alone is not a slouch, because turning the head makes the shoulders look wider (head turns so far +0.01 to +0.16 with head_drop -0.003 or above). Then it is a slouch only if head_drop is ${SLOUCH_MAX_HEAD_DROP} or lower. A third way, when shoulder_sink_in_shoulder_widths is present: ${SLOUCH_MIN_SHOULDER_SINK} or more is a slouch on its own, sinking down in the chair, where the head and shoulders drop together so forward_creep and head_drop barely move (sinks so far +0.086 to +0.103, uprights +0.020 or below). Lateral lean is not the story.`,
  lean:
    `The torso has shifted sideways. lateral_lean_in_shoulder_widths is clearly non-zero and holds its sign. A clear shift, ${LEAN_CLEAR_SHIFT} or more either way, is a lean whatever head_yaw_degrees says (the head often turns while leaning, sometimes past ${SWIVEL_MIN_HEAD_YAW} degrees), and even if forward_creep is mildly positive or head_drop is negative: leaning sideways often brings the shoulders a little toward the camera and tilts the head up in the image. The one exception is a swivel, which needs head_yaw_degrees at least ${SWIVEL_MIN_HEAD_YAW} AND forward_creep at or below ${SWIVEL_MAX_FORWARD_CREEP}. A smaller shift with the head turned past ${SWIVEL_MIN_HEAD_YAW} degrees is someone looking away, not a lean. Shoulders slightly narrower than baseline are fine for a lean when the head is not turned past ${SWIVEL_MIN_HEAD_YAW} degrees.`,
  chair_swivel:
    `The whole body has ROTATED in the chair rather than the posture degrading. It needs BOTH of these: head_yaw_degrees at least ${SWIVEL_MIN_HEAD_YAW} either way, because the head turns with the body, AND forward_creep at or below ${SWIVEL_MAX_FORWARD_CREEP}, because rotating about the vertical axis makes the shoulders look narrower (by 5% to 40% so far). A head turned that far with the shoulders at or wider than baseline (forward_creep above ${SWIVEL_MAX_FORWARD_CREEP}) is someone looking away, not a swivel: that is good posture unless head_drop says slouch. Narrower shoulders with head_yaw_degrees under ${SWIVEL_MIN_HEAD_YAW} is not a swivel either. The shoulder midpoint usually shifts sideways in a swivel too, so a sideways shift does not make it a lean. head_drop stays near zero. A swivel is a comfortable neutral posture seen off-axis, not bad posture.`,
  ambiguous:
    "The signals disagree with each other, or tracking_quality is 'degraded' or 'lost' so the values cannot be trusted. Prefer this over guessing; the caller gates on confidence and falls back to its own thresholds.",
};

/**
 * Every delta the app sends is relative to a calibration snapshot, in units that mean nothing
 * on their own. Stating that in the payload is not decoration: without a frame of reference a
 * prose rubric has nothing to bind the numbers to.
 */
export const BASELINE_NOTE = [
  "All values except the head angles are deltas from a calibration snapshot taken while the user sat upright; 0 means exactly at baseline.",
  "forward_creep is the fractional change in APPARENT shoulder width: positive means the shoulders look wider (torso closer to the camera), negative means narrower (torso rotated away from square).",
  "head_drop is in shoulder-widths and NEGATIVE when the head has dropped towards the shoulders since baseline, as in a slouch; positive means it sits higher above them.",
  "shoulder_sink_in_shoulder_widths, when present, is how far the shoulders sit lower in the frame than at baseline; positive is lower. Older app builds don't send it.",
  "lateral_lean_in_shoulder_widths is the sideways shift of the shoulder midpoint, divided by baseline shoulder width so it is dimensionless in both camera modes.",
  "shoulder_tilt_signed_degrees is one shoulder higher than the other, not axial rotation.",
  "Head angles are camera-absolute degrees and read 0 both when centred and when unavailable.",
].join(" ");

/**
 * What Jev is sent. Not torso_angle_degrees, torso_lean_delta_degrees or depth_mode: across all
 * 70 captures from five sessions they never varied (45, 0 and "twoDOnly"; the hips are never in
 * frame, so the torso values are a clamped proxy). The app still sends them, and they're dropped
 * here with any other unknown key.
 */
const NUMERIC_FIELDS = [
  "head_yaw_degrees",
  "head_pitch_degrees",
  "head_roll_degrees",
  "forward_creep_fraction_of_baseline_shoulder_width",
  "head_drop_in_shoulder_widths",
  "lateral_lean_in_shoulder_widths",
  "shoulder_tilt_signed_degrees",
] as const;

export type Features = { [K in (typeof NUMERIC_FIELDS)[number]]: number } & {
  tracking_quality: TrackingQuality;
  shoulder_sink_in_shoulder_widths?: number;
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

  // Optional: app builds from 2026-10-05 send it, older ones don't.
  if ("shoulder_sink_in_shoulder_widths" in src) {
    const sink = src.shoulder_sink_in_shoulder_widths;
    if (typeof sink !== "number" || !Number.isFinite(sink)) {
      return { ok: false, error: "shoulder_sink_in_shoulder_widths must be a finite number" };
    }
    out.shoulder_sink_in_shoulder_widths = sink;
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
