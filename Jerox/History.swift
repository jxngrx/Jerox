import Foundation
import CoreGraphics

enum ClipKind: String, Codable, CaseIterable {
    case text
    case richText
    case image
    case file
    case link
    case color
    case code
}

enum TypeFilter: String, CaseIterable, Identifiable {
    case all, text, richText, image, file, link, color, code

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .richText: "Rich Text"
        case .image: "Image"
        case .file: "File"
        case .link: "Link"
        case .color: "Color"
        case .code: "Code"
        }
    }

    var kind: ClipKind? { ClipKind(rawValue: rawValue) }
}

struct RGBA: Equatable {
    var r, g, b, a: Double
}

struct CodeToken: Equatable {
    enum Kind: Equatable { case plain, keyword, string, number, comment }
    var kind: Kind
    var text: String
}

struct Clip: Identifiable, Equatable, Codable {
    var id: UUID
    var text: String
    var kind: ClipKind
    var pinned: Bool
    var copiedAt: Date
    var blobExt: String?
    var hash: String?

    init(
        _ text: String,
        kind: ClipKind = .text,
        pinned: Bool = false,
        copiedAt: Date = Date(),
        id: UUID = UUID(),
        blobExt: String? = nil,
        hash: String? = nil
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.pinned = pinned
        self.copiedAt = copiedAt
        self.blobExt = blobExt
        self.hash = hash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        kind = try container.decodeIfPresent(ClipKind.self, forKey: .kind) ?? .text
        pinned = try container.decode(Bool.self, forKey: .pinned)
        copiedAt = try container.decode(Date.self, forKey: .copiedAt)
        blobExt = try container.decodeIfPresent(String.self, forKey: .blobExt)
        hash = try container.decodeIfPresent(String.self, forKey: .hash)
    }

    var identity: String {
        switch kind {
        case .image, .file:
            return "\(kind.rawValue):\(hash ?? text)"
        default:
            return "\(kind.rawValue):\(text)"
        }
    }

    func matches(_ other: Clip) -> Bool {
        switch kind {
        case .image, .file:
            guard kind == other.kind, let hash, !hash.isEmpty else { return false }
            return hash == other.hash
        case .richText:
            return other.kind == .richText && text == other.text
        default:
            return kind == other.kind && !text.isEmpty && text == other.text
        }
    }
}

struct ClipboardHistory {
    private(set) var items: [Clip]
    private(set) var query = ""
    private(set) var typeFilter = TypeFilter.all
    private(set) var selection = 0
    var limit: Int
    var maxAge: TimeInterval

    static let defaultLimit = 200
    static let defaultMaxAge: TimeInterval = 14 * 24 * 60 * 60

    static var fileURL: URL {
        supportURL.appendingPathComponent("history.json")
    }

    static var blobsURL: URL {
        supportURL.appendingPathComponent("blobs", isDirectory: true)
    }

