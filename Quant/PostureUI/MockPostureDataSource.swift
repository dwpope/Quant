import Foundation
import Combine
import PostureLogic

// MARK: - Simulation Phase

enum SimulationPhase {
    case good(elapsed: TimeInterval)
    case drifting(elapsed: TimeInterval, dominantMetric: MetricKey)
    case bad(elapsed: TimeInterval)
    case recovery(elapsed: TimeInterval)
}

@MainActor
final class MockPostureDataSource: ObservableObject, PostureDataSourceProtocol {

    // MARK: - PostureDataSourceProtocol

    var currentData: PostureDisplayData {
        if isAutoSimulating {
            return _currentData
        } else {
            return buildManualData()
        }
    }

    @Published private var _currentData: PostureDisplayData

    // MARK: - Manual Controls

    @Published var manualForwardCreep: Float = 0.0
    @Published var manualHeadDrop: Float = 0.0
    @Published var manualShoulderRounding: Float = 0.0
    @Published var manualLateralLean: Float = 0.0
    @Published var manualTwist: Float = 0.0
    @Published var manualPostureState: PostureState = .good
    @Published var isAutoSimulating: Bool = true

    // MARK: - Simulation Configuration

    var simulationThresholds: PostureThresholds = PostureThresholds()
    var simulationSpeedMultiplier: Double = 1.0

    // MARK: - Private Simulation State

    private var simulationTimer: Timer?
    private(set) var simulationPhase: SimulationPhase = .good(elapsed: 0)
    private var simulationClock: TimeInterval = 0
    private var currentDominantMetric: MetricKey = .forwardCreep

    // Phase durations (randomized per cycle)
    private var goodPhaseDuration: TimeInterval = 10.0
    private var driftingPhaseDuration: TimeInterval = 20.0
    private var badPhaseDuration: TimeInterval = 15.0
    private var recoveryPhaseDuration: TimeInterval = 4.0

    // Timestamp when current phase started (wall-clock)
    private var phaseStartTime: TimeInterval = Date().timeIntervalSince1970

    // MARK: - Init

    init() {
        self._currentData = PostureDisplayData.make(
            from: .zero,
            postureState: .good,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: PostureThresholds()
        )
        randomizeGoodPhaseDuration()
        startSimulation()
    }

    // MARK: - Timer Management

