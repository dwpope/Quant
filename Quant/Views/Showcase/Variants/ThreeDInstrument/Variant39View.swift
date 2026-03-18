import SwiftUI
import PostureLogic

/// Variant 39: Oscilloscope — Five real-time waveform traces on a simulated CRT
/// oscilloscope screen. Green phosphor display with dark background, scan lines,
/// and glowing afterimage. Each trace represents one metric as a scrolling waveform.
struct Variant39View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var buffers: [[Float]] = Array(repeating: Array(repeating: 0, count: 120), count: 5)
    @State private var writeHead: Int = 0

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // CRT dark background
                Color(red: 0.02, green: 0.05, blue: 0.02)
                    .ignoresSafeArea()

                if isAbsent {
                    AbsenceOverlay {
                        oscilloscopeContent(size: geo.size)
                    }
                } else {
                    oscilloscopeContent(size: geo.size)
                }

                VStack {
                    HStack {
                        Spacer()
                        SettingsGearButton { showingSettings = true }
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
    }

    private func oscilloscopeContent(size: CGSize) -> some View {
        let channelLabels = ["FWD", "HEAD", "SHLD", "LEAN", "TWST"]
        let channelKeys: [MetricKey] = [.forwardCreep, .headDrop, .shoulderRounding, .lateralLean, .twist]

        return TimelineView(.animation) { timeline in
            Canvas { context, canvasSize in
                let width = canvasSize.width
                let height = canvasSize.height
                let channelCount = 5
                let channelHeight = height / CGFloat(channelCount)
                let bufferSize = buffers[0].count

                // Scan lines
                for y in stride(from: 0.0, to: Double(height), by: 3.0) {
                    var scanLine = Path()
                    scanLine.move(to: CGPoint(x: 0, y: y))
                    scanLine.addLine(to: CGPoint(x: width, y: y))
                    context.stroke(scanLine, with: .color(.green.opacity(0.03)), style: StrokeStyle(lineWidth: 1))
                }

                for ch in 0..<channelCount {
                    let channelY = CGFloat(ch) * channelHeight
                    let baselineY = channelY + channelHeight / 2

                    // Channel divider
                    if ch > 0 {
                        var divider = Path()
                        divider.move(to: CGPoint(x: 0, y: channelY))
                        divider.addLine(to: CGPoint(x: width, y: channelY))
                        context.stroke(divider, with: .color(.green.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5))
                    }

                    // Baseline (dashed)
                    var baseline = Path()
                    baseline.move(to: CGPoint(x: 40, y: baselineY))
                    baseline.addLine(to: CGPoint(x: width, y: baselineY))
                    context.stroke(baseline, with: .color(.green.opacity(0.12)),
                                   style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

                    // Channel label
                    let label = "CH\(ch + 1): \(channelLabels[ch])"
                    context.draw(
                        Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.green.opacity(0.7)),
                        at: CGPoint(x: 28, y: baselineY)
                    )

                    // Waveform trace
                    let buffer = buffers[ch]
                    let traceColor: Color = observer.data.isAlertMode && observer.data.worstOffender?.key == channelKeys[ch] ? .red : .green
                    let maxAmplitude = channelHeight * 0.4

                    var tracePath = Path()
                    var started = false
                    for i in 0..<bufferSize {
                        let bufIdx = (writeHead + i) % bufferSize
                        let x = 40 + (width - 40) * CGFloat(i) / CGFloat(bufferSize - 1)
                        let amplitude = CGFloat(buffer[bufIdx]) * maxAmplitude
                        let y = baselineY - amplitude

                        if !started {
                            tracePath.move(to: CGPoint(x: x, y: y))
                            started = true
                        } else {
                            tracePath.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    // Phosphor decay gradient — newer samples (right) brighter
                    let gradient = Gradient(colors: [
                        traceColor.opacity(0.1),
                        traceColor.opacity(0.4),
                        traceColor.opacity(0.8),
                        traceColor
                    ])
                    context.stroke(tracePath, with: .linearGradient(gradient,
                                                                     startPoint: CGPoint(x: 40, y: 0),
                                                                     endPoint: CGPoint(x: width, y: 0)),
                                   style: StrokeStyle(lineWidth: 1.5))
                }

                // Trigger line (right edge)
                var triggerLine = Path()
                triggerLine.move(to: CGPoint(x: width - 2, y: 0))
                triggerLine.addLine(to: CGPoint(x: width - 2, y: height))
                context.stroke(triggerLine, with: .color(.green.opacity(0.3)), style: StrokeStyle(lineWidth: 1))

                // Alert indicator
                if observer.data.isAlertMode {
                    let alertRect = CGRect(x: width - 55, y: 8, width: 50, height: 16)
                    context.stroke(Path(alertRect), with: .color(.red), style: StrokeStyle(lineWidth: 1))
                    context.draw(
                        Text("ALERT").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.red),
                        at: CGPoint(x: alertRect.midX, y: alertRect.midY)
                    )
                }
            }
            .shadow(color: .green.opacity(0.3), radius: 4)
            .onChange(of: timeline.date) {
                updateBuffers()
            }

            // Countdown overlay
            if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
                VStack {
                    Spacer()
                    Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.green.opacity(0.8))
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func updateBuffers() {
        guard !isAbsent else { return }
        let keys: [MetricKey] = [.forwardCreep, .headDrop, .shoulderRounding, .lateralLean, .twist]
        for (i, key) in keys.enumerated() {
            buffers[i][writeHead] = observer.data.metric(for: key).clampedRatio
        }
        writeHead = (writeHead + 1) % buffers[0].count
    }
}

// MARK: - Oscilloscope Buffer (testable)

struct OscilloscopeBuffer {
    private(set) var data: [Float]
    private(set) var writeHead: Int = 0

    init(capacity: Int) {
        data = Array(repeating: 0, count: capacity)
    }

    var capacity: Int { data.count }

    mutating func write(_ value: Float) {
        data[writeHead] = value
        writeHead = (writeHead + 1) % data.count
    }

    func read(offset: Int) -> Float {
        let idx = (writeHead + offset) % data.count
        return data[idx]
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant39View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant39View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant39View()
        .environmentObject(observer)
}