    static var supportURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jerox", isDirectory: true)
    }

    init(
        items: [Clip] = [],
        limit: Int = ClipboardHistory.defaultLimit,
        maxAge: TimeInterval = ClipboardHistory.defaultMaxAge
    ) {
        self.items = items
        self.limit = limit
        self.maxAge = maxAge
    }

    mutating func add(_ text: String, now: Date = Date()) {
        let kind = classifyText(text)
        let stored: String
        switch kind {
        case .color: stored = canonicalColor(text)
        case .link: stored = text.trimmingCharacters(in: .whitespacesAndNewlines)
        default: stored = text
        }
        guard !stored.isEmpty else { return }
        _ = add(Clip(stored, kind: kind), now: now)
    }

    @discardableResult
    mutating func add(_ incoming: Clip, now: Date = Date()) -> (saved: Clip, removed: [Clip]) {
        guard !incoming.text.isEmpty || incoming.kind == .image else {
            return (incoming, [])
        }
        if let index = items.firstIndex(where: { $0.matches(incoming) }) {
            var clip = items.remove(at: index)
            clip.copiedAt = now
            clip.text = incoming.text
            clip.kind = incoming.kind
            clip.blobExt = incoming.blobExt
            clip.hash = incoming.hash
            if clip.pinned {
                items.insert(clip, at: 0)
            } else {
                insertUnpinned(clip)
            }
            let removed = expire(now: now)
            selection = 0
            let saved = items.first { $0.id == clip.id } ?? clip
            return (saved, removed)
        }
        var clip = incoming
        clip.copiedAt = now
        if clip.pinned {
            items.insert(clip, at: 0)
        } else {
            insertUnpinned(clip)
        }
        let removed = expire(now: now)
        selection = 0
        return (clip, removed)
    }

    @discardableResult
    mutating func replaceText(id: UUID, text: String, now: Date = Date()) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), !text.isEmpty else { return false }
        items[index].text = text
        items[index].kind = classifyText(text)
        items[index].copiedAt = now
        return true
    }

    @discardableResult
    mutating func togglePin(id: UUID, now: Date = Date()) -> [Clip] {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return [] }
        var clip = items.remove(at: index)
        clip.pinned.toggle()
        if clip.pinned {
            items.insert(clip, at: 0)
        } else {
            insertUnpinned(clip)
        }
        let removed = expire(now: now)
        if let visibleIndex = visible.firstIndex(where: { $0.id == id }) {
            selection = visibleIndex
        } else {
            selection = 0
        }
        return removed
    }

    mutating func setQuery(_ query: String) {
        self.query = query
        selection = 0
    }

    mutating func setTypeFilter(_ filter: TypeFilter) {
        typeFilter = filter
        selection = 0
    }

    mutating func moveSelection(_ delta: Int) {
        let count = visible.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    @discardableResult
    mutating func expire(now: Date = Date()) -> [Clip] {
        let prior = items
        let cutoff = now.addingTimeInterval(-maxAge)
        items.removeAll { !$0.pinned && $0.copiedAt < cutoff }
        let pins = items.filter(\.pinned)
        var rest = items.filter { !$0.pinned }
        if rest.count > limit {
            rest.removeLast(rest.count - limit)
        }
        items = pins + rest
        let count = visible.count
        if count == 0 {
            selection = 0
        } else if selection >= count {
            selection = count - 1
        }
        let kept = Set(items.map(\.id))
        return prior.filter { !kept.contains($0.id) }
    }

    var visible: [Clip] {
        let matched = items.filter(includes)
        let pins = matched.filter(\.pinned)
        let rest = matched.filter { !$0.pinned }
        if query.isEmpty { return pins + rest }
        return ranked(pins) + ranked(rest)
    }

    func clip(number: Int) -> Clip? {
        let rows = visible
        guard (1...9).contains(number), rows.indices.contains(number - 1) else { return nil }
        return rows[number - 1]
    }

    func item(number: Int) -> String? { clip(number: number)?.text }

    var selectedClip: Clip? {
        let rows = visible
        guard rows.indices.contains(selection) else { return nil }
        return rows[selection]
    }

    var selectedText: String? { selectedClip?.text }
    var selectedID: UUID? { selectedClip?.id }

    func save() throws {
        let url = Self.fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    static func load(
        now: Date = Date(),
        limit: Int = ClipboardHistory.defaultLimit,
        maxAge: TimeInterval = ClipboardHistory.defaultMaxAge
    ) -> (ClipboardHistory, removed: [Clip]) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return (ClipboardHistory(limit: limit, maxAge: maxAge), [])
        }
        return from(data: try? Data(contentsOf: fileURL), now: now, limit: limit, maxAge: maxAge)
    }

    @discardableResult
    mutating func setRetention(limit: Int, maxAge: TimeInterval, now: Date = Date()) -> [Clip] {
        self.limit = max(1, limit)
        self.maxAge = max(1, maxAge)
        return expire(now: now)
    }

    static func from(
        data: Data?,
        now: Date = Date(),
        limit: Int = ClipboardHistory.defaultLimit,
        maxAge: TimeInterval = ClipboardHistory.defaultMaxAge
    ) -> (ClipboardHistory, removed: [Clip]) {
        guard let data, let decoded = try? JSONDecoder().decode([Clip].self, from: data) else {
            return (ClipboardHistory(limit: limit, maxAge: maxAge), [])
        }
        var history = ClipboardHistory(items: decoded, limit: limit, maxAge: maxAge)
        let removed = history.expire(now: now)
        return (history, removed)
    }

    private mutating func insertUnpinned(_ clip: Clip) {
        let at = items.firstIndex(where: { !$0.pinned }) ?? items.count
        items.insert(clip, at: at)
    }

    private func includes(_ clip: Clip) -> Bool {
        if let kind = typeFilter.kind, clip.kind != kind { return false }
        return matchRank(clip.text) != nil
    }

    private func ranked(_ clips: [Clip]) -> [Clip] {
        let substring = clips.filter { matchRank($0.text) == .substring }
        let subsequence = clips.filter { matchRank($0.text) == .subsequence }
        return substring + subsequence
    }

    private enum Rank { case substring, subsequence }

    private func matchRank(_ text: String) -> Rank? {
        if query.isEmpty { return .substring }
        let hay = text.lowercased()
        let needle = query.lowercased()
        if hay.contains(needle) { return .substring }
        var index = hay.startIndex
        for character in needle {
            guard let found = hay[index...].firstIndex(of: character) else { return nil }
            index = hay.index(after: found)
        }
        return .subsequence
    }

    static func selfCheck() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 24 * 60 * 60

        var empty = ClipboardHistory(limit: 5, maxAge: 100 * day)
        empty.add("", now: start)
        req(empty.items.isEmpty, "ignore empty")
        empty.moveSelection(1)
        req(empty.selection == 0 && empty.selectedText == nil, "empty selection")

        var dupes = ClipboardHistory(limit: 10, maxAge: 100 * day)
        dupes.add("a", now: start)
        dupes.add("b", now: start + 1)
        dupes.add("a", now: start + 2)
        req(dupes.items.map(\.text) == ["a", "b"], "duplicate moves to top")
        req(dupes.items[0].copiedAt == start + 2, "duplicate refreshes time")
        req(dupes.items.filter { $0.text == "a" }.count == 1, "one row")

        var pinnedDupe = ClipboardHistory(limit: 10, maxAge: 100 * day)
        pinnedDupe.add("a", now: start)
        pinnedDupe.add("b", now: start + 1)
        pinnedDupe.togglePin(id: pinnedDupe.items[1].id, now: start + 1)
        pinnedDupe.add("a", now: start + 2)
        req(pinnedDupe.items[0].text == "a" && pinnedDupe.items[0].pinned, "pinned duplicate stays at top of pins")
        req(pinnedDupe.items.map(\.text) == ["a", "b"], "pinned duplicate does not clone")

        var capped = ClipboardHistory(limit: 2, maxAge: 100 * day)
        capped.add("a", now: start)
        capped.togglePin(id: capped.items[0].id, now: start)
        capped.add("b", now: start + 1)
        capped.add("c", now: start + 2)
        capped.add("d", now: start + 3)
        req(capped.items.map(\.text) == ["a", "d", "c"], "pin exempt from cap")
        req(capped.selection == 0, "newest selected")
        capped.moveSelection(1)
        capped.moveSelection(5)
        req(capped.selection == capped.visible.count - 1, "clamp end")
        capped.moveSelection(-10)
        req(capped.selection == 0, "clamp start")

        var aged = ClipboardHistory(limit: 10, maxAge: 14 * day)
        aged.add("old", now: start)
        aged.add("fresh", now: start + 15 * day)
        req(aged.items.map(\.text) == ["fresh"], "age drops unpinned")
        aged.add("kept", now: start)
        aged.togglePin(id: aged.items[0].id, now: start)
        aged.add("later", now: start + 15 * day)
        req(aged.items.contains { $0.text == "kept" && $0.pinned }, "pin skips age purge")
        let keptID = aged.items[0].id
        aged.togglePin(id: keptID, now: start + 15 * day)
        req(!aged.items.contains { $0.id == keptID }, "unpin of an expired row drops it")

        var found = ClipboardHistory(limit: 10, maxAge: 100 * day)
        found.add("zzz", now: start)
        found.add("h e l", now: start + 1)
        found.add("hello", now: start + 2)
        found.setQuery("HeL")
        req(found.visible.map(\.text) == ["hello", "h e l"], "substring ranks above subsequence")
        found.setQuery("")
        found.togglePin(id: found.items.first { $0.text == "h e l" }!.id, now: start + 3)
        found.setQuery("hel")
        req(found.visible.map(\.text) == ["h e l", "hello"], "pins stay above history")
        req(found.item(number: 1) == "h e l", "number 1 is first visible")
        found.setQuery("zzz")
        found.moveSelection(1)
        req(found.selection == 0 && found.item(number: 1) == "zzz", "search clamps numbers")
        found.setQuery("")
        found.setTypeFilter(.text)
        req(found.visible.map(\.id) == found.items.map(\.id), "text filter keeps text rows")

        var numbered = ClipboardHistory(limit: 20, maxAge: 100 * day)
        for i in 1...10 { numbered.add("\(i)", now: start + Double(i)) }
        req(numbered.item(number: 1) == "10", "newest is 1")
        req(numbered.item(number: 9) == "2", "ninth row")
        req(numbered.items.count == 10, "tenth row kept")
        req(numbered.item(number: 10) == nil, "no key for 10")

        let encoded = try? JSONEncoder().encode(numbered.items)
        let decoded = encoded.flatMap { try? JSONDecoder().decode([Clip].self, from: $0) }
        req(decoded?.map(\.id) == numbered.items.map(\.id), "ids survive json")
        req(decoded?.map(\.text) == numbered.items.map(\.text), "text survives json")
        req(decoded?.map(\.pinned) == numbered.items.map(\.pinned), "pins survive json")

        let (broken, removedBroken) = ClipboardHistory.from(data: Data("nope".utf8), now: start)
        req(broken.items.isEmpty && removedBroken.isEmpty, "corrupt json is not overwritten")
        let stale = try? JSONEncoder().encode([Clip("old", copiedAt: start)])
        let (expired, removedExpired) = ClipboardHistory.from(
            data: stale,
            now: start + 15 * day,
            maxAge: 14 * day
        )
        req(expired.items.isEmpty && removedExpired.count == 1, "load expires old rows")

        req(classifyText("#fff") == .color, "hex color")
        req(classifyText("rgb(1, 2, 3)") == .color, "rgb color")
        req(classifyText("see #fff") == .text, "hex inside prose")
        req(canonicalColor("#fff") == "#ffffff", "short hex expands")
        req(parseColor("#fff") == RGBA(r: 1, g: 1, b: 1, a: 1), "white")
        req(classifyText("https://jxngrx.com/a") == .link, "link")
        req(classifyText("#!/bin/sh\necho hi") == .code, "shebang")
        req(classifyText("```\nlet x = 1\n```") == .code, "fence")
        req(classifyText("func f() {\n  return x;\n}\nlet y = 1;") == .code, "punctuation ratio")
        req(classifyText("hello world") == .text, "prose")
        let tokens = codeTokens("let x = \"hi\" // note")
        req(tokens.contains { $0.kind == .keyword && $0.text == "let" }, "keyword")
        req(tokens.contains { $0.kind == .string && $0.text == "\"hi\"" }, "string")
        req(tokens.contains { $0.kind == .comment }, "comment")

        var kinds = ClipboardHistory(limit: 10, maxAge: 100 * day)
        kinds.add("#AaBbCc", now: start)
        kinds.add("#aabbcc", now: start + 1)
        req(kinds.items.count == 1 && kinds.items[0].kind == .color, "color duplicates collapse")
        let imageA = Clip("", kind: .image, copiedAt: start, blobExt: "png", hash: "abc")
        let imageB = Clip("shot", kind: .image, copiedAt: start + 1, blobExt: "png", hash: "abc")
        let (_, removedImages) = kinds.add(imageA, now: start)
        _ = removedImages
        let (savedImage, _) = kinds.add(imageB, now: start + 1)
        req(kinds.items.filter { $0.kind == .image }.count == 1, "image hash duplicate")
        req(savedImage.id == imageA.id && savedImage.text == "shot", "image duplicate keeps id")
        let rich = Clip("hello", kind: .richText, copiedAt: start, blobExt: "rtf")
        kinds.add(rich, now: start)
        kinds.togglePin(id: rich.id, now: start)
        kinds.add(Clip("hello", kind: .richText, blobExt: "rtf"), now: start + 2)
        req(kinds.items.contains { $0.kind == .richText && $0.pinned && $0.text == "hello" }, "rich text matches plain string")
        kinds.setTypeFilter(.image)
        req(kinds.visible.allSatisfy { $0.kind == .image }, "image filter")
        kinds.setTypeFilter(.text)
        req(kinds.visible.isEmpty, "text filter hides other kinds")

        if let data = try? JSONEncoder().encode([Clip("legacy", copiedAt: start)]),
           var rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            rows[0].removeValue(forKey: "kind")
            rows[0].removeValue(forKey: "blobExt")
            rows[0].removeValue(forKey: "hash")
            let legacy = try? JSONSerialization.data(withJSONObject: rows)
            let decodedLegacy = legacy.flatMap { try? JSONDecoder().decode([Clip].self, from: $0) }
            req(decodedLegacy?.first?.kind == .text && decodedLegacy?.first?.text == "legacy", "old rows stay text")
        } else {
            req(false, "legacy json")
        }

        var options = PasteOptions(trim: true)
        req(transformPaste("  hi \n", options) == "hi", "trim edges")
        options = PasteOptions(markdown: true)
        req(transformPaste("# Hi\n**x** and [n](http://x.com)", options) == "Hi\nx and n", "strip markdown")
        options = PasteOptions(prettyJSON: true)
        req(transformPaste("{not json", options) == "{not json", "invalid json stays")
        let pretty = transformPaste("{\"b\":1,\"a\":2}", options)
        req(pretty != "{\"b\":1,\"a\":2}" && pretty.contains("\n") && pretty.contains("\"a\""), "json pretty")
        options = PasteOptions(caseMode: .upper)
        req(transformPaste("Ab", options) == "AB", "upper")
        options = PasteOptions(caseMode: .lower)
        req(transformPaste("Ab", options) == "ab", "lower")
        options = PasteOptions(caseMode: .title)
        req(transformPaste("hello world", options) == "Hello World", "title")
        options = PasteOptions(base64: .encode)
        req(transformPaste("hi", options) == Data("hi".utf8).base64EncodedString(), "base64 encode")
        options = PasteOptions(base64: .decode)
        req(transformPaste("not base64 !!!", options) == "not base64 !!!", "bad base64 stays")
        req(transformPaste(Data("hi".utf8).base64EncodedString(), options) == "hi", "base64 decode")
        options = PasteOptions(trim: true, caseMode: .upper, base64: .encode)
        req(transformPaste("  ab  ", options) == Data("AB".utf8).base64EncodedString(), "trim then case then base64")
        req(isScreenshotFile("Screenshot 2026-09-27 at 10.36.00 PM.png"), "screenshot png")
        req(isScreenshotFile("Screen Shot 2020-01-01 at 1.02.03 AM.tiff"), "old screenshot name")
        req(!isScreenshotFile("notes.png") && !isScreenshotFile("Screenshot.txt"), "not a screenshot")
        let prettyDoc = prettyJSONDocument("{\"b\":1,\"a\":2}")
        req(prettyDoc?.contains("\n") == true, "json document")
        req(prettyJSONDocument(prettyDoc ?? "") == nil, "pretty json stays")
        req(prettyJSONDocument("nope") == nil && prettyJSONDocument("true") == nil, "not a json document")
        req(prettyJSONDocument("see {\"a\":1}") == nil, "json inside text stays")
        req(carbonModifierMask(command: true, option: true, control: true, shift: false) == 6400, "shortcut modifiers")
        let payload = aiCall(service: "openrouter", model: "m", key: "k", instruction: "Clean", text: "Hello")
        let sent = (try? JSONSerialization.jsonObject(with: payload?.body ?? Data())) as? [String: Any]
        let messages = sent?["messages"] as? [[String: Any]]
        req(payload?.url.contains("openrouter.ai") == true && sent?["provider"] != nil && sent?["model"] as? String == "m" && messages?.first?["content"] as? String == "Clean" && messages?.last?["content"] as? String == "Hello", "router payload")
        let openai = aiCall(service: "openai", model: "", key: "k", instruction: "Clean", text: "Hello")
        let openaiBody = (try? JSONSerialization.jsonObject(with: openai?.body ?? Data())) as? [String: Any]
        req(openai?.url.contains("api.openai.com") == true && openaiBody?["provider"] == nil && openaiBody?["model"] as? String == "gpt-4o-mini", "openai")
        let hugging = aiCall(service: "huggingface", model: "org/m", key: "k", instruction: "Clean", text: "Hi")
        req(hugging?.url.contains("router.huggingface.co") == true, "huggingface")
        let anthropic = aiCall(service: "anthropic", model: "claude", key: "secret", instruction: "Clean", text: "Hi")
        let anthropicBody = (try? JSONSerialization.jsonObject(with: anthropic?.body ?? Data())) as? [String: Any]
        req(anthropic?.url.contains("api.anthropic.com") == true && anthropic?.headers["x-api-key"] == "secret" && anthropicBody?["system"] as? String == "Clean", "anthropic")
        req(aiReply(service: "openai", data: Data("{\"choices\":[{\"message\":{\"content\":\" OK \"}}]}".utf8)) == "OK", "chat reply")
        req(aiReply(service: "anthropic", data: Data("{\"content\":[{\"text\":\" Hi \"}]}".utf8)) == "Hi", "anthropic reply")
        req(aiCall(service: "apple", model: "", key: "", instruction: "Clean", text: "Hi") == nil, "apple is local")
        let quiet = waveBars(Array(repeating: 0, count: 10), count: 5)
        let loud = waveBars(Array(repeating: 0.4, count: 10), count: 5)
        req(quiet.allSatisfy { $0 == 0 } && loud.allSatisfy { $0 > 0.5 }, "wave bars")
        req(stripDictationFillers("uh I um went ah home") == "I went home", "drop fillers")
        let grew = dictateUpdate(locked: "", tentative: "I went", latest: "I went home", final: false)
        req(grew.shown == "I went home" && grew.locked == "" && grew.tentative == "I went home", "dictation grows")
        var paused = dictateUpdate(locked: "", tentative: "", latest: "I went home", final: false)
        paused = dictateUpdate(locked: paused.locked, tentative: paused.tentative, latest: "then I slept", final: false)
        req(paused.shown == "I went home then I slept", "dictation keeps history")
        let echo = dictateUpdate(locked: "I went home", tentative: "", latest: "I went", final: false)
        req(echo.shown == "I went home", "short partial does not erase")
        let overlap = dictateUpdate(locked: "I went home", tentative: "", latest: "home and slept", final: false)
        req(overlap.shown == "I went home and slept", "overlap does not repeat")
        let punct = dictateUpdate(locked: "I went home", tentative: "", latest: "I went home.", final: false)
        req(punct.shown == "I went home.", "punctuation revision replaces")
        let held = dictateUpdate(locked: "I went home", tentative: "", latest: "", final: true)
        req(held.shown == "I went home" && held.locked == "I went home", "empty final keeps the paragraph")
        var replay = dictateUpdate(locked: "", tentative: "", latest: "I went home", final: true)
        replay = dictateUpdate(locked: replay.locked, tentative: replay.tentative, latest: "I went home", final: false)
        replay = dictateUpdate(locked: replay.locked, tentative: replay.tentative, latest: "I went home", final: false)
        req(replay.shown == "I went home", "replay does not repeat")
        var revised = dictateUpdate(locked: "", tentative: "", latest: "I went to the store", final: false)
        revised = dictateUpdate(locked: revised.locked, tentative: revised.tentative, latest: "I went to the shop", final: false)
        req(revised.shown == "I went to the shop", "revision replaces")
        var notes = rememberDictation(" Hello ", notes: [])
        notes = rememberDictation("Next", notes: notes)
        req(notes.map(\.text) == ["Next", "Hello"], "newest note first")
        for i in 0..<60 { notes = rememberDictation("n\(i)", notes: notes) }
        req(notes.count == 50 && notes.first?.text == "n59" && notes.last?.text == "n10", "notes cap")
        let quietBox = dictateBox(text: "")
        let oneLine = dictateBox(text: "Hello")
        let many = dictateBox(text: String(repeating: "word ", count: 80))
        req(quietBox.height == 40 && oneLine.height > quietBox.height && oneLine.height < many.height && many.height == dictateBox(text: String(repeating: "x", count: 400)).height, "dictation box grows to a cap")
        req(ocrReadingOrder([("bottom", 0.1, 0), ("top", 0.9, 0), ("top right", 0.9, 0.5)]) == "top\ntop right\nbottom", "ocr reading order")
        req(spokenList("I went home then I slept") == "I went home then I slept", "prose stays prose")
        req(spokenList("First tomatoes second potatoes third milk") == "1. tomatoes\n2. potatoes\n3. milk", "ordinal list")
        req(spokenList("So, here's my grocery list. First, I need a tomato, then a potato, ladyfingers, and Amit.") == "So, here's my grocery list.\n1. I need a tomato\n2. a potato\n3. ladyfingers\n4. Amit", "spoken grocery list")
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let above = ocrCaptionFrame(anchor: CGRect(x: 100, y: 100, width: 200, height: 80), screen: screen, text: "Hello")
        req(above.minY == 186 && above.minX == 100, "caption sits above the selection")
        let top = ocrCaptionFrame(anchor: CGRect(x: 100, y: 760, width: 200, height: 30), screen: screen, text: "Hello")
        req(top.maxY <= screen.maxY && top.minY >= screen.minY, "caption stays on screen")
        let custom = [RephrasePrompt(id: "x", name: "Hindi", instruction: "लिखो")]
        let list = rephrasePromptList(custom: custom)
        req(list.count == 4 && list[0].id == "friendly" && list[3].id == "x", "custom prompt appends")
        req(rephrasePrompt(number: 1, in: list)?.id == "friendly", "prompt 1")
        req(rephrasePrompt(number: 4, in: list)?.id == "x", "prompt 4")
        req(rephrasePrompt(number: 5, in: list) == nil && rephrasePrompt(number: 0, in: list) == nil, "prompt number bounds")
        req(rephrasePromptList(custom: [RephrasePrompt(id: "b", name: " ", instruction: "x")]).count == 3, "blank prompt dropped")
        req(decodeRephrasePrompts(Data("nope".utf8)).isEmpty, "bad prompt json")
    }
}

