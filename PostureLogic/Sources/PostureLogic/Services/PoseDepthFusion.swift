import CoreGraphics
import Foundation
import simd

/// True head orientation in degrees, derived from facial keypoints
/// (`nose`/`eye`/`ear`) independently of the shoulder skeleton.
///
/// Sign conventions (locked against `PoseDepthFusion`'s y-up frame, where larger
/// `y` = physically higher — the same convention `computeShoulderTwist` uses):
/// - `roll`:  tilt of the ear line from horizontal; right ear lower → negative.
/// - `pitch`: chin-down nod angle (computed in a later sub-stage).
/// - `yaw`:   left/right head turn (computed in a later sub-stage).
/// Public so it can type `InputFrame.externalHeadAngles` — the channel an app-side
/// ARKit provider uses to inject a fully-decoupled `ARFaceAnchor` head pose (Layer
/// 1) ahead of both the Vision monocular fit and the legacy 2D formulas.
public struct HeadAngles {
    public var pitch: Float
    public var yaw: Float
    public var roll: Float

    public init(pitch: Float, yaw: Float, roll: Float) {
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
    }

    public static let neutral = HeadAngles(pitch: 0, yaw: 0, roll: 0)
}

/// Runtime-tunable head-orientation calibration, exposed `public` so a **DEBUG**
/// build can dial it in on device without a rebuild (see the calibration slider in
/// `PostureVisualizationView`). In Release nothing mutates it, so it behaves as the
/// baked default constant.
///
/// Concurrency: a plain `static var` read on the pose-processing path and written
/// from the main-thread tuning HUD. The unsynchronized cross-thread access is a
/// benign race for a scalar debug knob — it is not a correctness-critical value and
/// a torn `Float` read merely yields a slightly-off frame that the next one
/// corrects. Do **not** promote this pattern to anything that gates real behavior.
public enum HeadYawTuning {
    /// Calibration factor for the one-ear proportional yaw: the ratio of frontal
    /// eye separation to nose-tip protrusion in the image plane (`E₀ / d`).
    ///
    /// Derivation — under perspective projection a head yawed by `θ` foreshortens
    /// its eye separation to `E₀·cos θ` while the nose tip swings sideways by
    /// `d·sin θ`, so the eye-normalized nose offset is
    /// `(nose.x − eyeMidX) / eyeSeparation = (d / E₀)·tan θ`. Inverting gives
    /// `θ = atan(k · offset)` with `k = E₀ / d`. Anatomically (IPD ≈ 63 mm, nose
    /// protrusion ≈ 23 mm) `k ≈ 2.7`, but the device value runs higher — Vision's
    /// `nose` keypoint is not the nose *tip* and the eye keypoints sit at eye
    /// *centers*, so the measured `offset/separation` is smaller than the ideal
    /// geometry, inflating the `k` needed to recover the true angle. Larger `k` ⇒
    /// a given offset reads as a bigger turn. TUNE ON DEVICE against known angles.
    public static var oneEarCalibration: Float = oneEarCalibrationDefault

    /// Device-tuned starting value for `oneEarCalibration` (the slider's reset
    /// target and the Release-shipped constant). Single source of truth so the UI
    /// never re-states the magic number. Dialled in on device 2026-06-14 to **8.0**
    /// (mid-slider, not railed — a genuine optimum; the anatomical ideal is ≈2.7,
    /// see `oneEarCalibration` for why the real value is higher).
    public static let oneEarCalibrationDefault: Float = 8.0
}

/// Converts a 2D `PoseObservation` into a shoulder-width-normalized `PoseSample`.
///
/// All positions are expressed relative to the shoulder midpoint and divided by
/// shoulder width, making them scale-invariant regardless of camera distance.
/// In `twoDOnly` mode all z-values are 0. When depth is available with sufficient
/// confidence, uses `unproject()` to produce 3D positions in `depthFusion` mode.
struct PoseDepthFusion: PoseDepthFusionProtocol {

    // MARK: - Constants

    private static let minKeypointConfidence: Float = 0.3
    private static let minShoulderWidth: CGFloat = 0.01
    private static let edgeMargin: CGFloat = 0.05  // Ignore depth within 5% of frame edges
    private static let minDepthSampleConfidence: Float = 0.5

