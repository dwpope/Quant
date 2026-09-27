import PostureLogic

extension RawMetrics {
    /// All-zero metrics: the posture visualization's value before any frame arrives.
    ///
    /// Lived in `PostureUI/RawMetrics+Extensions.swift` until the variant showcase and its data
    /// layer were removed on 2026-09-26. This is the one member the visualization still uses.
    static let zero = RawMetrics(
        timestamp: 0,
        forwardCreep: 0,
        headDrop: 0,
        shoulderRounding: 0,
        lateralLean: 0,
        twist: 0,
        movementLevel: 0,
        headMovementPattern: .still
    )
}