// ponytail: English screenshot names only. Match kMDItemIsScreenCapture if a locale uses another prefix.
func isScreenshotFile(_ name: String) -> Bool {
    let base = (name as NSString).lastPathComponent.lowercased()
    let ext = (base as NSString).pathExtension
    guard ext == "png" || ext == "tiff" || ext == "tif" else { return false }
    return base.hasPrefix("screenshot") || base.hasPrefix("screen shot")
}

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

struct RephrasePrompt: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var instruction: String
}

private let rephraseHuman = " Write it the way a person would. No em dashes, en dashes, or AI phrasing. If they listed items, keep a numbered list. Output only the rewritten text."

let builtInRephrasePrompts: [RephrasePrompt] = [
    RephrasePrompt(id: "friendly", name: "Friendly chat", instruction: "Rewrite the user's text in a warm, informal tone." + rephraseHuman),
    RephrasePrompt(id: "professional", name: "Professional chat", instruction: "Rewrite the user's text in a clear, professional tone." + rephraseHuman),
    RephrasePrompt(id: "mail", name: "Professional mail", instruction: "Rewrite the user's text as a professional email." + rephraseHuman),
]

func decodeRephrasePrompts(_ data: Data) -> [RephrasePrompt] {
    guard let prompts = try? JSONDecoder().decode([RephrasePrompt].self, from: data) else { return [] }
    return prompts.filter(rephrasePromptIsUsable)
}

