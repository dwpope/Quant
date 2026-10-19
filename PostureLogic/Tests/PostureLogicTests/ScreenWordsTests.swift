import XCTest

/// The words the screens use, checked by reading the source (2026-10-19).
///
/// Forward lean was "Forward Creep" on Posture Thresholds and "Forward Lean" on Calibration and
/// the Watch: the same setting under two names. "Forward creep" is the code's name for it; the
/// screens say forward lean.
final class ScreenWordsTests: XCTestCase {

    /// The repository root, from this file's own path.
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PostureLogicTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // PostureLogic
            .deletingLastPathComponent()   // repository root
    }

    /// Every Swift file of the two apps, path relative to the root, with its text.
    private func appSources() throws -> [(path: String, text: String)] {
        var out: [(String, String)] = []
        for folder in ["Quant", "QuantWatch Watch App"].map({ root.appendingPathComponent($0) }) {
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
                out.append((path, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return out
    }

    func test_theSourcesAreFound() throws {
        let files = try appSources()
        XCTAssertTrue(files.contains { $0.path.hasSuffix("ThresholdsSettingsView.swift") })
        XCTAssertTrue(files.contains { $0.path.hasSuffix("CalibrationSettingsView.swift") })
    }

    /// A line's string literals, escapes and empty strings included.
    private let literal = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)

    func test_stringLiterals_areFound() {
        let line = #"Text("") + Text("a \"b\" c") // "comment""#
        let range = NSRange(line.startIndex..., in: line)
        let found = literal.matches(in: line, range: range).map { (line as NSString).substring(with: $0.range(at: 1)) }
        XCTAssertEqual(found, ["", #"a \"b\" c"#, "comment"])
    }

    /// No screen calls forward lean "creep": not in a title, a caption or a label. Comments
    /// aren't shown, so they're skipped. (The diagnostics panel shows the code's own names for
    /// the nudge reasons, `forwardCreep` among them: it's for testing, not for reading.)
    func test_noScreen_saysForwardCreep() throws {
        for file in try appSources() {
            for line in file.text.split(separator: "\n").map(String.init)
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let range = NSRange(line.startIndex..., in: line)
                for match in literal.matches(in: line, range: range) {
                    let text = (line as NSString).substring(with: match.range(at: 1)).lowercased()
                    if text.contains("forward creep") || text.contains("fwd creep") {
                        XCTFail("\(file.path) shows \"\(text)\": the screens call it forward lean")
                    }
                }
            }
        }
    }
}
