//
//  MarkGridView.swift
//  QuantWatch Watch App
//
//  The first screen: six marks, Calibrate and the camera, on one screen without scrolling.
//

import SwiftUI

/// Eight tiles in two columns and four rows, sized to the screen so nothing scrolls (2026-11-27).
/// The marks come first; Calibrate and the camera's view, which Dave wanted on the first screen
/// too, are the bottom row, tinted so they don't read as marks.
struct MarkGridView: View {
    @ObservedObject var sessionDelegate: WatchSessionDelegate
    /// The tile that just took a tap, to show a tick for a second.
    @State private var justMarked: SessionMark?

    private let spacing: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let rowHeight = max(36, (geometry.size.height - spacing * 3) / 4)
            let columns = [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)]
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(SessionMark.allCases) { mark in
                    Button { tap(mark) } label: {
                        tile(title: mark.title,
                             symbol: justMarked == mark ? "checkmark" : mark.symbol)
                    }
                    .buttonStyle(TileStyle(colour: mark == .sittingWell ? .green : .gray))
                    .frame(height: rowHeight)
                    .accessibilityLabel(Text(mark.title))
                }
                Button { sessionDelegate.sendCalibrateRequest() } label: {
                    tile(title: "Calibrate", symbol: "scope")
                }
                .buttonStyle(TileStyle(colour: .accentColor, filled: true))
                .frame(height: rowHeight)
                .disabled(!sessionDelegate.isConnected)

                Button {
                    sessionDelegate.setCameraPreview(show: !sessionDelegate.phoneShowsCamera)
                } label: {
                    tile(title: "Camera", symbol: sessionDelegate.phoneShowsCamera ? "eye.slash" : "eye")
                }
                .buttonStyle(TileStyle(colour: .blue))
                .frame(height: rowHeight)
                .disabled(!sessionDelegate.isPhoneReachable)
                .accessibilityLabel(Text(CameraPreviewRemote.buttonTitle(phoneShows: sessionDelegate.phoneShowsCamera)))
            }
        }
        .navigationTitle("Mark")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tap(_ mark: SessionMark) {
        sessionDelegate.sendMark(mark)
        justMarked = mark
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if justMarked == mark { justMarked = nil }
        }
    }
}

/// A tile that fills its grid cell exactly. The system's bordered buttons have a taller minimum
/// than a quarter of the smallest screen, so their rows overlapped.
private struct TileStyle: ButtonStyle {
    let colour: Color
    var filled = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(filled ? Color.white : colour == .gray ? Color.white : colour)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colour.opacity(filled ? 0.85 : 0.25)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
