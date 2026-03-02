//
//  ContentView.swift
//  Quant
//
//  Created by Learning on 27/12/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showSettings = false

    var body: some View {
        ZStack {
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

            if appModel.needsCalibration {
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
        }
        .padding()
        .sheet(isPresented: $showSettings) {
            CalibrationSettingsView()
        }
    }

    private var monitoringView: some View {
        VStack {
            Image(systemName: "person.fill.viewfinder")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Quant: Posture Detection")
                .font(.title2)
                .padding(.top, 8)

            Text("Monitoring Active")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
