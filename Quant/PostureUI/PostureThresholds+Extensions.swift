import PostureLogic

extension PostureThresholds {
    func threshold(for key: MetricKey) -> Float {
        switch key {
        case .forwardCreep:     return forwardCreepThreshold
        case .headDrop:         return headDropThreshold
        case .shoulderRounding: return shoulderRoundingThreshold
        case .lateralLean:      return sideLeanThreshold
        case .twist:            return twistThreshold
        }
    }
}