    // MARK: - Debug State

    private(set) var lastShoulderWidth: CGFloat = 0
    private(set) var lastHeadPosition: CGPoint = .zero
    private(set) var fusionCount: Int = 0
    private(set) var missingKeypointCount: Int = 0

    var debugState: [String: Any] {
        [
            "lastShoulderWidth": lastShoulderWidth,
            "lastHeadPosition": [lastHeadPosition.x, lastHeadPosition.y],
            "fusionCount": fusionCount,
            "missingKeypointCount": missingKeypointCount,
        ]
    }

    init() {}

    // MARK: - PoseDepthFusionProtocol

    mutating func fuse(
        pose: PoseObservation,
        depthSamples: [DepthAtPoint]?,
        confidence: DepthConfidence,
        intrinsics: simd_float3x3?,
        trackingQuality: TrackingQuality
    ) -> PoseSample? {
        // Extract required keypoints
        guard let leftShoulder = keypoint(.leftShoulder, from: pose),
              let rightShoulder = keypoint(.rightShoulder, from: pose)
        else {
            missingKeypointCount += 1
            return nil
        }

        guard let headPos = resolveHeadPosition(from: pose) else {
            missingKeypointCount += 1
            return nil
        }

        // Guard degenerate shoulder width
        let shoulderWidth = distance(leftShoulder.position, rightShoulder.position)
        guard shoulderWidth > Self.minShoulderWidth else {
            missingKeypointCount += 1
            return nil
        }

        // Update debug state
        lastShoulderWidth = shoulderWidth
        lastHeadPosition = headPos
        fusionCount += 1

        // Attempt 3D fusion when depth is available with sufficient confidence
        if confidence >= .medium,
           let samples = depthSamples,
           let intr = intrinsics {
            if let sample3D = fuse3D(
                pose: pose,
                leftShoulder: leftShoulder,
                rightShoulder: rightShoulder,
                headPos: headPos,
                shoulderWidth: shoulderWidth,
                depthSamples: samples,
                intrinsics: intr,
                trackingQuality: trackingQuality
            ) {
                return sample3D
            }
        }

        // Fallback: 2D-only path
        return fuse2D(
            pose: pose,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            headPos: headPos,
            shoulderWidth: shoulderWidth,
            trackingQuality: trackingQuality
        )
    }

    // MARK: - 2D Fusion (existing path)

    private func fuse2D(
        pose: PoseObservation,
        leftShoulder: Keypoint,
        rightShoulder: Keypoint,
        headPos: CGPoint,
        shoulderWidth: CGFloat,
        trackingQuality: TrackingQuality
    ) -> PoseSample {
        let midX = (leftShoulder.position.x + rightShoulder.position.x) / 2
        let midY = (leftShoulder.position.y + rightShoulder.position.y) / 2

        let normLeftShoulder = SIMD3<Float>(
            Float((leftShoulder.position.x - midX) / shoulderWidth),
            Float((leftShoulder.position.y - midY) / shoulderWidth),
            0
        )
        let normRightShoulder = SIMD3<Float>(
            Float((rightShoulder.position.x - midX) / shoulderWidth),
            Float((rightShoulder.position.y - midY) / shoulderWidth),
            0
        )
        let normHead = SIMD3<Float>(
            Float((headPos.x - midX) / shoulderWidth),
            Float((headPos.y - midY) / shoulderWidth),
            0
        )

        let torsoAngle = computeTorsoAngle(
            pose: pose,
            shoulderMidX: midX,
            shoulderMidY: midY,
            shoulderWidth: shoulderWidth,
            headPos: headPos
        )
        let shoulderTwist = computeShoulderTwist(
            leftShoulder: leftShoulder.position,
            rightShoulder: rightShoulder.position,
            shoulderWidth: shoulderWidth
        )
        let headAngles = computeHeadAngles(from: pose)
        // Ear-based head-carriage height (image space) — sources the refined
        // `headDrop`. `midY`/`shoulderWidth` are already image-space here.
        let neckHeight = computeNeckHeight(
            pose: pose,
            fallbackHeadY: headPos.y,
            shoulderMidY: midY,
            shoulderWidth: shoulderWidth
        )

        return PoseSample(
            timestamp: pose.timestamp,
            depthMode: .twoDOnly,
            headPosition: normHead,
            shoulderMidpoint: SIMD3<Float>(Float(midX), Float(midY), 0),
            leftShoulder: normLeftShoulder,
            rightShoulder: normRightShoulder,
            torsoAngle: torsoAngle,
            headForwardOffset: 0,
            shoulderTwist: shoulderTwist,
            shoulderWidthRaw: Float(shoulderWidth),
            trackingQuality: trackingQuality,
            headPitch: headAngles.pitch,
            headYaw: headAngles.yaw,
            headRoll: headAngles.roll,
            // Viz-only quaternion: non-nil only on the ARFaceAnchor/Tier-1 path,
            // nil for 2D/dropout. Parallel to the Euler fields, never gates scoring.
            headOrientation: pose.externalHeadOrientation?.vector,
            neckHeight: neckHeight
        )
    }

