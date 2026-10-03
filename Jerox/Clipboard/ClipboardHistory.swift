import CoreGraphics
import Foundation

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

func req(_ ok: Bool, _ message: String) {
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
