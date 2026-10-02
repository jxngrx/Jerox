import CoreGraphics
import Foundation

func ocrReadingOrder(_ lines: [(text: String, y: CGFloat, x: CGFloat)]) -> String {
    lines.sorted { a, b in
        if abs(a.y - b.y) > 0.02 { return a.y > b.y }
        return a.x < b.x
    }.map(\.text).joined(separator: "\n")
}

func ocrCaptionFrame(anchor: CGRect, screen: CGRect, text: String) -> CGRect {
    // ponytail: line count from character width, cap 5. Measure the string if captions clip.
    let room = max(40, screen.width - 16)
    let width = min(360, room, max(140, anchor.width))
    let per = max(12, Int(width / 7.2))
    let lines = min(5, max(1, (max(text.count, 1) + per - 1) / per))
    let height = CGFloat(lines) * 18 + 14
    let minX = screen.minX + 8
    let maxX = max(minX, screen.maxX - width - 8)
    let x = min(max(anchor.midX - width / 2, minX), maxX)
    var y = anchor.maxY + 6
    if y + height > screen.maxY - 8 { y = anchor.maxY - height }
    if y < screen.minY + 8 { y = screen.minY + 8 }
    return CGRect(x: x, y: y, width: width, height: height)
}