    // MARK: - 3D Fusion (depth-enhanced path)

    private func fuse3D(
        pose: PoseObservation,
        leftShoulder: Keypoint,
        rightShoulder: Keypoint,
        headPos: CGPoint,
        shoulderWidth: CGFloat,
        depthSamples: [DepthAtPoint],
        intrinsics: simd_float3x3,
        trackingQuality: TrackingQuality
    ) -> PoseSample? {
        // Find depth for each critical keypoint
        guard let lsDepth = findDepth(for: leftShoulder.position, in: depthSamples),
              let rsDepth = findDepth(for: rightShoulder.position, in: depthSamples),
              let headDepth = findDepth(for: headPos, in: depthSamples)
        else {
            return nil  // Fall back to 2D if any critical depth is missing
        }

        // Unproject to 3D camera space
        let ls3D = unproject(
            point: SIMD2<Float>(Float(leftShoulder.position.x), Float(leftShoulder.position.y)),
            depth: lsDepth,
            intrinsics: intrinsics
        )
        let rs3D = unproject(
            point: SIMD2<Float>(Float(rightShoulder.position.x), Float(rightShoulder.position.y)),
            depth: rsDepth,
            intrinsics: intrinsics
        )
        let head3D = unproject(
            point: SIMD2<Float>(Float(headPos.x), Float(headPos.y)),
            depth: headDepth,
            intrinsics: intrinsics
        )

        // 3D shoulder midpoint
        let mid3D = (ls3D + rs3D) / 2

        // 3D shoulder width for normalization
        let shoulderWidth3D = simd_length(ls3D - rs3D)
        guard shoulderWidth3D > 0.01 else {
            return nil  // Degenerate 3D shoulder width
        }

        // Normalize positions relative to 3D midpoint, divided by 3D shoulder width
        let normLeftShoulder = (ls3D - mid3D) / shoulderWidth3D
        let normRightShoulder = (rs3D - mid3D) / shoulderWidth3D
        let normHead = (head3D - mid3D) / shoulderWidth3D

        // Head forward offset: z-difference between head and shoulder midpoint
        // Positive = head is further from camera than shoulders (leaning back)
        // Negative = head is closer to camera than shoulders (leaning forward)
        let headForwardOffset = head3D.z - mid3D.z

        // Shoulder twist using 3D: angle from y-difference in 3D space
        let yDiff3D = ls3D.y - rs3D.y
        let twistRatio = yDiff3D / shoulderWidth3D
        let clampedTwist = max(-1, min(twistRatio, 1))
        let shoulderTwist = asin(clampedTwist) * (180.0 / .pi)

        // Torso angle using 3D: use z-offset as proxy for forward lean
        // atan2(|z-offset|, y-extent) gives forward lean in 3D
        let torsoAngle = computeTorsoAngle(
            pose: pose,
            shoulderMidX: CGFloat(mid3D.x),
            shoulderMidY: CGFloat(mid3D.y),
            shoulderWidth: CGFloat(shoulderWidth3D),
            headPos: headPos
        )
        // Facial-keypoint angles. Yaw + roll stay 2D (image-plane geometry); pitch
        // is upgraded to a true depth-based elevation angle when LiDAR depth exists
        // at the nose + ear plane, falling back to the 2D pitch otherwise.
        var headAngles = computeHeadAngles(from: pose)
        // The LiDAR elevation pitch refines the *2D* estimate; it must not override
        // an authoritative ARKit (`externalHeadAngles`) pitch, which is already a
        // true metric angle.
        if pose.externalHeadAngles == nil,
           let pitch3D = computeHeadPitch3D(
            from: pose,
            depthSamples: depthSamples,
            intrinsics: intrinsics
        ) {
            headAngles.pitch = pitch3D
        }

        // Ear-based head-carriage height, computed in **image space** exactly as
        // the 2D path does (NOT from the unprojected 3D coordinates) so `headDrop`
        // stays comparable across camera modes. `shoulderWidth` here is already the
        // 2D image-space width; derive the matching 2D shoulder-mid Y from the same
        // shoulder keypoints, and use the image-space `headPos.y` as fallback.
        let shoulderMidY2D = (leftShoulder.position.y + rightShoulder.position.y) / 2
        let neckHeight = computeNeckHeight(
            pose: pose,
            fallbackHeadY: headPos.y,
            shoulderMidY: shoulderMidY2D,
            shoulderWidth: shoulderWidth
        )

        return PoseSample(
            timestamp: pose.timestamp,
            depthMode: .depthFusion,
            headPosition: normHead,
            shoulderMidpoint: mid3D,
            leftShoulder: normLeftShoulder,
            rightShoulder: normRightShoulder,
            torsoAngle: torsoAngle,
            headForwardOffset: headForwardOffset,
            shoulderTwist: shoulderTwist,
            shoulderWidthRaw: Float(shoulderWidth),
            trackingQuality: trackingQuality,
            headPitch: headAngles.pitch,
            headYaw: headAngles.yaw,
            headRoll: headAngles.roll,
            // Viz-only quaternion: non-nil only on the ARFaceAnchor/Tier-1 path,
            // nil for 2D/dropout. Parallel to the Euler fields, never gates scoring.
            headOrientation: pose.externalHeadOrientation?.vector,
            neckHeight: neckHeight
        )
    }