func rephrasePromptList(custom: [RephrasePrompt]) -> [RephrasePrompt] {
    builtInRephrasePrompts + custom.filter(rephrasePromptIsUsable)
}

func rephrasePrompt(number: Int, in prompts: [RephrasePrompt]) -> RephrasePrompt? {
    guard (1...9).contains(number), prompts.indices.contains(number - 1) else { return nil }
    return prompts[number - 1]
}

private func rephrasePromptIsUsable(_ prompt: RephrasePrompt) -> Bool {
    !prompt.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !prompt.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

enum RephrasePromptStore {
    private static let key = "rephrasePrompts"

    static func load() -> [RephrasePrompt] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return decodeRephrasePrompts(data)
    }

    static func save(_ prompts: [RephrasePrompt]) {
        let clean = prompts.filter(rephrasePromptIsUsable)
        guard let data = try? JSONEncoder().encode(clean) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum AIService: String, CaseIterable {
    case openrouter, openai, anthropic, huggingface, apple

    var title: String {
        switch self {
        case .openrouter: "OpenRouter"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .huggingface: "Hugging Face"
        case .apple: "Apple Intelligence"
        }
    }

    var defaultModel: String {
        switch self {
        case .openrouter: "openai/gpt-4o-mini"
        case .openai: "gpt-4o-mini"
        case .anthropic: "claude-3-5-haiku-20241022"
        case .huggingface: "meta-llama/Llama-3.2-3B-Instruct"
        case .apple: "On this Mac"
        }
    }
}

func stripDictationFillers(_ text: String) -> String {
    let fillers: Set = ["uh", "um", "ah", "er", "hmm", "mm", "uhm", "uhh", "ahh", "umm", "eh"]
    return text.split(separator: " ").map(String.init).filter { word in
        let bare = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
        return !fillers.contains(bare)
    }.joined(separator: " ")
}

private let ordinalWords = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]

func spokenList(_ text: String) -> String {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return text }
    let words = text.split(separator: " ").map(String.init)
    let hits = words.indices.filter { ordinalWords.contains(bareWord(words[$0])) }
    if hits.count >= 2 {
        let preface = words[..<hits[0]].joined(separator: " ")
        var items: [String] = []
        for (index, hit) in hits.enumerated() {
            let end = index + 1 < hits.count ? hits[index + 1] : words.count
            items.append(contentsOf: listPieces(words[(hit + 1)..<end].joined(separator: " ")))
        }
        return renderList(preface: preface, items: items) ?? text
    }
    guard text.lowercased().contains("list"),
          let start = words.firstIndex(where: { bareWord($0) == "first" }) else { return text }
    let preface = words[..<start].joined(separator: " ")
    let tail = words[(start + 1)...].joined(separator: " ")
    return renderList(preface: preface, items: listPieces(tail)) ?? text
}

