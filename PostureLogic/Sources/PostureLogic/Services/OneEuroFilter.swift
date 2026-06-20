/// One Euro filter (Géry Casiez, Nicolas Roussel & Daniel Vogel, *CHI 2012*) — an
/// adaptive low-pass for noisy interactive signals. Unlike a fixed-weight EMA, it
/// raises its cutoff frequency with the signal's *speed*: it smooths hard when the
/// value is stationary (killing hold-still jitter) yet barely lags a fast move (no
/// rubber-banding on a deliberate gesture). It is the single tunable that trades
/// jitter against lag without forcing one fixed compromise.
///
/// In this app it is the **source-side denoiser** for the head angles, sitting
/// *before* the display gain (which amplifies pitch ~5×) and *before* the render
/// follower. The two filters do genuinely different jobs:
/// - This (One Euro): removes high-frequency *noise* from the measurement. Adaptive,
///   so it adds lag only while the head is still — where lag is imperceptible.
/// - The render follower (``CriticallyDampedScalar``): bridges the ~10 Hz → 60–120 Hz
///   *staircase* into a fluid arc. It is a tracker, not a denoiser, so on its own it
///   faithfully reproduces whatever jitter reaches it.
///
/// Pure value type, no Foundation: the One Euro smoothing factor
/// `alpha = 1 / (1 + tau/dt)` with `tau = 1 / (2π·fc)` needs no transcendentals, so
/// this is headlessly unit-tested exactly like ``CriticallyDampedScalar``.
///
/// **Identity when it cannot measure a rate.** The filter is timestamp-driven. The
/// first sample *seeds* (returns the raw value); any later sample whose timestamp
/// does **not advance** (`dt <= 0` — a duplicate or non-monotone clock) passes the
/// raw value straight through. This is not a special case but the only honest
/// behaviour — a derivative-driven filter has no velocity to adapt to and no rate to
/// low-pass when no time has elapsed. Two consequences fall out for free: a caller
/// feeding a constant timestamp (the app's camera-free unit-test seam does exactly
/// this) sees perfect pass-through, and a stray duplicate ARKit frame timestamp in
/// production costs at most one unfiltered frame instead of a divide-by-zero.
public struct OneEuroFilter: Equatable, Sendable {

    /// Minimum cutoff frequency (Hz): the smoothing floor when the signal is
    /// stationary. **Lower = steadier** (more lag while held, but more jitter
    /// removed). This is the dominant knob for the "it won't sit still" complaint.
    public var minCutoff: Float

    /// Speed coefficient. The effective cutoff rises by `beta · |filtered speed|`, so
    /// **higher = snappier catch-up** on a fast move (less lag) at the cost of letting
    /// more jitter through *while* moving. `0` makes the filter a plain fixed low-pass
    /// at `minCutoff`.
    public var beta: Float

    /// Cutoff (Hz) of the derivative's own low-pass. The paper's stable default of
    /// `1.0` is almost always right; exposed only for completeness.
    public var dCutoff: Float

    private var xHat: Float = 0       // last filtered value (the output state)
    private var xPrevRaw: Float = 0   // last raw input (for the speed estimate)
    private var dxHat: Float = 0      // last filtered derivative
    private var lastTime: Double?     // nil ⇒ unseeded

    public init(minCutoff: Float = 1.0, beta: Float = 0.0, dCutoff: Float = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    /// The current filtered value without advancing time.
    public var value: Float { xHat }

    /// Whether the filter has seen its first (seeding) sample.
    public var isSeeded: Bool { lastTime != nil }

    /// First-order low-pass smoothing factor for a cutoff/`dt` pair:
    /// `1 / (1 + tau/dt)`, `tau = 1 / (2π·fc)`. Larger `fc` (or `dt`) ⇒ alpha → 1
    /// (trust the new sample); smaller ⇒ alpha → 0 (hold the old value).
    private static func alpha(cutoff: Float, dt: Float) -> Float {
        let tau = 1 / (2 * Float.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    /// Ingest a new sample stamped at `timestamp` (seconds). Returns the filtered
    /// value. See the type doc for the seed / non-advancing-timestamp contract.
    @discardableResult
    public mutating func update(_ x: Float, timestamp: Double) -> Float {
        guard let prev = lastTime else {            // first sample: seed, no filtering
            xHat = x
            xPrevRaw = x
            dxHat = 0
            lastTime = timestamp
            return x
        }

        let dt = Float(timestamp - prev)
        guard dt > 0 else {                          // no time elapsed ⇒ cannot filter
            xHat = x
            xPrevRaw = x
            lastTime = timestamp
            return x
        }
        lastTime = timestamp

        // Estimate speed from the raw signal, low-pass it, and let its magnitude
        // raise the cutoff so fast motion is tracked while slow drift is smoothed.
        let dx = (x - xPrevRaw) / dt
        dxHat += Self.alpha(cutoff: dCutoff, dt: dt) * (dx - dxHat)
        let cutoff = max(minCutoff + beta * abs(dxHat), 1e-4)   // never freeze fully
        xHat += Self.alpha(cutoff: cutoff, dt: dt) * (x - xHat)
        xPrevRaw = x
        return xHat
    }

    /// Return to the unseeded state so the next `update` seeds afresh (e.g. on a
    /// recalibration or a long tracking gap).
    public mutating func reset() {
        xHat = 0
        xPrevRaw = 0
        dxHat = 0
        lastTime = nil
    }
}

/// Runtime-tunable parameters for the head-angle ``OneEuroFilter`` denoiser, exposed
/// `public` so a **DEBUG** on-device panel can dial them without a rebuild (mirrors
/// ``HeadYawTuning``). In Release nothing mutates them, so they behave as the baked
/// default constants.
///
/// Concurrency: plain `static var`s read on the (main-actor) view-model ingest path
/// and written from the main-thread tuning HUD — same thread in practice. As with
/// ``HeadYawTuning`` a torn read would merely yield a slightly-off frame the next one
/// corrects; do not promote this pattern to anything that gates real behaviour.
public enum HeadAngleFilterTuning {

    /// `OneEuroFilter.minCutoff` for the head angles (Hz). **1.0** is a deliberately
    /// gentle start for the ~10 Hz pose cadence: noticeable jitter removal without an
    /// obvious hold lag. Lower it on device until the held head stops shimmering.
    public static var minCutoff: Float = minCutoffDefault
    public static let minCutoffDefault: Float = 1.0

    /// `OneEuroFilter.beta` for the head angles. **0.05** lets a deliberate nod
    /// (tens of degrees per second) lift the cutoff several Hz so it is tracked with
    /// little lag, while a still head stays at `minCutoff`. Raise if real moves feel
    /// draggy, lower if motion looks jittery.
    public static var beta: Float = betaDefault
    public static let betaDefault: Float = 0.05
}
