//
//  CameraPermissionView.swift
//  Quant
//
//  Created for Ticket 4.7.5 - Permission/Error UX
//

import SwiftUI

/// Shown when the front camera cannot start because permission is denied or restricted.
///
/// Provides two recovery paths:
/// - **Open Settings** — takes the user to the app's Settings page to grant camera access.
/// - **Try Again** — re-attempts `start()` on the front camera service, which will
///   succeed if the user granted permission while the app was backgrounded.
///
/// The user can also switch back to the rear camera via the settings sheet,
/// which remains accessible from the toolbar at the bottom of ContentView.
struct CameraPermissionView: View {
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Quant needs camera access to track your posture.\nPlease enable it in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Try Again", action: onRetry)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

#Preview {
    CameraPermissionView(onRetry: {})
}
