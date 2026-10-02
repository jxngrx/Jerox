import Foundation

func prettyJSONDocument(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let data = trimmed.data(using: .utf8),
          (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }
    let pretty = prettyJSON(trimmed)
    return pretty == trimmed ? nil : pretty
}

func classifyText(_ text: String) -> ClipKind {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if parseColor(trimmed) != nil { return .color }
    if isLink(trimmed) { return .link }
    if isCode(text) { return .code }
    return .text
}

func canonicalColor(_ text: String) -> String {
    guard let color = parseColor(text) else { return text }
    func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
    if color.a < 0.999 {
        return String(format: "#%02x%02x%02x%02x", byte(color.r), byte(color.g), byte(color.b), byte(color.a))
    }
    return String(format: "#%02x%02x%02x", byte(color.r), byte(color.g), byte(color.b))
}

func parseColor(_ text: String) -> RGBA? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("#") { return parseHex(String(trimmed.dropFirst())) }
    return parseRGBCall(trimmed)
}

// ponytail: fence, shebang, or punctuation ratio. Not a language detector.
func isCode(_ text: String) -> Bool {
    if text.contains("```") { return true }
    let first = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
    if first.hasPrefix("#!") { return true }
    guard text.count >= 16 else { return false }
    let marks = text.filter { "{}[]();=<>".contains($0) }.count
    return marks >= 4 && Double(marks) / Double(text.count) >= 0.06
}

func codeTokens(_ line: String) -> [CodeToken] {
    let keywords: Set<String> = [
        "if", "else", "return", "func", "function", "class", "struct", "let", "var", "const",
        "import", "for", "while", "def", "true", "false", "nil", "null"
    ]
    var tokens: [CodeToken] = []
    var index = line.startIndex
    func push(_ kind: CodeToken.Kind, _ text: String) {
        guard !text.isEmpty else { return }
        if let last = tokens.indices.last, tokens[last].kind == kind {
            tokens[last].text += text
        } else {
            tokens.append(CodeToken(kind: kind, text: text))
        }
    }
    while index < line.endIndex {
        let rest = line[index...]
        if rest.hasPrefix("//") || (rest.hasPrefix("#") && (index == line.startIndex || line[line.index(before: index)].isWhitespace)) {
            push(.comment, String(rest))
            break
        }
        if rest.hasPrefix("/*") {
            if let end = line[index...].range(of: "*/") {
                push(.comment, String(line[index..<end.upperBound]))
                index = end.upperBound
                continue
            }
            push(.comment, String(rest))
            break
        }
        let character = line[index]
        if character == "\"" || character == "'" {
            var next = line.index(after: index)
            while next < line.endIndex {
                if line[next] == "\\" {
                    next = line.index(next, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
                    continue
                }
                if line[next] == character {
                    next = line.index(after: next)
                    break
                }
                next = line.index(after: next)
            }
            push(.string, String(line[index..<next]))
            index = next
            continue
        }
        if character.isNumber {
            var next = index
            while next < line.endIndex, line[next].isNumber || line[next] == "." {
                next = line.index(after: next)
            }
            push(.number, String(line[index..<next]))
            index = next
            continue
        }
        if character.isLetter || character == "_" {
            var next = index
            while next < line.endIndex, line[next].isLetter || line[next].isNumber || line[next] == "_" {
                next = line.index(after: next)
            }
            let word = String(line[index..<next])
            push(keywords.contains(word) ? .keyword : .plain, word)
            index = next
            continue
        }
        push(.plain, String(character))
        index = line.index(after: index)
    }
    return tokens
}

func isLink(_ text: String) -> Bool {
    guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
    if scheme == "mailto" { return text.contains("@") }
    return (scheme == "http" || scheme == "https") && url.host != nil
}

func parseHex(_ digits: String) -> RGBA? {
    let hex = digits.lowercased()
    guard hex.allSatisfy(\.isHexDigit) else { return nil }
    let expanded: String
    switch hex.count {
    case 3, 4: expanded = hex.map { "\($0)\($0)" }.joined()
    case 6, 8: expanded = hex
    default: return nil
    }
    func byte(at offset: Int) -> Double? {
        let start = expanded.index(expanded.startIndex, offsetBy: offset)
        let end = expanded.index(start, offsetBy: 2)
        guard let value = Int(expanded[start..<end], radix: 16) else { return nil }
        return Double(value) / 255
    }
    guard let r = byte(at: 0), let g = byte(at: 2), let b = byte(at: 4) else { return nil }
    let a = expanded.count == 8 ? (byte(at: 6) ?? 1) : 1
    return RGBA(r: r, g: g, b: b, a: a)
}

func parseRGBCall(_ text: String) -> RGBA? {
    let compact = text.lowercased().filter { !$0.isWhitespace }
    let prefix: String
    if compact.hasPrefix("rgba("), compact.hasSuffix(")") { prefix = "rgba(" }
    else if compact.hasPrefix("rgb("), compact.hasSuffix(")") { prefix = "rgb(" }
    else { return nil }
    let inner = compact.dropFirst(prefix.count).dropLast()
    let parts = inner.split(separator: ",").map(String.init)
    guard parts.count == (prefix == "rgb(" ? 3 : 4) else { return nil }
    func channel(_ part: String) -> Double? {
        guard let value = Double(part), value >= 0, value <= 255 else { return nil }
        return value / 255
    }
    guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
    var alpha = 1.0
    if parts.count == 4 {
        guard let value = Double(parts[3]), value >= 0 else { return nil }
        if value > 1 {
            guard value <= 255 else { return nil }
            alpha = value / 255
        } else {
            alpha = value
        }
    }
    return RGBA(r: r, g: g, b: b, a: alpha)
}
