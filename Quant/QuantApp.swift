//
//  QuantApp.swift
//  Quant
//
//  Created by Learning on 27/12/2025.
//

import SwiftUI

@main
struct QuantApp: App {
    @StateObject private var appModel = AppModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .task {
                    await appModel.startMonitoring()
                }
        }
    }
}
