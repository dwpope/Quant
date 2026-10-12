import PostureLogic

/// Stopping the camera while the phone is too hot, and starting it again once it cools
/// (2026-10-11).
///
/// At a critical thermal level the pipeline stops looking at frames and the screen says
/// detection is paused to cool down, but the camera, the main source of the heat, kept running.
enum HeatPause {
    enum Action: Equatable {
        case stopCamera
        case startCamera
        case none
    }

    /// What to do on a new thermal level, given whether the camera is stopped for heat now.
    static func action(for level: ThermalLevel, cameraStoppedForHeat: Bool) -> Action {
        switch (level == .critical, cameraStoppedForHeat) {
        case (true, false): return .stopCamera
        case (false, true): return .startCamera
        default: return .none
        }
    }
}