    // MARK: - Depth Lookup

    /// Finds the depth value for a given 2D point from the depth samples.
    /// Returns nil if the point is near a frame edge or has low confidence.
    private func findDepth(for point: CGPoint, in samples: [DepthAtPoint]) -> Float? {
        // Ignore points near edges (within 5% of frame boundaries)
        if isNearEdge(point) {
            return nil
        }

        // Find the sample closest to this point
        let threshold: CGFloat = 0.01  // Match within 1% of frame
        guard let match = samples.min(by: {
            hypot($0.point.x - point.x, $0.point.y - point.y) <
            hypot($1.point.x - point.x, $1.point.y - point.y)
        }) else {
            return nil
        }

        let dist = hypot(match.point.x - point.x, match.point.y - point.y)
        guard dist < threshold else {
            return nil
        }

        // Check confidence and validity
        guard match.confidence >= Self.minDepthSampleConfidence,
              match.depth > 0,
              match.depth.isFinite
        else {
            return nil
        }

        return match.depth
    }

    /// Returns true if the point is within the edge margin (5% of frame boundaries).
    private func isNearEdge(_ point: CGPoint) -> Bool {
        point.x < Self.edgeMargin || point.x > (1.0 - Self.edgeMargin) ||
        point.y < Self.edgeMargin || point.y > (1.0 - Self.edgeMargin)
    }

    // MARK: - Head Fallback Chain

    /// Resolves head position using fallback chain: nose → eye midpoint → single eye → ear midpoint → nil
    private func resolveHeadPosition(from pose: PoseObservation) -> CGPoint? {
        // 1. Nose
        if let nose = keypoint(.nose, from: pose) {
            return nose.position
        }

        // 2. Eye midpoint
        let leftEye = keypoint(.leftEye, from: pose)
        let rightEye = keypoint(.rightEye, from: pose)
        if let le = leftEye, let re = rightEye {
            return CGPoint(
                x: (le.position.x + re.position.x) / 2,
                y: (le.position.y + re.position.y) / 2
            )
        }

        // 3. Single eye
        if let eye = leftEye ?? rightEye {
            return eye.position
        }

        // 4. Ear midpoint
        let leftEar = keypoint(.leftEar, from: pose)
        let rightEar = keypoint(.rightEar, from: pose)
        if let le = leftEar, let re = rightEar {
            return CGPoint(
                x: (le.position.x + re.position.x) / 2,
                y: (le.position.y + re.position.y) / 2
            )
        }

        return nil
    }

