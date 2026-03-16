struct MetricInfo {
    let key: MetricKey
    let value: Float
    let ratio: Float
    let threshold: Float
    let isWorstOffender: Bool

    var isExceeded: Bool { ratio >= 1.0 }
    var clampedRatio: Float { min(ratio, 1.0) }
}
