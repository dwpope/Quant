//
//  ContentView.swift
//  Quant
//
//  Created by Learning on 27/12/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "person.fill.viewfinder")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Quant: Posture Detection")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