    func startSimulation() {
        stopSimulation()
        guard isAutoSimulating else { return }
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.simulationTick()
            }
        }
    }

    func stopSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    deinit {
        simulationTimer?.invalidate()
    }

    // MARK: - Simulation Tick (internal for test access)

    func simulationTick() {
        guard isAutoSimulating else { return }
        let dt = (1.0 / 30.0) * simulationSpeedMultiplier
        simulationClock += dt
        advancePhase(by: dt)
        _currentData = buildSimulationData()
    }

    // MARK: - Phase Advancement

    private func advancePhase(by dt: TimeInterval) {
        switch simulationPhase {
        case .good(let elapsed):
            let newElapsed = elapsed + dt
            if newElapsed >= goodPhaseDuration {
                enterDriftingPhase()
            } else {
                simulationPhase = .good(elapsed: newElapsed)
            }

        case .drifting(let elapsed, let dominant):
            let newElapsed = elapsed + dt
            if newElapsed >= driftingPhaseDuration {
                enterBadPhase()
            } else {
                simulationPhase = .drifting(elapsed: newElapsed, dominantMetric: dominant)
            }

        case .bad(let elapsed):
            let newElapsed = elapsed + dt
            if newElapsed >= badPhaseDuration {
                enterRecoveryPhase()
            } else {
                simulationPhase = .bad(elapsed: newElapsed)
            }

        case .recovery(let elapsed):
            let newElapsed = elapsed + dt
            if newElapsed >= recoveryPhaseDuration {
                enterGoodPhase()
            } else {
                simulationPhase = .recovery(elapsed: newElapsed)
            }
        }
    }

    // MARK: - Phase Transitions

    private func enterGoodPhase() {
        randomizeGoodPhaseDuration()
        simulationPhase = .good(elapsed: 0)
        phaseStartTime = Date().timeIntervalSince1970
    }

    private func enterDriftingPhase() {
        driftingPhaseDuration = TimeInterval.random(in: 15...30)
        currentDominantMetric = MetricKey.allCases.randomElement()!
        simulationPhase = .drifting(elapsed: 0, dominantMetric: currentDominantMetric)
        phaseStartTime = Date().timeIntervalSince1970
    }

    private func enterBadPhase() {
        badPhaseDuration = TimeInterval.random(in: 10...20)
        simulationPhase = .bad(elapsed: 0)
        phaseStartTime = Date().timeIntervalSince1970
    }

    private func enterRecoveryPhase() {
        recoveryPhaseDuration = TimeInterval.random(in: 3...5)
        simulationPhase = .recovery(elapsed: 0)
        phaseStartTime = Date().timeIntervalSince1970
    }

    private func randomizeGoodPhaseDuration() {
        goodPhaseDuration = TimeInterval.random(in: 8...12)
    }

    // MARK: - Simulation Data Builder

    private func buildSimulationData() -> PostureDisplayData {
        let (raw, postureState, nudgeDecision) = computeSimulationState()
        return PostureDisplayData.make(
            from: raw,
            postureState: postureState,
            nudgeDecision: nudgeDecision,
            trackingQuality: .good,
            thresholds: simulationThresholds
        )
    }

    private func computeSimulationState() -> (RawMetrics, PostureState, NudgeDecision) {
        switch simulationPhase {
        case .good(let elapsed):
            _ = elapsed
            let raw = buildGoodPhaseMetrics()
            return (raw, .good, .none)

        case .drifting(let elapsed, let dominantMetric):
            let raw = buildDriftingPhaseMetrics(elapsed: elapsed, dominant: dominantMetric)
            let remaining = simulationThresholds.slouchDurationBeforeNudge - elapsed
            return (
                raw,
                .drifting(since: phaseStartTime),
                .pending(reason: .sustainedSlouch, timeRemaining: max(0, remaining))
            )

        case .bad(let elapsed):
            let raw = buildBadPhaseMetrics()
            let nudge: NudgeDecision = elapsed < 2.0
                ? .fire(reason: .sustainedSlouch)
                : .none
            return (raw, .bad(since: phaseStartTime), nudge)

        case .recovery(let elapsed):
            let raw = buildRecoveryPhaseMetrics(elapsed: elapsed)
            return (raw, .good, .none)
        }
    }

    // MARK: - Phase Metric Generators

    /// Good phase: layered sine waves at irrational frequencies, ±5% threshold amplitude.
    private func buildGoodPhaseMetrics() -> RawMetrics {
        let t = simulationClock
        func noise(_ seed: Double) -> Float {
            let v = sin(t * 1.1 + seed) * 0.5
                  + sin(t * 1.7 + seed * 2.0) * 0.3
                  + sin(t * 2.3 + seed * 3.0) * 0.2
            return Float(v) * 0.05
        }

        return RawMetrics(
            timestamp: Date().timeIntervalSince1970,
            forwardCreep: noise(0.0) * simulationThresholds.forwardCreepThreshold,
            headDrop: noise(1.0) * simulationThresholds.headDropThreshold,
            shoulderRounding: noise(2.0) * simulationThresholds.shoulderRoundingThreshold,
            lateralLean: noise(3.0) * simulationThresholds.sideLeanThreshold,
            twist: noise(4.0) * simulationThresholds.twistThreshold,
            movementLevel: 0,
            headMovementPattern: .still
        )
    }

    /// Drifting phase: dominant metric ramps 0→1.2× threshold via ease-in curve.
    private func buildDriftingPhaseMetrics(elapsed: TimeInterval, dominant: MetricKey) -> RawMetrics {
        let progress = min(1.0, elapsed / driftingPhaseDuration)
        let easeIn = Float(progress * progress) // quadratic ease-in
        let rampMultiplier = easeIn * 1.2

        func metricValue(for key: MetricKey) -> Float {
            let threshold = simulationThresholds.threshold(for: key)
            if key == dominant {
                return rampMultiplier * threshold
            }
            // Subtle noise for non-dominant metrics
            let seed = Double(key.rawValue.hashValue)
            let noise = Float(sin(simulationClock * 1.3 + seed) * 0.03)
            return noise * threshold
        }

        return RawMetrics(
            timestamp: Date().timeIntervalSince1970,
            forwardCreep: metricValue(for: .forwardCreep),
            headDrop: metricValue(for: .headDrop),
            shoulderRounding: metricValue(for: .shoulderRounding),
            lateralLean: metricValue(for: .lateralLean),
            twist: metricValue(for: .twist),
            movementLevel: 0,
            headMovementPattern: .still
        )
    }

    /// Bad phase: dominant metric stays elevated at ~1.2× threshold with slight oscillation.
    private func buildBadPhaseMetrics() -> RawMetrics {
        let t = simulationClock
        func metricValue(for key: MetricKey) -> Float {
            let threshold = simulationThresholds.threshold(for: key)
            if key == currentDominantMetric {
                let oscillation = Float(sin(t * 0.5) * 0.05)
                return (1.2 + oscillation) * threshold
            }
            let seed = Double(key.rawValue.hashValue)
            let noise = Float(sin(t * 1.3 + seed) * 0.03)
            return noise * threshold
        }

        return RawMetrics(
            timestamp: Date().timeIntervalSince1970,
            forwardCreep: metricValue(for: .forwardCreep),
            headDrop: metricValue(for: .headDrop),
            shoulderRounding: metricValue(for: .shoulderRounding),
            lateralLean: metricValue(for: .lateralLean),
            twist: metricValue(for: .twist),
            movementLevel: 0,
            headMovementPattern: .still
        )
    }

    /// Recovery phase: dominant metric eases from 1.2× to zero over the recovery duration.
    private func buildRecoveryPhaseMetrics(elapsed: TimeInterval) -> RawMetrics {
        let progress = Float(min(1.0, elapsed / recoveryPhaseDuration))
        let easeOut = 1.0 - progress * progress // quadratic ease-out

        func metricValue(for key: MetricKey) -> Float {
            let threshold = simulationThresholds.threshold(for: key)
            if key == currentDominantMetric {
                return easeOut * 1.2 * threshold
            }
            return 0
        }

        return RawMetrics(
            timestamp: Date().timeIntervalSince1970,
            forwardCreep: metricValue(for: .forwardCreep),
            headDrop: metricValue(for: .headDrop),
            shoulderRounding: metricValue(for: .shoulderRounding),
            lateralLean: metricValue(for: .lateralLean),
            twist: metricValue(for: .twist),
            movementLevel: 0,
            headMovementPattern: .still
        )
    }

    // MARK: - Manual Mode

    private func buildManualData() -> PostureDisplayData {
        let raw = RawMetrics(
            timestamp: Date().timeIntervalSince1970,
            forwardCreep: manualForwardCreep,
            headDrop: manualHeadDrop,
            shoulderRounding: manualShoulderRounding,
            lateralLean: manualLateralLean,
            twist: manualTwist,
            movementLevel: 0,
            headMovementPattern: .still
        )

        return PostureDisplayData.make(
            from: raw,
            postureState: manualPostureState,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: simulationThresholds
        )
    }

    // MARK: - Preview Factory

    static func preview(
        state: PostureState = .good,
        worstMetric: MetricKey? = nil,
        worstRatio: Float = 0.0
    ) -> MockPostureDataSource {
        let source = MockPostureDataSource()
        source.stopSimulation()
        source.isAutoSimulating = false
        source.manualPostureState = state

        if let metric = worstMetric {
            let threshold = source.simulationThresholds.threshold(for: metric)
            let value = worstRatio * threshold
            switch metric {
            case .forwardCreep:     source.manualForwardCreep = value
            case .headDrop:         source.manualHeadDrop = value
            case .shoulderRounding: source.manualShoulderRounding = value
            case .lateralLean:      source.manualLateralLean = value
            case .twist:            source.manualTwist = value
            }
        }

        return source
    }
}
