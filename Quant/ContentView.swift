//
//  ContentView.swift
//  Quant
//
//  Created by Learning on 27/12/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        ZStack {
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

                if !appModel.needsCalibration {
                    HStack {
                        Spacer()
                        Button("Recalibrate") {
                            appModel.recalibrate()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .padding()
                    }
                }
            }
        }
        .padding()
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
