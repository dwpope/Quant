import Foundation
import CoreVideo
import simd

public enum TestScenarios {
    /// 60 seconds of perfect posture
    public static var goodPosture: TestScenario {
        let frame = InputFrame(
            timestamp: Date().timeIntervalSince1970,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        // Expected state is just Good for Sprint 0 simplicity
        return TestScenario(
            name: "Good Posture",
            frames: [frame],
            expectedStates: [(frame.timestamp, .good)]
        )
    }
    
    /// Starts good, gradually slouches over 10 minutes (Stub)
    public static var gradualSlouch: TestScenario { 
        goodPosture // Placeholder
    }
    
    /// Good posture but depth drops out intermittently (Stub)
    public static var intermittentDepth: TestScenario { 
        goodPosture // Placeholder
    }
    
    /// User leaves and returns to frame (Stub)
    public static var userAbsent: TestScenario { 
        goodPosture // Placeholder
    }
    
    /// Rapid movements (stretching) (Stub)
    public static var stretching: TestScenario { 
        goodPosture // Placeholder
    }
    
    /// Alternating reading and typing (Stub)
    public static var mixedTasks: TestScenario { 
        goodPosture // Placeholder
    }
}

public struct TestScenario {
    public let name: String
    public let frames: [InputFrame]
    public let expectedStates: [(timestamp: TimeInterval, state: PostureState)]
    
    public init(name: String, frames: [InputFrame], expectedStates: [(timestamp: TimeInterval, state: PostureState)]) {
        self.name = name
        self.frames = frames
        self.expectedStates = expectedStates
    }
}
