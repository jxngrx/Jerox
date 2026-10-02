import CoreGraphics
import Foundation

func stripDictationFillers(_ text: String) -> String {
    let fillers: Set = ["uh", "um", "ah", "er", "hmm", "mm", "uhm", "uhh", "ahh", "umm", "eh"]
    return text.split(separator: " ").map(String.init).filter { word in
        let bare = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
        return !fillers.contains(bare)
    }.joined(separator: " ")
}

let ordinalWords = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]

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

func bareWord(_ word: String) -> String {
    word.trimmingCharacters(in: .punctuationCharacters).lowercased()
}

func listPieces(_ text: String) -> [String] {
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

func renderList(preface: String, items: [String]) -> String? {
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
