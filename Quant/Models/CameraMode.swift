enum CameraMode: String, Codable, CaseIterable {
    case rearDepth
    case front2D
    /// Front TrueDepth ARKit face tracking (Layer 1): metric 6-DOF head pose from
    /// `ARFaceAnchor`, with shoulders still recovered via Vision for side-lean.
    /// Only selectable on devices where `ARFaceTrackingService.isFaceTrackingSupported`.
    case frontFace
}
