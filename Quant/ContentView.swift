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
    @State private var showSipTimeline = false
    @State private var showSipCalibration = false
    @State private var showVisualization = false

    /// Height of the diagnostics panel, measured live. While the panel is collapsed, the posture
    /// and hydration cards start below it instead of under its top line.
    @State private var panelHeight: CGFloat = 0

    /// Mirrors the panel's own expanded state. Expanded, the panel is a diagnostics view that
    /// covers the cards on purpose. Pushing the cards below it put them under the bottom icons.
    @AppStorage(DiagnosticsPanel.expandedKey) private var panelExpanded = true

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
                case .frontFace:
                    CameraPreviewView(session: appModel.arFaceService.session)
                        .ignoresSafeArea()
                }
            }

            if appModel.cameraMode == .front2D && appModel.frontCameraBlocked {
                CameraPermissionView {
                    Task { await appModel.retryFrontCamera() }
                }
            } else if appModel.cameraMode == .rearDepth && appModel.rearCameraStatus != .ok {
                RearCameraProblemView(status: appModel.rearCameraStatus) {
                    Task { await appModel.retryRearCamera() }
                }
            } else if appModel.needsCalibration {
                CalibrationView(appModel: appModel)
            } else {
                monitoringView
            }

            // Diagnostics panel, top-leading, with the icon controls pinned below it.
            //
            // The controls live in a bottom safe-area inset rather than after a Spacer, so the
            // panel is offered only the height above them. The panel scrolls when its content is
            // taller than that (see ScrollableHUD). Before this, the panel was a fixed-height
            // VStack: on an iPhone 15 Pro, Jev results made it taller than the screen, and it
            // spilled off both ends and pushed Recalibrate out of reach.
            //
            // Recalibrate now lives in the panel's top line. The bottom row keeps icon buttons
            // only, which have a fixed size and cannot be squeezed to one letter wide.
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    DebugOverlayView(appModel: appModel)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            panelHeight = $0
                        }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .safeAreaInset(edge: .bottom, spacing: 12) {
                HStack(spacing: 12) {
                    Spacer(minLength: 0)

                    Button {
                        showSipCalibration = true
                    } label: {
                        Image(systemName: "drop.circle")
                            .font(.title2)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Sip calibration")

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
                    .accessibilityLabel("Settings")

                    Button {
                        appModel.showCameraPreview.toggle()
                    } label: {
                        Image(systemName: appModel.showCameraPreview ? "eye.fill" : "eye.slash")
                            .font(.title2)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(appModel.showCameraPreview ? "Hide camera preview" : "Show camera preview")
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
        // Clears the collapsed panel: it sits 16pt below the safe area, and the cards keep a
        // 12pt gap under it after their own 24pt of padding.
        .contentMargins(.top, panelExpanded ? 0 : panelHeight + 4, for: .scrollContent)
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
