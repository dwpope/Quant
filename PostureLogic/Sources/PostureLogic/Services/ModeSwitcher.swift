import Foundation

/// Automatically switches between DepthFusion and TwoDOnly modes based on depth confidence.
///
/// The switcher prevents rapid mode changes by requiring sustained good depth confidence
/// for `depthRecoveryDelay` seconds before switching back to depth fusion mode.
public final class ModeSwitcher {
    // MARK: - Public Properties

    /// The current depth mode in use
    public private(set) var currentMode: DepthMode = .depthFusion

    // MARK: - Private Properties

    private let thresholds: PostureThresholds

    /// Timestamp when good depth confidence first returned (used for recovery delay)
    private var goodDepthStartTime: TimeInterval?

    // MARK: - Initialization

    public init(thresholds: PostureThresholds) {
        self.thresholds = thresholds
    }

    // MARK: - Public Methods

    /// Updates the current mode based on depth confidence.
    ///
    /// Mode switching logic:
    /// - **DepthFusion → TwoDOnly**: Immediate when confidence drops below medium
    /// - **TwoDOnly → DepthFusion**: Delayed by `depthRecoveryDelay` to prevent flickering
    ///
    /// - Parameters:
    ///   - confidence: Current depth confidence level
    ///   - timestamp: Current timestamp for tracking recovery delay
    /// - Returns: The updated current mode
    public func update(confidence: DepthConfidence, timestamp: TimeInterval) -> DepthMode {
        switch currentMode {
        case .depthFusion:
            // Switch to 2D mode immediately if depth confidence drops
            if confidence < .medium {
                currentMode = .twoDOnly
                goodDepthStartTime = nil
            }

        case .twoDOnly:
            // Only switch back to depth fusion after sustained good confidence
            if confidence >= .medium {
                if let start = goodDepthStartTime {
                    // Check if we've had good depth for long enough
                    if timestamp - start >= thresholds.depthRecoveryDelay {
                        currentMode = .depthFusion
                        goodDepthStartTime = nil
                    }
                } else {
                    // Start the recovery timer
                    goodDepthStartTime = timestamp

                    // Handle zero delay case - switch immediately
                    if thresholds.depthRecoveryDelay <= 0 {
                        currentMode = .depthFusion
                        goodDepthStartTime = nil
                    }
                }
            } else {
                // Confidence dropped again, reset the recovery timer
                goodDepthStartTime = nil
            }
        }

        return currentMode
    }

    /// Resets the mode switcher to initial state (DepthFusion mode)
    public func reset() {
        currentMode = .depthFusion
        goodDepthStartTime = nil
    }
}
