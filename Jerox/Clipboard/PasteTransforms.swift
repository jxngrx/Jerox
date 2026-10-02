import Foundation

enum CaseMode: String, CaseIterable, Identifiable {
    case off, upper, lower, title
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .upper: "UPPER"
        case .lower: "lower"
        case .title: "Title Case"
        }
    }
}

enum Base64Mode: String, CaseIterable, Identifiable {
    case off, encode, decode
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .encode: "Encode"
        case .decode: "Decode"
        }
    }
}

struct PasteOptions: Equatable {
    var trim = false
    var markdown = false
    var prettyJSON = false
    var caseMode = CaseMode.off
    var base64 = Base64Mode.off

    static func current() -> PasteOptions {
        let defaults = UserDefaults.standard
        return PasteOptions(prettyJSON: defaults.bool(forKey: "prettyJSON"))
    }
}

enum Retention {
    static func limit() -> Int {
        (UserDefaults.standard.object(forKey: "historyLimit") as? Int) ?? ClipboardHistory.defaultLimit
    }

    static func maxAge() -> TimeInterval {
        let days = (UserDefaults.standard.object(forKey: "historyDays") as? Int) ?? 14
        return TimeInterval(max(1, days)) * 24 * 60 * 60
    }
}

func transformPaste(_ text: String, _ options: PasteOptions) -> String {
    var result = text
    if options.trim { result = result.trimmingCharacters(in: .whitespacesAndNewlines) }
    if options.markdown { result = stripMarkdown(result) }
    if options.prettyJSON { result = prettyJSON(result) }
    switch options.caseMode {
    case .off: break
    case .upper: result = result.uppercased()
    case .lower: result = result.lowercased()
    case .title: result = result.capitalized // ponytail: "it's" becomes "It'S"
    }
    switch options.base64 {
    case .off: break
    case .encode: result = Data(result.utf8).base64EncodedString()
    case .decode:
        if let data = Data(base64Encoded: result), let decoded = String(data: data, encoding: .utf8) {
            result = decoded
        }
    }
    return result
}

// ponytail: regex for common markup. A real markdown parser if nested syntax shows up.
func stripMarkdown(_ text: String) -> String {
    var result = text
    let swaps: [(String, String)] = [
        ("!\\[([^\\]]*)\\]\\([^)]*\\)", "$1"),
        ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"),
        ("```[a-zA-Z0-9]*\\n?", ""),
        ("`([^`]+)`", "$1"),
        ("(?m)^#{1,6}\\s+", ""),
        ("(?m)^>\\s?", ""),
        ("(?m)^\\s*[-*+]\\s+", ""),
        ("(\\*\\*|__)(.+?)\\1", "$2"),
        ("(\\*|_)([^\\s*_]+)\\1", "$2"),
    ]
    for (pattern, template) in swaps {
        result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
    return result
}

func prettyJSON(_ text: String) -> String {
    guard let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: pretty, encoding: .utf8) else { return text }
    return string
}

/// Whole clipboard text is a JSON object or array. Nil when it is not, or already pretty.
func carbonModifierMask(command: Bool, option: Bool, control: Bool, shift: Bool) -> UInt32 {
    var mask: UInt32 = 0
    if command { mask |= 1 << 8 }
    if shift { mask |= 1 << 9 }
    if option { mask |= 1 << 11 }
    if control { mask |= 1 << 12 }
    return mask
}
