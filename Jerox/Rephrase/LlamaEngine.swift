import Foundation

/// Offline rephrase with a downloaded Qwen GGUF, through the C shim in JeroxLlama.c.
/// One serial queue guards all state (hence @unchecked Sendable); the model loads on first use and is freed after a few idle minutes.
final class LlamaEngine: @unchecked Sendable {
    static let shared = LlamaEngine()
    private let queue = DispatchQueue(label: "com.jxngrx.jerox.llama", qos: .userInitiated)
    private var llm: OpaquePointer?
    private var loadedPath: String?
    private var idleUnload: DispatchWorkItem?
    private let idleSeconds = 300.0

    func rewrite(instruction: String, text: String, model file: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.run(instruction: instruction, text: text, path: file.path))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Free the model before the process exits: ggml's Metal backend asserts at exit while a context is alive.
    func shutdown() {
        queue.sync { releaseModel() }
    }

    func unload(_ file: URL) {
        queue.async { if self.loadedPath == file.path { self.releaseModel() } }
    }

    private func releaseModel() {
        idleUnload?.cancel()
        idleUnload = nil
        if let llm { jerox_llm_free(llm) }
        llm = nil
        loadedPath = nil
    }

    private func run(instruction: String, text: String, path: String) throws -> String {
        var error = [CChar](repeating: 0, count: 256)
        if loadedPath != path {
            releaseModel()
            llm = jerox_llm_load(path, &error, error.count)
            guard llm != nil else { throw AIError(message: String(cString: error)) }
            loadedPath = path
        }
        defer { scheduleUnload() }
        guard let reply = jerox_llm_rewrite(llm, instruction, text, &error, error.count) else {
            throw AIError(message: String(cString: error))
        }
        defer { free(reply) }
        return String(cString: reply).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleUnload() {
        idleUnload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.releaseModel() }
        idleUnload = work
        queue.asyncAfter(deadline: .now() + idleSeconds, execute: work)
    }
}
