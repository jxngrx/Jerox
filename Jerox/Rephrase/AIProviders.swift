import Foundation

struct AICall {
    var url: String
    var headers: [String: String]
    var body: Data
}

func cleanAPIKey(_ raw: String) -> String {
    var key = raw.components(separatedBy: .whitespacesAndNewlines).joined()
    if key.lowercased().hasPrefix("bearer") { key = String(key.dropFirst(6)) }
    return key
}

func aiCall(service: String, model: String, key: String, instruction: String, text: String) -> AICall? {
    let service = AIService(rawValue: service) ?? .openrouter
    if service == .local { return nil }
    // A pasted key often carries a newline or space; URLSession drops such a header value
    // silently, and the server then reports "authentication header is missing".
    let key = cleanAPIKey(key)
    let model = cleanAPIKey(model).isEmpty ? service.defaultModel : cleanAPIKey(model)
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
