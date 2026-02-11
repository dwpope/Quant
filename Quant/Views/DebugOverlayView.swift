//
//  DebugOverlayView.swift
//  Quant
//
//  Created for Ticket 1.4 - Debug UI v1 (Minimal)
//

import SwiftUI
import PostureLogic

struct DebugOverlayView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Mode indicator with color
            HStack(spacing: 4) {
                Circle()
                    .fill(modeColor)
                    .frame(width: 6, height: 6)
                Text("Mode: \(appModel.currentMode.rawValue)")
            }

            // Depth confidence with icon
            HStack(spacing: 4) {
                depthIcon
                Text("Depth: \(appModel.depthConfidence.rawValue)")
            }

            // Tracking quality with color
            HStack(spacing: 4) {
                Circle()
                    .fill(trackingColor)
                    .frame(width: 6, height: 6)
                Text("Tracking: \(appModel.trackingQuality.rawValue)")
            }

            // FPS
            Text("FPS: \(appModel.fps, specifier: "%.1f")")

            Divider()

            // Pose sample readout
            Text("Head: \(posePair(appModel.latestSample?.headPosition))")
            Text("L Shldr: \(posePair(appModel.latestSample?.leftShoulder))")
            Text("R Shldr: \(posePair(appModel.latestSample?.rightShoulder))")
            Text("Torso: \(poseAngle(appModel.latestSample?.torsoAngle))")
            Text("Twist: \(poseAngle(appModel.latestSample?.shoulderTwist))")
            Text("Shldr W: \(poseScalar(appModel.latestSample?.shoulderWidthRaw, "%.3f"))")
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private var modeColor: Color {
        switch appModel.currentMode {
        case .depthFusion:
            return .green
        case .twoDOnly:
            return .orange
        }
    }

    private var trackingColor: Color {
        switch appModel.trackingQuality {
        case .good:
            return .green
        case .degraded:
            return .orange
        case .lost:
            return .red
        }
    }

    private func posePair(_ v: SIMD3<Float>?) -> String {
        guard let v = v else { return "(--, --)" }
        return String(format: "(%.2f, %.2f)", v.x, v.y)
    }

    private func poseAngle(_ v: Float?) -> String {
        guard let v = v else { return "--" }
        return String(format: "%.1f°", v)
    }

    private func poseScalar(_ v: Float?, _ fmt: String) -> String {
        guard let v = v else { return "--" }
        return String(format: fmt, v)
    }

    private var depthIcon: some View {
        Group {
            switch appModel.depthConfidence {
            case .high:
                Image(systemName: "l.joystick.tilt.up.fill")
                    .foregroundStyle(.green)
            case .medium:
                Image(systemName: "l.joystick.tilt.up")
                    .foregroundStyle(.yellow)
            case .low:
                Image(systemName: "l.joystick.tilt.down")
                    .foregroundStyle(.orange)
            case .unavailable:
                Image(systemName: "l.joystick")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 10))
    }
}

#Preview {
    DebugOverlayView(appModel: AppModel())
}