private func bareWord(_ word: String) -> String {
    word.trimmingCharacters(in: .punctuationCharacters).lowercased()
}

private func listPieces(_ text: String) -> [String] {
    // ponytail: splits on commas, "then", and "and". "mac and cheese" becomes two items.
    var parts = [text]
    for separator in [",", " then ", " and "] {
        parts = parts.flatMap { $0.components(separatedBy: separator) }
    }
    return parts.compactMap { piece in
        var item = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["then ", "and "] where item.lowercased().hasPrefix(prefix) {
            item = String(item.dropFirst(prefix.count))
        }
        item = item.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return item.isEmpty ? nil : item
    }
}

private func renderList(preface: String, items: [String]) -> String? {
    guard items.count >= 2 else { return nil }
    let lines = items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    let head = preface.trimmingCharacters(in: .whitespacesAndNewlines)
    return head.isEmpty ? lines : head + "\n" + lines
}

func dictateUpdate(locked: String, tentative: String, latest: String, final: Bool) -> (locked: String, tentative: String, shown: String) {
    func keys(_ text: String) -> [String] {
        text.split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
    }
    func fresh(_ base: String, _ extra: String) -> String {
        if extra.isEmpty { return base }
        if base.isEmpty { return extra }
        let old = keys(base)
        let new = keys(extra)
        if old == new { return extra }
        if old.starts(with: new) { return base }
        if new.starts(with: old) { return extra }
        let cap = min(old.count, new.count)
        guard cap > 0 else { return base + " " + extra }
        for count in stride(from: cap, through: 1, by: -1) where old.suffix(count).elementsEqual(new.prefix(count)) {
            let tail = extra.split(separator: " ").dropFirst(count).joined(separator: " ")
            return tail.isEmpty ? base : base + " " + tail
        }
        // ponytail: replayed phrase already in the paragraph. O(n*m) over one utterance.
        if old.count >= new.count {
            for start in 0...(old.count - new.count) where old[start..<(start + new.count)].elementsEqual(new) {
                return base
            }
        }
        return base + " " + extra
    }
    func sameUtterance(_ a: String, _ b: String) -> Bool {
        let x = keys(a), y = keys(b)
        if x.isEmpty || y.isEmpty { return true }
        if x.starts(with: y) || y.starts(with: x) { return true }
        let n = min(x.count, y.count)
        var shared = 0
        while shared < n, x[shared] == y[shared] { shared += 1 }
        return shared >= 2 || (shared > 0 && shared * 2 >= n)
    }

    let latest = stripDictationFillers(latest.trimmingCharacters(in: .whitespacesAndNewlines))
    var locked = stripDictationFillers(locked.trimmingCharacters(in: .whitespacesAndNewlines))
    var tentative = stripDictationFillers(tentative.trimmingCharacters(in: .whitespacesAndNewlines))
    if !latest.isEmpty {
        let old = keys(tentative)
        let new = keys(latest)
        if tentative.isEmpty || sameUtterance(tentative, latest) {
            if !(old.starts(with: new) && old.count > new.count) { tentative = latest }
        } else {
            locked = fresh(locked, tentative)
            tentative = latest
        }
    }
    if final {
        locked = fresh(locked, tentative)
        tentative = ""
    }
    return (locked, tentative, tentative.isEmpty ? locked : fresh(locked, tentative))
}

