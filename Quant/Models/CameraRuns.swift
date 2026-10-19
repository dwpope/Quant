/// Which run of a camera a delayed restart belongs to (2026-10-19 review of the heat pause).
///
/// The camera services restart their own sessions half a second or a second after a frame
/// timeout or a failure. A restart queued just before `stop()` ran after it, so a heat pause's
/// stop could be undone and the camera, the main source of the heat, came back on. Each start is
/// a new run and a stop ends it; a restart goes ahead only while its run is still going.
struct CameraRuns {
    /// The latest run.
    private(set) var current = 0
    private var running = false

    mutating func started() {
        current += 1
        running = true
    }

    mutating func stopped() {
        running = false
    }

    /// Whether `run` is still going: not stopped since, and not replaced by a newer start.
    func isStill(_ run: Int) -> Bool {
        running && run == current
    }
}