    // MARK: - Neck Height (ear-based head carriage)

    /// Ear-based head-carriage height in **image space** (Vision y-up),
    /// shoulder-normalized: `(earMidY − shoulderMidY) / shoulderWidth`. This is the
    /// source for the refined `RawMetrics.headDrop` — it tracks where the head is
    /// *carried* relative to the shoulders, so a stable head reading down at the
    /// nose (a transient look-down / chin-drop) does not register as a drop the way
    /// nose-relative `headPosition.y` does. It is deliberately a **2D body-pose**
    /// quantity (ear + shoulder image keypoints, same domain as `torsoAngle`); it
    /// must NOT be derived from head-orientation angles.
    ///
    /// Both the 2D and 3D fusion paths call this with the **same image-space**
    /// keypoints (never 3D/unprojected coordinates), so `headDrop` stays directly
    /// comparable across camera modes.
    ///
    /// Ear source: both `.leftEar` and `.rightEar` must pass the shared
    /// `keypoint(_:from:)` confidence gate; then `earY = (le.y + re.y) / 2`.
    /// Otherwise falls back to `fallbackHeadY` — the already-resolved nose-first
    /// head Y — so a turned/occluded-ear frame still yields a sane carriage value
    /// instead of collapsing. Guards a degenerate `shoulderWidth` (returns 0),
    /// mirroring the caller's existing width guards.
    private func computeNeckHeight(
        pose: PoseObservation,
        fallbackHeadY: CGFloat,
        shoulderMidY: CGFloat,
        shoulderWidth: CGFloat
    ) -> Float {
        guard shoulderWidth > Self.minShoulderWidth else { return 0 }

        let earY: CGFloat
        if let le = keypoint(.leftEar, from: pose),
           let re = keypoint(.rightEar, from: pose) {
            earY = (le.position.y + re.position.y) / 2
        } else {
            earY = fallbackHeadY
        }

        // Vision y-up: ears above shoulders ⇒ positive.
        return Float((earY - shoulderMidY) / shoulderWidth)
    }

    // MARK: - Angle Computation

    /// Computes torso forward lean angle in degrees.
    /// If hips visible: `atan2(|dx|, dy)` of hip→shoulder vector.
    /// Fallback: head-shoulder vertical ratio mapped to pseudo-angle.
    ///
    /// Note: Vision framework uses y-up coordinates (0 at bottom, 1 at top).
    private func computeTorsoAngle(
        pose: PoseObservation,
        shoulderMidX: CGFloat,
        shoulderMidY: CGFloat,
        shoulderWidth: CGFloat,
        headPos: CGPoint
    ) -> Float {
        // Try hip-based calculation first
        let leftHip = keypoint(.leftHip, from: pose)
        let rightHip = keypoint(.rightHip, from: pose)

        if let lh = leftHip, let rh = rightHip {
            let hipMidX = (lh.position.x + rh.position.x) / 2
            let hipMidY = (lh.position.y + rh.position.y) / 2
            let dx = abs(shoulderMidX - hipMidX)
            // Vision y-up: shoulders above hips → shoulderMidY > hipMidY when upright
            let dy = shoulderMidY - hipMidY
            // atan2(|dx|, dy) gives 0 when upright, increases with lean
            return Float(atan2(dx, dy)) * (180.0 / .pi)
        }

        // Fallback: map head-shoulder vertical distance ratio to pseudo-angle
        // Vision y-up: head.y > shoulderMid.y when upright
        let headVerticalOffset = headPos.y - shoulderMidY
        let ratio = headVerticalOffset / shoulderWidth
        // Map ratio: 1.2 → 0°, 0.0 → 45° (linear interpolation, clamped)
        let normalizedRatio = max(0, min(Float(ratio) / 1.2, 1.0))
        return (1.0 - normalizedRatio) * 45.0
    }

