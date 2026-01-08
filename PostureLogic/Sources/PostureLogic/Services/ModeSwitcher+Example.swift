import Foundation

// MARK: - ModeSwitcher Usage Example
//
// This file demonstrates how to use ModeSwitcher in your pipeline.
// Delete this file when you understand the usage pattern.

#if DEBUG
extension ModeSwitcher {
    /// Example usage of ModeSwitcher in a processing pipeline
    static func usageExample() {
        let thresholds = PostureThresholds()
        let switcher = ModeSwitcher(thresholds: thresholds)

        // In your frame processing loop:
        func processFrame(frame: InputFrame, depthService: inout DepthServiceProtocol) {
            // 1. Compute depth confidence from the current frame
            let depthConfidence = depthService.computeConfidence(from: frame)

            // 2. Update the mode switcher with current confidence and timestamp
            let currentMode = switcher.update(
                confidence: depthConfidence,
                timestamp: frame.timestamp
            )

            // 3. Use the current mode to determine which processing path to take
            switch currentMode {
            case .depthFusion:
                print("Using depth fusion mode - 3D position tracking active")
                // Process with depth data for accurate 3D positions

            case .twoDOnly:
                print("Using 2D-only mode - falling back to 2D analysis")
                // Process without depth, use ratio-based metrics
            }
        }

        // The switcher automatically prevents mode flickering by requiring
        // sustained good depth (default 2 seconds) before switching back to DepthFusion
    }

    /// Example of handling mode changes
    static func modeChangeHandlingExample() {
        let thresholds = PostureThresholds()
        let switcher = ModeSwitcher(thresholds: thresholds)

        var previousMode: DepthMode = .depthFusion

        func onFrameUpdate(confidence: DepthConfidence, timestamp: TimeInterval) {
            let newMode = switcher.update(confidence: confidence, timestamp: timestamp)

            // Detect mode changes
            if newMode != previousMode {
                print("Mode changed: \(previousMode) → \(newMode)")

                switch newMode {
                case .depthFusion:
                    // Depth is now available and stable
                    // Could show "3D tracking active" in UI
                    break

                case .twoDOnly:
                    // Depth became unavailable
                    // Could show "2D mode" indicator in UI
                    break
                }

                previousMode = newMode
            }
        }
    }
}
#endif
