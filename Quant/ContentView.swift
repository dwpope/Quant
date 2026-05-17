//
//  ContentView.swift
//  Quant
//
//  Created by Learning on 27/12/2025.
//

import SwiftUI
import PostureLogic

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showSettings = false
    @State private var showShowcase = false
    @State private var showSipTimeline = false
    @State private var showSipCalibration = false
    @State private var showVisualization = false

    var body: some View {
        ZStack {
            // Thermal warning overlays
            if appModel.thermalLevel == .critical {
                thermalCriticalOverlay
            } else if appModel.thermalLevel >= .serious {
                thermalWarningBanner
            }

            if appModel.showCameraPreview {
                switch appModel.cameraMode {
                case .rearDepth:
                    CameraPreviewView(session: appModel.arService.session)
                        .ignoresSafeArea()
                case .front2D:
                    FrontCameraPreviewView(session: appModel.frontService.captureSession)
                        .ignoresSafeArea()
                }
            }

            if appModel.cameraMode == .front2D && appModel.frontCameraBlocked {
                CameraPermissionView {
                    Task { await appModel.retryFrontCamera() }
                }
            } else if appModel.needsCalibration {
                CalibrationView(appModel: appModel)
            } else {
                monitoringView
            }

            // Debug overlay positioned in top-leading corner
            VStack {
                HStack {
                    DebugOverlayView(appModel: appModel)
                        .padding()
                    Spacer()
                }
                Spacer()

                HStack {
                    Picker("Haptic", selection: $appModel.selectedHaptic) {
                        Text("notification").tag("notification")
                        Text("directionUp").tag("directionUp")
                        Text("directionDown").tag("directionDown")
                        Text("success").tag("success")
                        Text("failure").tag("failure")
                        Text("retry").tag("retry")
                        Text("start").tag("start")
                        Text("stop").tag("stop")
                        Text("click").tag("click")
                    }
                    .pickerStyle(.menu)
                    .font(.caption)

                    Button("Test Nudge") {
                        appModel.sendTestNudge()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .padding()

                    Spacer()

                    if !appModel.needsCalibration {
                        Button("Recalibrate") {
                            appModel.recalibrate()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .padding()
                    }

                    Button {
                        showSipCalibration = true
                    } label: {
                        Image(systemName: "drop.circle")
                            .font(.title2)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        showShowcase = true
                    } label: {
                        Image(systemName: "rectangle.stack")
                            .font(.title2)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        showVisualization = true
                    } label: {
                        Image(systemName: "cube.transparent")
                            .font(.title2)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Posture visualization")

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        appModel.showCameraPreview.toggle()
                    } label: {
                        Image(systemName: appModel.showCameraPreview ? "eye.fill" : "eye.slash")
                            .font(.title2)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showSettings) {
            CalibrationSettingsView()
        }
        .sheet(isPresented: $showSipCalibration) {
            SipCalibrationView(appModel: appModel)
        }
        .fullScreenCover(isPresented: $showShowcase) {
            VariantShowcaseView()
        }
        .fullScreenCover(isPresented: $showVisualization) {
            PostureVisualizationView()
        }
    }

    private var monitoringView: some View {
        ScrollView {
            VStack(spacing: 12) {
                PostureCard(
                    postureState: appModel.postureState,
                    trackingQuality: appModel.trackingQuality
                )

                HydrationCard(
                    sipCount: appModel.sipStore.sipCount,
                    lastSipTimestamp: appModel.sipStore.lastSipTimestamp,
                    onTap: { showSipTimeline = true }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .sheet(isPresented: $showSipTimeline) {
            SipTimelineView(appModel: appModel, sipStore: appModel.sipStore)
        }
        .sheet(item: Binding(
            get: { appModel.activeSipLabelItem },
            set: { newValue in
                if newValue == nil, let id = appModel.activeSipLabelItem?.id {
                    appModel.dismissLabelAsUnconfirmed(id: id)
                }
            }
        )) { item in
            SipLabelSheet(
                item: item,
                onLabel: { label in
                    appModel.applyLabel(label, toSipID: item.id)
                },
                onSkip: {
                    appModel.dismissLabelAsUnconfirmed(id: item.id)
                }
            )
        }
    }

    private var thermalWarningBanner: some View {
        VStack {
            HStack {
                Image(systemName: "thermometer.sun.fill")
                    .foregroundStyle(.orange)
                Text("Reduced accuracy \u{2014} device is warm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.top, 60)

            Spacer()
        }
    }

    private var thermalCriticalOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "thermometer.sun.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Cooling down...")
                    .font(.title2)
                    .foregroundStyle(.white)
                Text("Detection paused to prevent overheating")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                ProgressView()
                    .tint(.white)
                    .padding(.top, 8)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
