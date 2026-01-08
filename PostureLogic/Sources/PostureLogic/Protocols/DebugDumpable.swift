import Foundation

public protocol DebugDumpable {
    var debugState: [String: Any] { get }
}
