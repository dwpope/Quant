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
            // System Status
            Group {
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
            }

            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.vertical, 2)

            // Posture Metrics
            Group {
                Text("METRICS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                metricRow(
                    label: "Forward",
                    value: appModel.forwardCreep,
                    unit: "m",
                    warningThreshold: 0.08
                )

                metricRow(
                    label: "HeadDrop",
                    value: appModel.headDrop,
                    unit: "m",
                    warningThreshold: 0.05
                )

                metricRow(
                    label: "Lean",
                    value: appModel.lateralLean,
                    unit: "m",
                    warningThreshold: 0.06
                )

                metricRow(
                    label: "Twist",
                    value: appModel.twist,
                    unit: "°",
                    warningThreshold: 12.0
                )

                metricRow(
                    label: "Rounding",
                    value: appModel.shoulderRounding,
                    unit: "m",
                    warningThreshold: 0.05
                )

                metricRow(
                    label: "Movement",
                    value: appModel.movementLevel,
                    unit: "",
                    warningThreshold: 0.7,
                    isMovement: true
                )
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    @ViewBuilder
    private func metricRow(
        label: String,
        value: Float,
        unit: String,
        warningThreshold: Float,
        isMovement: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            // Warning indicator
            Circle()
                .fill(metricColor(value: value, threshold: warningThreshold, isMovement: isMovement))
                .frame(width: 6, height: 6)

            // Label
            Text(label)
                .frame(width: 60, alignment: .leading)

            // Value with unit
            Text(formatValue(value, unit: unit))
                .frame(minWidth: 45, alignment: .trailing)
                .foregroundStyle(metricColor(value: value, threshold: warningThreshold, isMovement: isMovement))
        }
    }

    private func formatValue(_ value: Float, unit: String) -> String {
        let formatted = String(format: "%.2f", value)
        return unit.isEmpty ? formatted : "\(formatted)\(unit)"
    }

    private func metricColor(value: Float, threshold: Float, isMovement: Bool) -> Color {
        if isMovement {
            // Movement level: green is good, yellow for moderate, red for high/erratic
            if value < 0.3 {
                return .green
            } else if value < 0.7 {
                return .yellow
            } else {
                return .orange
            }
        } else {
            // Other metrics: green is good (low), yellow approaching threshold, red over threshold
            if value < threshold * 0.5 {
                return .green
            } else if value < threshold {
                return .yellow
            } else {
                return .red
            }
        }
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
