import AppKit
import CoreGraphics
import Foundation

func readPasteboard(_ board: NSPasteboard) -> Captured? {
    if let files = fileURLs(on: board), !files.isEmpty {
        if files.count == 1, let captured = capturedImageFile(files[0]) { return captured }
        let paths = files.map(\.path).joined(separator: "\n")
        let hash = files.map(fileIdentity).joined(separator: "|")
        return Captured(clip: Clip(paths, kind: .file, hash: hash), payload: nil, thumb: nil)
    }
    if let url = webURL(on: board) {
        return Captured(clip: Clip(url.absoluteString, kind: .link), payload: nil, thumb: nil)
    }
    if let color = (board.readObjects(forClasses: [NSColor.self], options: nil) as? [NSColor])?.first {
        return Captured(clip: Clip(hexString(color), kind: .color), payload: nil, thumb: nil)
    }
    if let text = board.string(forType: .string) {
        let kind = classifyText(text)
        if kind == .color || kind == .link {
            let stored = kind == .color ? canonicalColor(text) : text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Captured(clip: Clip(stored, kind: kind), payload: nil, thumb: nil)
        }
    }
    // RTF wins over a TIFF preview. HTML does not, so a copied picture stays an image.
    if let rich = richData(on: board, html: false) {
        return capturedRich(rich, board: board)
    }
    if let image = imageData(on: board) {
        let plain = board.string(forType: .string) ?? ""
        return Captured(
            clip: Clip(plain, kind: .image, blobExt: image.ext, hash: sha256Hex(image.data)),
            payload: image.data,
            thumb: thumbnailPNG(image.data)
        )
    }
    if let rich = richData(on: board, html: true) {
        return capturedRich(rich, board: board)
    }
    guard let text = board.string(forType: .string), !text.isEmpty else { return nil }
    let kind = classifyText(text)
    let stored = kind == .color ? canonicalColor(text) : text
    return Captured(clip: Clip(stored, kind: kind), payload: nil, thumb: nil)
}

func writeOriginal(_ clip: Clip, board: NSPasteboard) {
    switch clip.kind {
    case .image:
        if let data = blobData(clip) {
            let type: NSPasteboard.PasteboardType
            switch clip.blobExt {
            case "tiff": type = .tiff
            case "jpg", "jpeg": type = NSPasteboard.PasteboardType("public.jpeg")
            default: type = .png
            }
            board.declareTypes([type], owner: nil)
            board.setData(data, forType: type)
            return
        }
    case .richText:
        if let data = blobData(clip) {
            let type: NSPasteboard.PasteboardType
            switch clip.blobExt {
            case "html": type = .html
            case "rtfd": type = .rtfd
            default: type = .rtf
            }
            var types: [NSPasteboard.PasteboardType] = [type]
            if !clip.text.isEmpty { types.append(.string) }
            board.declareTypes(types, owner: nil)
            board.setData(data, forType: type)
            if !clip.text.isEmpty { board.setString(clip.text, forType: .string) }
            return
        }
    case .file:
        let urls = clip.text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        if !urls.isEmpty {
            board.writeObjects(urls as [NSURL])
            return
        }
    case .link:
        let item = NSPasteboardItem()
        item.setString(clip.text, forType: .string)
        if URL(string: clip.text) != nil {
            item.setString(clip.text, forType: .URL)
        }
        board.writeObjects([item])
        return
    case .color:
        if let rgba = parseColor(clip.text) {
            let color = NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
            let item = NSPasteboardItem()
            item.setString(clip.text, forType: .string)
            if let list = color.pasteboardPropertyList(forType: .color) {
                item.setPropertyList(list, forType: .color)
            }
            board.writeObjects([item])
            return
        }
    case .text, .code:
        break
    }
    if !clip.text.isEmpty { board.setString(clip.text, forType: .string) }
}

func webURL(on board: NSPasteboard) -> URL? {
    let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    return urls?.first { url in
        guard !url.isFileURL, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }
}

// ponytail: image files over 8MB stay as paths. The bytes are what still paste after the file moves.
func capturedImageFile(_ url: URL) -> Captured? {
    let ext = url.pathExtension.lowercased()
    guard ["png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "webp", "bmp"].contains(ext) else { return nil }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    if size > 8 * 1024 * 1024 { return nil }
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    let stored: (Data, String)
    switch ext {
    case "png": stored = (data, "png")
    case "tif", "tiff": stored = (data, "tiff")
    case "jpg", "jpeg": stored = (data, "jpg")
    default:
        guard let png = pngBytes(data) else { return nil }
        stored = (png, "png")
    }
    return Captured(
        clip: Clip(url.lastPathComponent, kind: .image, blobExt: stored.1, hash: sha256Hex(stored.0)),
        payload: stored.0,
        thumb: thumbnailPNG(stored.0)
    )
}

func fileURLs(on board: NSPasteboard) -> [URL]? {
    board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
}

func imageData(on board: NSPasteboard) -> (data: Data, ext: String)? {
    if let data = board.data(forType: .png), !data.isEmpty { return (data, "png") }
    if let data = board.data(forType: .tiff), !data.isEmpty { return (data, "tiff") }
    return nil
}

func richData(on board: NSPasteboard, html: Bool) -> (data: Data, ext: String)? {
    if !html {
        if let data = board.data(forType: .rtf), !data.isEmpty { return (data, "rtf") }
        if let data = board.data(forType: .rtfd), !data.isEmpty { return (data, "rtfd") }
        return nil
    }
    if let data = board.data(forType: .html), !data.isEmpty { return (data, "html") }
    return nil
}

func capturedRich(_ rich: (data: Data, ext: String), board: NSPasteboard) -> Captured? {
    let plain = board.string(forType: .string) ?? plainString(rich: rich.data, ext: rich.ext)
    guard !plain.isEmpty else { return nil }
    return Captured(clip: Clip(plain, kind: .richText, blobExt: rich.ext), payload: rich.data, thumb: nil)
}

func plainString(rich data: Data, ext: String) -> String {
    if ext == "html", let html = String(data: data, encoding: .utf8) {
        // ponytail: tag strip for the preview line. The blob is what pastes.
        return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string, !text.isEmpty {
        return text
    }
    return ""
}

func hexString(_ color: NSColor) -> String {
    let converted = color.usingColorSpace(.sRGB) ?? color
    func byte(_ value: CGFloat) -> Int { Int((value * 255).rounded()) }
    let hex = String(
        format: "#%02x%02x%02x%02x",
        byte(converted.redComponent),
        byte(converted.greenComponent),
        byte(converted.blueComponent),
        byte(converted.alphaComponent)
    )
    return canonicalColor(hex)
}

func pngBytes(_ data: Data) -> Data? {
    guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
    return thumbnailPNG(data, maxSide: min(2048, max(image.size.width, image.size.height)))
}

func thumbnailPNG(_ data: Data, maxSide limit: CGFloat = 64) -> Data? {
    guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
    let maxSide = limit
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let newSize = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(newSize.width),
        pixelsHigh: Int(newSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: newSize))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}
