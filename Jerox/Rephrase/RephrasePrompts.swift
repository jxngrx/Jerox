import Foundation

struct RephrasePrompt: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var instruction: String
}

let rephraseHuman = " Write it the way a person would. No em dashes, en dashes, or AI phrasing. If they listed items, keep a numbered list. Output only the rewritten text."

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

func rephrasePromptIsUsable(_ prompt: RephrasePrompt) -> Bool {
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
    case openrouter, openai, anthropic, huggingface

    var title: String {
        switch self {
        case .openrouter: "OpenRouter"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .huggingface: "Hugging Face"
        }
    }

    /// OpenRouter's default is a free model so rephrase works before anyone has a paid key.
    var defaultModel: String {
        switch self {
        case .openrouter: "deepseek/deepseek-chat-v3.1:free"
        case .openai: "gpt-4o-mini"
        case .anthropic: "claude-3-5-haiku-20241022"
        case .huggingface: "meta-llama/Llama-3.2-3B-Instruct"
        }
    }
}
