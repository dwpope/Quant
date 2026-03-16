import PostureLogic

extension RawMetrics {
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

    func value(for key: MetricKey) -> Float {
        switch key {
        case .forwardCreep:     return forwardCreep
        case .headDrop:         return headDrop
        case .shoulderRounding: return shoulderRounding
        case .lateralLean:      return lateralLean
        case .twist:            return twist
        }
    }
}