struct DictateNote: Codable, Equatable, Identifiable {
    var id: String
    var text: String
    var at: Date
}

func decodeDictateNotes(_ data: Data) -> [DictateNote] {
    (try? JSONDecoder().decode([DictateNote].self, from: data)) ?? []
}

func encodeDictateNotes(_ notes: [DictateNote]) -> Data {
    (try? JSONEncoder().encode(notes)) ?? Data("[]".utf8)
}

func rememberDictation(_ text: String, notes: [DictateNote]) -> [DictateNote] {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return notes }
    var notes = notes
    notes.insert(DictateNote(id: UUID().uuidString, text: text, at: Date()), at: 0)
    if notes.count > 50 { notes.removeLast(notes.count - 50) }
    return notes
}

struct DictateBox {
    var width: CGFloat
    var height: CGFloat
    var textHeight: CGFloat
}

func dictateBox(text: String) -> DictateBox {
    if text.isEmpty { return DictateBox(width: 184, height: 40, textHeight: 0) }
    let lines = min(3, max(1, (text.count + 37) / 38))
    let textHeight = CGFloat(lines) * 22 + 6
    return DictateBox(width: 300, height: 40 + textHeight, textHeight: textHeight)
}

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

func waveBars(_ samples: [Float], count: Int = 5) -> [Double] {
    guard count > 0 else { return [] }
    guard !samples.isEmpty else { return Array(repeating: 0, count: count) }
    let size = max(1, samples.count / count)
    return (0..<count).map { index in
        let start = index * size
        let end = min(samples.count, start + size)
        guard end > start else { return 0 }
        var sum: Float = 0
        for sample in samples[start..<end] { sum += sample * sample }
        return min(1, Double(sqrt(sum / Float(end - start)) * 8))
    }
}

