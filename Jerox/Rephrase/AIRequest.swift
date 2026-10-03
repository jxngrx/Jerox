import Foundation

func requestAI(instruction: String, text: String) async throws -> String {
    let service = UserDefaults.standard.string(forKey: "aiProvider") ?? AIService.openrouter.rawValue
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
