import AppKit
import Foundation
import SwiftUI

struct PickerView: View {
    var model: AppModel
    var onPaste: (Clip, Bool) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                JeroxLogo(size: 22)
                TextField("Search history", text: Binding(
                    get: { model.history.query },
                    set: { model.history.setQuery($0) }
                ))
                .textFieldStyle(.plain)
                .focused($searchFocused)
            }
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .frame(height: 32)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    rows
                }
                .onChange(of: model.history.selection) { _, _ in scroll(proxy) }
                .onChange(of: model.history.query) { _, _ in scroll(proxy) }
            }
            if let clip = model.history.selectedClip, !clip.text.isEmpty {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(rephrasePromptList(custom: RephrasePromptStore.load())) { prompt in
                            Button(prompt.name) { model.rewrite(clip, instruction: prompt.instruction) }
                        }
                    } label: {
                        Label("Rephrase", systemImage: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .tint(JeroxInk.accent)
                    .disabled(model.aiBusy)
                    .fixedSize()
                    Spacer(minLength: 0)
                    if !model.aiNote.isEmpty {
                        Text(model.aiNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            Divider()
                .padding(.horizontal, 10)
            CommandHints()
                .padding(.top, 7)
                .padding(.bottom, 11)
        }
        .frame(minWidth: PickerMetrics.minWidth, minHeight: PickerMetrics.minHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .jeroxPanel()
        .onAppear { searchFocused = true }
        .onChange(of: model.reveal) { _, _ in searchFocused = true }
    }

    private var rows: some View {
        let visible = model.history.visible
        return Group {
            if model.history.items.isEmpty {
                Text("Nothing copied yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else if visible.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, clip in
                        if index == 0, clip.pinned {
                            sectionLabel("Pinned")
                        } else if index > 0, !clip.pinned, visible[index - 1].pinned {
                            sectionLabel("History")
                        }
                        row(index: index, clip: clip)
                    }
                }
                .padding(6)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        let visible = model.history.visible
        guard visible.indices.contains(model.history.selection) else { return }
        proxy.scrollTo(visible[model.history.selection].id, anchor: .center)
    }

    private func row(index: Int, clip: Clip) -> some View {
        let selected = index == model.history.selection
        let busy = model.aiBusy && model.aiTarget == clip.id
        return HStack(spacing: 8) {
            Text(index < 9 ? "\(index + 1)" : "")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 12, alignment: .trailing)
            clipLeading(clip)
            Button {
                onPaste(clip, false)
            } label: {
                clipTitle(clip)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if busy {
                ProgressView().controlSize(.small)
            } else if selected {
                rowAction("doc.plaintext", help: "Paste as Plain Text") { onPaste(clip, true) }
                rowAction(clip.pinned ? "pin.fill" : "pin", help: clip.pinned ? "Unpin" : "Pin") { model.togglePin(id: clip.id) }
            } else if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(
            selected ? JeroxInk.accent.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .id(clip.id)
    }

    private func rowAction(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle())
        .help(help)
    }

}

struct BlobThumb: View {
    var clip: Clip
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo")
            }
        }
        .frame(width: 20, height: 20)
        .task(id: clip.id) {
            let dir = ClipboardHistory.blobsURL
            let thumb = dir.appendingPathComponent("\(clip.id.uuidString).thumb.png")
            if let image = NSImage(contentsOf: thumb) {
                self.image = image
                return
            }
            if let ext = clip.blobExt {
                self.image = NSImage(contentsOf: dir.appendingPathComponent("\(clip.id.uuidString).\(ext)"))
            }
        }
    }
}

@ViewBuilder
func clipLeading(_ clip: Clip) -> some View {
    Group {
        switch clip.kind {
        case .image:
            BlobThumb(clip: clip).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .color:
            if let rgba = parseColor(clip.text) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    .padding(3)
            }
        default:
            Image(systemName: kindSymbol(clip.kind))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    .frame(width: 20, height: 20)
}

func kindSymbol(_ kind: ClipKind) -> String {
    switch kind {
    case .text: "text.alignleft"
    case .richText: "textformat"
    case .image: "photo"
    case .file: "doc"
    case .link: "link"
    case .color: "paintpalette"
    case .code: "chevron.left.forwardslash.chevron.right"
    }
}

@ViewBuilder
func clipTitle(_ clip: Clip) -> some View {
    if clip.kind == .code {
        Text(highlightedLine(clip.text)).lineLimit(1)
    } else {
        Text(displayTitle(clip)).lineLimit(1)
    }
}

func displayTitle(_ clip: Clip) -> String {
    switch clip.kind {
    case .image where clip.text.isEmpty:
        return "Image"
    case .file:
        let parts = clip.text.split(separator: "\n").map(String.init)
        let name = URL(fileURLWithPath: parts.first ?? clip.text).lastPathComponent
        let extra = parts.count - 1
        return extra > 0 ? "\(name) +\(extra)" : name
    default:
        return clip.text.replacingOccurrences(of: "\n", with: " ")
    }
}

func highlightedLine(_ text: String) -> AttributedString {
    let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
    var result = AttributedString()
    for token in codeTokens(line) {
        var piece = AttributedString(token.text)
        switch token.kind {
        case .keyword: piece.foregroundColor = .purple
        case .string: piece.foregroundColor = .red
        case .number: piece.foregroundColor = .blue
        case .comment: piece.foregroundColor = .secondary
        case .plain: break
        }
        result += piece
    }
    return result
}
