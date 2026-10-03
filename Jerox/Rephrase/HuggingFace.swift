import Foundation

/// A text-generation repo on the Hugging Face Hub that ships GGUF files.
struct HFRepo: Identifiable, Equatable {
    let id: String // "owner/name"
    let downloads: Int
}

/// One downloadable GGUF file, pinned to the repo revision it was listed at.
struct HFFile: Identifiable, Equatable {
    let name: String
    let bytes: Int64
    let sha256: String
    let revision: String
    var id: String { name }
}

func hfParseSearch(_ data: Data) -> [HFRepo] {
    guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    return list.compactMap { item in
        guard let id = item["id"] as? String else { return nil }
        return HFRepo(id: id, downloads: item["downloads"] as? Int ?? 0)
    }
}

/// Whole-model GGUF files only: split shards and vision projectors cannot run on their own here.
func hfParseFiles(_ data: Data) -> [HFFile] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let revision = json["sha"] as? String,
          let siblings = json["siblings"] as? [[String: Any]] else { return [] }
    return siblings.compactMap { item -> HFFile? in
        guard let name = item["rfilename"] as? String, name.lowercased().hasSuffix(".gguf"), !name.contains("/"),
              !name.lowercased().contains("mmproj"), !name.contains("-of-0"),
              let lfs = item["lfs"] as? [String: Any],
              let sha = lfs["sha256"] as? String, sha.count == 64,
              let bytes = (lfs["size"] as? NSNumber)?.int64Value ?? (item["size"] as? NSNumber)?.int64Value, bytes > 0
        else { return nil }
        return HFFile(name: name, bytes: bytes, sha256: sha, revision: revision)
    }
    .sorted { $0.bytes < $1.bytes }
}

enum HuggingFace {
    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AIError(message: status == 429 ? "Hugging Face is busy. Try again in a minute." : "Hugging Face answered \(status).") }
        return data
    }

    static func search(_ query: String) async throws -> [HFRepo] {
        var parts = URLComponents(string: "https://huggingface.co/api/models")!
        parts.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "pipeline_tag", value: "text-generation"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "15"),
        ]
        return hfParseSearch(try await get(parts.url!))
    }

    static func files(repo: String) async throws -> [HFFile] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true") else { return [] }
        return hfParseFiles(try await get(url))
    }
}

enum HuggingFaceCheck {
    static func run() {
        let search = Data(#"[{"id":"a/b-GGUF","downloads":12},{"downloads":3}]"#.utf8)
        assert(hfParseSearch(search) == [HFRepo(id: "a/b-GGUF", downloads: 12)])
        let sha = String(repeating: "a", count: 64)
        let repo = Data("""
        {"sha":"rev1","siblings":[
         {"rfilename":"m-Q8_0.gguf","lfs":{"sha256":"\(sha)","size":900}},
         {"rfilename":"m-Q4_K_M.gguf","lfs":{"sha256":"\(sha)","size":500}},
         {"rfilename":"mmproj-m.gguf","lfs":{"sha256":"\(sha)","size":50}},
         {"rfilename":"big-00001-of-00002.gguf","lfs":{"sha256":"\(sha)","size":700}},
         {"rfilename":"README.md"}]}
        """.utf8)
        let files = hfParseFiles(repo)
        assert(files.map(\.name) == ["m-Q4_K_M.gguf", "m-Q8_0.gguf"] && files.allSatisfy { $0.revision == "rev1" })
    }
}
