import Foundation

public enum CalibrationStatus: Equatable {
    case waiting
    case sampling
    case validating
    case success
    case failed(String)
}
