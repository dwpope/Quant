//
//  RearCameraProblemView.swift
//  Quant
//
//  The rear camera's recovery screen, following CameraPermissionView (front camera).
//

import SwiftUI

/// Shown when the rear camera can't run, so a failure is a screen with a way out rather than
/// a silent blank. Permission problems reuse `CameraPermissionView`, which links to Settings.
/// Anything else offers a retry and a reminder that the camera can be switched in Settings.
struct RearCameraProblemView: View {
    let status: RearCameraStatus
    var onRetry: () -> Void

    var body: some View {
        switch status {
        case .ok:
            EmptyView()
        case .unauthorized:
            CameraPermissionView(onRetry: onRetry)
        case .unavailable(let reason):
            VStack(spacing: 16) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Rear Camera Not Available")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(reason)\nTry again, or switch to the front camera with the gear icon below.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

#Preview {
    RearCameraProblemView(status: .unavailable(reason: "The rear camera isn't sending any images."), onRetry: {})
}
