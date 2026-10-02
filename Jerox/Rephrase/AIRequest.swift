import Foundation
import FoundationModels

func appleIntelligenceReady() -> Bool {
    guard #available(macOS 26, *) else { return false }
    return SystemLanguageModel.default.isAvailable
}

func appleRewrite(instruction: String, text: String) async throws -> String {
    guard #available(macOS 26, *) else { throw AIError(message: "Apple Intelligence needs macOS 26.") }
    guard SystemLanguageModel.default.isAvailable else {
        throw AIError(message: "Turn on Apple Intelligence in System Settings.")
    }
    let session = LanguageModelSession(instructions: instruction)
    let cleaned = try await session.respond(to: text).content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { throw AIError(message: "Apple Intelligence returned nothing.") }
    return cleaned
}

func requestAI(instruction: String, text: String) async throws -> String {
    let service = UserDefaults.standard.string(forKey: "aiProvider") ?? AIService.openrouter.rawValue
    if service == AIService.apple.rawValue {
        guard text.count <= 20_000 else { throw AIError(message: "Text is too long.") }
        return try await appleRewrite(instruction: instruction, text: text)
    }
    let title = AIService(rawValue: service)?.title ?? "AI"
    let key = APIKey.read(service)
    guard !key.isEmpty else { throw AIError(message: "Add a \(title) key in Settings.") }
    guard text.count <= 20_000 else { throw AIError(message: "Text is too long.") }
    guard let call = aiCall(service: service, model: savedAIModel(service: service), key: key, instruction: instruction, text: text),
          let url = URL(string: call.url) else {
        throw AIError(message: "Could not build the request.")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 45
    for (field, value) in call.headers { request.setValue(value, forHTTPHeaderField: field) }
    request.httpBody = call.body
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw AIError(message: aiErrorMessage(data: data, status: status, service: service)) }
    guard let reply = aiReply(service: service, data: data) else {
        throw AIError(message: "\(title) returned nothing.")
    }
    return reply
}