    /// `asin(yDiff / shoulderWidth)` in degrees. Positive = left shoulder higher.
    private func computeShoulderTwist(
        leftShoulder: CGPoint,
        rightShoulder: CGPoint,
        shoulderWidth: CGFloat
    ) -> Float {
        let yDiff = leftShoulder.y - rightShoulder.y
        let ratio = Float(yDiff / shoulderWidth)
        // Clamp to valid asin range
        let clamped = max(-1, min(ratio, 1))
        return asin(clamped) * (180.0 / .pi)
    }

    // MARK: - Head Angles (true head geometry from facial keypoints)

    /// Computes true head pitch/yaw/roll from the facial keypoints
    /// (`nose`/`eye`/`ear`) Vision already detects, independently of the shoulder
    /// skeleton. Reuses `keypoint(_:from:)` for confidence-filtered lookup and
    /// degrades gracefully (neutral 0) when the required keypoints are absent —
    /// mirroring `resolveHeadPosition`'s tolerance.
    ///
    /// Head orientation in the `PoseSample` degree convention.
    ///
    /// Two tiers. **Tier 1** — an ARKit `ARFaceAnchor` head pose threaded through as
    /// `pose.externalHeadAngles`: a true metric 6-DOF rotation, decoupled by
    /// construction and authoritative whenever present (TrueDepth `.frontFace`),
    /// all-or-nothing (the anchor yields a whole rotation, not per-axis optionals).
    /// **Tier 2** — the legacy 2D estimate: pitch/yaw/roll as three INDEPENDENT
    /// formulas off the same nose/eye/ear keypoints, each assuming the other two axes
    /// are zero, so a turn foreshortens the ear line and tips the projected nose into
    /// a phantom nod/tilt (the "W"). It is the fallback floor for non-TrueDepth
    /// devices and for ARFace dropouts.
    func computeHeadAngles(from pose: PoseObservation) -> HeadAngles {
        // Tier 1 — ARKit ARFaceAnchor (Layer 1): authoritative when present.
        if let external = pose.externalHeadAngles {
            return external
        }
        // Tier 2 — legacy 2D formulas (fallback floor).
        return HeadAngles(
            pitch: computeHeadPitch(from: pose),
            yaw: computeHeadYaw(from: pose),
            roll: computeHeadRoll(from: pose)
        )
    }

    /// Roll = tilt of the ear line from horizontal, in degrees. Falls back to the
    /// eye line when an ear is missing, then to neutral (0).
    ///
    /// Uses `atan2(Δy, |Δx|)` of the `leftEar → rightEar` vector: horizontalizing
    /// the run (|Δx|) makes a level head read ~0° regardless of which ear lands at
    /// larger image-x (a front-facing subject has anatomical left/right mirrored),
    /// while the signed Δy carries the tilt. y-up convention (larger y = higher,
    /// per `computeShoulderTwist`) ⇒ right ear physically lower → negative roll.
    private func computeHeadRoll(from pose: PoseObservation) -> Float {
        let left: CGPoint
        let right: CGPoint
        if let le = keypoint(.leftEar, from: pose), let re = keypoint(.rightEar, from: pose) {
            left = le.position
            right = re.position
        } else if let le = keypoint(.leftEye, from: pose), let re = keypoint(.rightEye, from: pose) {
            left = le.position
            right = re.position
        } else {
            return 0
        }

        let run = abs(right.x - left.x)
        guard run > 1e-6 else { return 0 }  // degenerate vertical line → no defined tilt
        let rise = right.y - left.y
        return Float(atan2(rise, run)) * (180.0 / .pi)
    }

    /// Fallback yaw when one ear is occluded *and* the eyes are also unavailable
    /// to scale the turn — a strong-but-flat estimate (a turn large enough to hide
    /// an ear is roughly 50–70°). When the eyes are present, `oneEarYaw(...)`
    /// supersedes this with a proportional estimate.
    private static let oneEarMissingYawDegrees: Float = 60

    /// Ceiling for the proportional one-ear estimate, in degrees. `atan` already
    /// saturates at 90°; this only bounds noise at extreme foreshortening.
    private static let oneEarMaxYawDegrees: Float = 90

