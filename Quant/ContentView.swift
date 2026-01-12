//
//  ContentView.swift
//  Quant
//
//  Created by Learning on 27/12/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showingCalibration = false

    var body: some View {
        ZStack {
            VStack {
                Image(systemName: "person.fill.viewfinder")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Quant: Posture Detection")
                    .font(.title2)
                    .padding(.top, 8)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                // Calibration button
                Button {
                    showingCalibration = true
                } label: {
                    HStack {
                        Image(systemName: appModel.baseline != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        Text(appModel.baseline != nil ? "Recalibrate" : "Calibrate")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(appModel.baseline != nil ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundStyle(appModel.baseline != nil ? .green : .orange)
                    .cornerRadius(8)
                }
                .padding(.top, 16)

                if let baseline = appModel.baseline {
                    VStack(spacing: 4) {
                        Text("Baseline Info")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text("Captured: \(formatDate(baseline.timestamp))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Depth: \(baseline.depthAvailable ? "Available" : "Not Available")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }

            // Debug overlay positioned in top-leading corner
            VStack {
                HStack {
                    DebugOverlayView(appModel: appModel)
                        .padding()
                    Spacer()
                }
                Spacer()
            }
        }
        .padding()
        .sheet(isPresented: $showingCalibration) {
            CalibrationView(appModel: appModel)
        }
        .onAppear {
            // Show calibration on first launch if needed
            if appModel.needsCalibration {
                showingCalibration = true
            }
        }
    }

    private var statusText: String {
        if appModel.baseline != nil {
            return "Monitoring Active"
        } else {
            return "Calibration Required"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
