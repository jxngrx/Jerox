import CoreGraphics
import Foundation
import SwiftUI

struct PromptPickerView: View {
    static let width: CGFloat = 300
    static let rowPitch: CGFloat = 32
    // header 36 + dividers 2 + list padding 12 + footer 32, less the last row gap.
    static let chrome: CGFloat = 80
    var state: PromptChoice
    var onPick: (RephrasePrompt) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(JeroxInk.accent)
                Text("Rephrase with").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 36)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(state.prompts.enumerated()), id: \.element.id) { index, prompt in
                            Button {
                                onPick(prompt)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(index < 9 ? "\(index + 1)" : "")
                                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 12, alignment: .trailing)
                                    Text(prompt.name)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if index == state.selection {
                                        Image(systemName: "return")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(JeroxInk.accent)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .frame(height: Self.rowPitch - 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                index == state.selection ? JeroxInk.accent.opacity(0.16) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .id(prompt.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: state.selection) { _, _ in
                    guard state.prompts.indices.contains(state.selection) else { return }
                    proxy.scrollTo(state.prompts[state.selection].id, anchor: .center)
                }
            }
            Divider()
            HStack(spacing: 14) {
                hint("↩", "apply")
                hint("Esc", "cancel")
                Spacer(minLength: 0)
                Text("1–9").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .jeroxPanel()
    }

    private func hint(_ key: String, _ name: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(text: key)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