    /// Yaw = horizontal offset of the nose from the ear midpoint, normalized by
    /// ear separation, in degrees. Centred nose → ~0°. Sign: nose toward
    /// `.rightEar` (larger image-x in our layouts) → positive; toward `.leftEar`
    /// → negative.
    ///
    /// One-ear-missing rule: a strong turn occludes the far ear, so when exactly
    /// one ear is present we can't measure an ear-relative offset. Instead we hand
    /// off to `oneEarYaw(...)`, which scales the turn off the still-visible eyes —
    /// a *proportional* estimate that tracks the real angle and joins the two-ear
    /// curve continuously (rather than snapping to a constant). The sign is locked
    /// to the missing side (missing `.rightEar` → +, missing `.leftEar` → −).
    /// Falls back to neutral (0) when both ears or the nose are absent.
    private func computeHeadYaw(from pose: PoseObservation) -> Float {
        let leftEar = keypoint(.leftEar, from: pose)
        let rightEar = keypoint(.rightEar, from: pose)

        switch (leftEar, rightEar) {
        case let (le?, re?):
            // Both ears visible — measure the nose's normalized horizontal offset.
            guard let nose = keypoint(.nose, from: pose) else { return 0 }
            let separation = abs(re.position.x - le.position.x)
            guard separation > 1e-6 else { return 0 }
            let midX = (le.position.x + re.position.x) / 2
            let ratio = (nose.position.x - midX) / separation
            let clamped = max(-1, min(1, ratio))
            return Float(asin(clamped)) * (180.0 / .pi)
        case (.some, .none):
            // Right ear occluded → strong turn toward the right.
            return oneEarYaw(toward: 1, from: pose)
        case (.none, .some):
            // Left ear occluded → strong turn toward the left.
            return oneEarYaw(toward: -1, from: pose)
        case (.none, .none):
            return 0
        }
    }

    /// Proportional yaw for the one-ear-occluded regime, scaled off the eyes
    /// (which stay visible well past the angle that hides an ear — the same reason
    /// pitch/roll fall back to the eye line).
    ///
    /// Measures the nose's horizontal offset from the eye midpoint, normalized by
    /// the (foreshortening) eye separation, and maps it to an angle via
    /// `θ = atan(HeadYawTuning.oneEarCalibration · offset)` — see that knob for the
    /// projection derivation. The result is monotonic in the true turn angle and
    /// saturates smoothly toward 90°, so it continues the two-ear `asin` curve
    /// instead of snapping to a constant. `sign` (+1 missing-right, −1
    /// missing-left) carries the established one-ear direction; the eyes supply
    /// only magnitude, so the locked sign rule is preserved even at large yaw
    /// where the eye geometry is noisiest. Degrades to the flat
    /// `oneEarMissingYawDegrees` when the eyes or a usable separation are absent.
    private func oneEarYaw(toward sign: Float, from pose: PoseObservation) -> Float {
        guard let nose = keypoint(.nose, from: pose),
              let leftEye = keypoint(.leftEye, from: pose),
              let rightEye = keypoint(.rightEye, from: pose)
        else {
            return sign * Self.oneEarMissingYawDegrees
        }
        let separation = abs(rightEye.position.x - leftEye.position.x)
        guard separation > 1e-6 else { return sign * Self.oneEarMissingYawDegrees }
        let midX = (leftEye.position.x + rightEye.position.x) / 2
        let offset = abs(nose.position.x - midX) / separation
        let magnitude = atan(HeadYawTuning.oneEarCalibration * Float(offset)) * (180.0 / .pi)
        return sign * min(magnitude, Self.oneEarMaxYawDegrees)
    }

    /// Pitch (2D) = vertical offset of the nose relative to the eye/ear line,
    /// normalized by that line's horizontal separation, in degrees. A coarse
    /// proxy for chin-down/forward-head tilt — refined into a true elevation
    /// angle from LiDAR depth in a later sub-stage.
    ///
    /// Sign (y-up, larger y = higher): nose *below* the line (chin-down /
    /// forward-head) → positive; nose above (chin-up) → negative. The raw zero is
    /// the geometric on-the-line case, not a physiological neutral — the
    /// ViewModel's rest-relative calibration re-zeros it downstream. Ear line
    /// primary, eye line fallback (mirrors roll); neutral (0) when no reference
    /// line or no nose.
    private func computeHeadPitch(from pose: PoseObservation) -> Float {
        let left: CGPoint
        let right: CGPoint
        if let le = keypoint(.leftEar, from: pose), let re = keypoint(.rightEar, from: pose) {
            left = le.position
            right = re.position
        } else if let le = keypoint(.leftEye, from: pose), let re = keypoint(.rightEye, from: pose) {
            left = le.position
            right = re.position
        } else {
            return 0
        }

        guard let nose = keypoint(.nose, from: pose) else { return 0 }

        let scale = abs(right.x - left.x)
        guard scale > 1e-6 else { return 0 }  // degenerate line → no defined normalizer
        let lineY = (left.y + right.y) / 2
        let drop = lineY - nose.position.y  // y-up: nose below the line ⇒ positive drop
        return Float(atan2(drop, scale)) * (180.0 / .pi)
    }

