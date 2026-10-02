import Foundation

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
