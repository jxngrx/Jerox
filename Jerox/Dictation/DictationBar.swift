import CoreGraphics
import Foundation
import SwiftUI

@Observable
final class LoaderState {
    var label = ""
}

struct DictateMark: View {
    var state: DictateState
    var onStop: () -> Void

    private var clock: String {
        let seconds = Int(state.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        let radius: CGFloat = state.closing ? 14 : (state.text.isEmpty ? 20 : 16)
        if state.closing {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(JeroxInk.graphite, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
        VStack(spacing: 0) {
            if !state.text.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(state.text)
                            .font(.system(size: 14))
                            .italic()
                            .foregroundStyle(Color.white.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("tail")
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(.bottom)
                    .frame(height: dictateBox(text: state.text).textHeight)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22), .init(color: .black, location: 1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .onChange(of: state.text) { _, _ in
                        proxy.scrollTo("tail", anchor: .bottom)
                    }
                }
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.98, green: 0.33, blue: 0.42))
                    .frame(width: 7, height: 7)
                    .padding(.leading, 4)
                Spacer(minLength: 0)
                if !state.text.isEmpty {
                    Text(clock)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .monospacedDigit()
                }
                Button(action: onStop) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .overlay {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array(state.bars.enumerated()), id: \.offset) { _, level in
                        Capsule()
                            .fill(JeroxInk.silver)
                            .frame(width: 4, height: max(3, 16 * level))
                    }
                }
                .frame(height: 18)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(JeroxInk.graphite, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
    }
}

struct LoaderMark: View {
    var state: LoaderState

    var body: some View {
        Group {
            if state.label.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                Text(state.label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(3)
                    .padding(.horizontal, 10)
            }
        }
        .tint(JeroxInk.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .jeroxPanel(radius: 9)
    }
}