struct AICall {
    var url: String
    var headers: [String: String]
    var body: Data
}

func aiCall(service: String, model: String, key: String, instruction: String, text: String) -> AICall? {
    let service = AIService(rawValue: service) ?? .openrouter
    if service == .apple { return nil }
    let model = model.isEmpty ? service.defaultModel : model
    if service == .anthropic {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096, // ponytail: long rewrites get cut here. Raise the cap if they do.
            "system": instruction,
            "messages": [["role": "user", "content": text]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        return AICall(url: "https://api.anthropic.com/v1/messages", headers: [
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        ], body: data)
    }
    var body: [String: Any] = [
        "model": model,
        "messages": [
            ["role": "system", "content": instruction],
            ["role": "user", "content": text],
        ],
    ]
    if service == .openrouter { body["provider"] = ["allow_fallbacks": true] }
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
    let url: String
    switch service {
    case .openai: url = "https://api.openai.com/v1/chat/completions"
    case .huggingface: url = "https://router.huggingface.co/v1/chat/completions"
    default: url = "https://openrouter.ai/api/v1/chat/completions"
    }
    var headers = ["Authorization": "Bearer \(key)", "Content-Type": "application/json"]
    if service == .openrouter { headers["X-Title"] = "Jerox" }
    return AICall(url: url, headers: headers, body: data)
}

func aiReply(service: String, data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let raw: String?
    if service == AIService.anthropic.rawValue {
        raw = ((json["content"] as? [[String: Any]])?.first?["text"] as? String)
    } else {
        let choices = json["choices"] as? [[String: Any]]
        raw = (choices?.first?["message"] as? [String: Any])?["content"] as? String
    }
    let cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleaned.isEmpty ? nil : cleaned
}

func aiErrorMessage(data: Data, status: Int, service: String) -> String {
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    if let error = json?["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
        return message
    }
    if let error = json?["error"] as? String, !error.isEmpty { return error }
    let name = AIService(rawValue: service)?.title ?? "AI"
    return "\(name) failed (\(status))."
}

func savedAIModel(service: String) -> String {
    let fallback = AIService(rawValue: service)?.defaultModel ?? AIService.openrouter.defaultModel
    if let saved = UserDefaults.standard.string(forKey: "aiModel.\(service)"), !saved.isEmpty { return saved }
    if service == AIService.openrouter.rawValue {
        let old = UserDefaults.standard.string(forKey: "openrouterModel") ?? ""
        if !old.isEmpty { return old }
    }
    return fallback
}

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

private func isLink(_ text: String) -> Bool {
    guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
    if scheme == "mailto" { return text.contains("@") }
    return (scheme == "http" || scheme == "https") && url.host != nil
}

private func parseHex(_ digits: String) -> RGBA? {
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

private func parseRGBCall(_ text: String) -> RGBA? {
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

private func req(_ ok: Bool, _ message: String) {
    if !ok { fatalError("history check failed: \(message)") }
}

#if JEROX_CHECK
@main
struct HistoryCheckMain {
    static func main() {
        ClipboardHistory.selfCheck()
    }
}
#endif
