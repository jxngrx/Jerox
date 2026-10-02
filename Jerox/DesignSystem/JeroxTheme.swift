import AppKit
import CoreGraphics
import Foundation
import SwiftUI

enum JeroxInk {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let field = Color(nsColor: .textBackgroundColor)
    // systemBlue adapts its shade for light and dark, so contrast holds in both.
    static let accent = Color(nsColor: .systemBlue)
    static let graphite = Color(red: 0.13, green: 0.14, blue: 0.17)
    static let silver = LinearGradient(
        colors: [Color(red: 0.93, green: 0.94, blue: 0.96), Color(red: 0.62, green: 0.65, blue: 0.71)],
        startPoint: .top, endPoint: .bottom
    )
    static let danger = Color.red
    static let ink = Color.primary
}

/// The Jerox mark, from the bundled app icon.
struct JeroxLogo: View {
    var size: CGFloat

    var body: some View {
        if let image = NSImage(named: "jerox-icon") {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        }
    }
}


struct IconButtonStyle: ButtonStyle {
    var destructive = false
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hover ? (destructive ? JeroxInk.danger : JeroxInk.accent) : Color.secondary)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.12 : hover ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .onHover { hover = $0 }
    }
}

struct ToastView: View {
    var message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(JeroxInk.danger)
            Text(message).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .jeroxPanel(radius: 20)
        .fixedSize()
    }
}

extension View {
    /// Shared chrome for every floating Jerox panel.
    func jeroxPanel(radius: CGFloat = 12) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

func applyTheme(_ name: String) {
    switch name {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
    default: NSApp.appearance = nil
    }
}