    /// Pitch (3D) = the nose's elevation relative to the interaural (ear) plane,
    /// measured from LiDAR depth instead of the image-plane vertical the 2D path
    /// uses. Returns `nil` whenever the nose or an ear/eye reference pair lacks a
    /// valid depth sample, so the caller keeps the 2D pitch (graceful fallback —
    /// a depth frame never crashes or degrades a head that 2D could still read).
    ///
    /// Geometry: `unproject` the nose and the ear midpoint into camera space
    /// (z = metric depth, larger = farther), then take `atan2(noseZ − earMidZ,
    /// interaural)` — the angle by which the nose sits forward of / behind the ear
    /// plane, normalized by the interaural distance (a stable, ~fixed metric scale,
    /// mirroring how the rest of the fusion normalizes by shoulder width).
    ///
    /// Sign is locked to match the 2D pitch *direction* for the same motion so the
    /// ViewModel behaves identically in either mode: a relaxed head has the nose
    /// protruding *nearer* than the ears (noseZ < earMidZ) → negative; as the chin
    /// drops (forward-head / tech-neck) the nose rotates down and back toward —
    /// then through — the ear plane (noseZ → earMidZ and beyond) → pitch rises to
    /// positive, exactly as the 2D "nose below the ear line → positive" rule does.
    /// The absolute zero is geometric, not physiological; rest-relative calibration
    /// re-zeros it downstream. Ear pair primary, eye pair fallback (mirrors 2D).
    private func computeHeadPitch3D(
        from pose: PoseObservation,
        depthSamples: [DepthAtPoint],
        intrinsics: simd_float3x3
    ) -> Float? {
        guard let nose = keypoint(.nose, from: pose) else { return nil }

        let left: Keypoint
        let right: Keypoint
        if let le = keypoint(.leftEar, from: pose), let re = keypoint(.rightEar, from: pose) {
            left = le
            right = re
        } else if let le = keypoint(.leftEye, from: pose), let re = keypoint(.rightEye, from: pose) {
            left = le
            right = re
        } else {
            return nil
        }

        // Every reference point needs a valid depth sample, else fall back to 2D.
        guard let noseDepth = findDepth(for: nose.position, in: depthSamples),
              let leftDepth = findDepth(for: left.position, in: depthSamples),
              let rightDepth = findDepth(for: right.position, in: depthSamples)
        else {
            return nil
        }

        let nose3D = unproject(
            point: SIMD2<Float>(Float(nose.position.x), Float(nose.position.y)),
            depth: noseDepth,
            intrinsics: intrinsics
        )
        let left3D = unproject(
            point: SIMD2<Float>(Float(left.position.x), Float(left.position.y)),
            depth: leftDepth,
            intrinsics: intrinsics
        )
        let right3D = unproject(
            point: SIMD2<Float>(Float(right.position.x), Float(right.position.y)),
            depth: rightDepth,
            intrinsics: intrinsics
        )

        let earMid = (left3D + right3D) / 2
        let interaural = simd_length(left3D - right3D)
        guard interaural > 1e-6 else { return nil }  // degenerate ear plane

        let depthOffset = nose3D.z - earMid.z  // +ve = nose farther than ears
        return atan2(depthOffset, interaural) * (180.0 / .pi)
    }

    // MARK: - Helpers

    private func keypoint(_ joint: Joint, from pose: PoseObservation) -> Keypoint? {
        pose.keypoints.first {
            $0.joint == joint && $0.confidence >= Self.minKeypointConfidence
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
