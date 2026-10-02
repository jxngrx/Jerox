import AVFoundation
import CryptoKit
import Foundation
import whisper

/// A downloadable on-device speech model. Same contract as Handy's catalog:
/// a pinned Hugging Face revision plus size and sha256, so the bytes on disk
/// provably match what was listed.
struct SpeechModel: Identifiable, Equatable {
    let id: String // file name in the repo, also the name on disk
    let name: String
    let detail: String
    let bytes: Int64
    let sha256: String
    var recommended = false

    var englishOnly: Bool { id.contains(".en") }
    var file: URL { SpeechCatalog.directory.appendingPathComponent(id) }
    var url: URL { URL(string: "https://huggingface.co/\(SpeechCatalog.repo)/resolve/\(SpeechCatalog.revision)/\(id)")! }
    var isDownloaded: Bool { FileManager.default.fileExists(atPath: file.path) }
}

enum SpeechCatalog {
    static let repo = "ggerganov/whisper.cpp"
    // Pinned like Handy: `resolve/<sha>` is immutable, so sizes and hashes below stay true.
    static let revision = "5359861c739e955e79d9a303bcbc70fb988958b1"
    static let apple = "apple"

    static let models: [SpeechModel] = [
        SpeechModel(id: "ggml-tiny-q5_1.bin", name: "Whisper Tiny", detail: "Fastest · rough drafts · 99 languages",
                    bytes: 32_152_673, sha256: "818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7"),
        SpeechModel(id: "ggml-base-q5_1.bin", name: "Whisper Base", detail: "Fast · everyday notes · 99 languages",
                    bytes: 59_707_625, sha256: "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"),
        SpeechModel(id: "ggml-small.en-q5_1.bin", name: "Whisper Small (English)", detail: "Accurate English · light on memory",
                    bytes: 190_098_681, sha256: "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30"),
        SpeechModel(id: "ggml-small-q5_1.bin", name: "Whisper Small", detail: "Balanced · 99 languages",
                    bytes: 190_085_487, sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb", recommended: true),
        SpeechModel(id: "ggml-large-v3-turbo-q5_0.bin", name: "Whisper Large v3 Turbo", detail: "Most accurate · 99 languages",
                    bytes: 574_041_195, sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2", recommended: true),
    ]

    static var directory: URL { ClipboardHistory.supportURL.appendingPathComponent("Models", isDirectory: true) }

    /// The downloaded model dictation uses. nil means Apple Speech.
    static var active: SpeechModel? {
        let id = UserDefaults.standard.string(forKey: "speechEngine") ?? apple
        return models.first { $0.id == id && $0.isDownloaded }
    }

    static func language(for model: SpeechModel) -> String {
        if model.englishOnly { return "en" }
        let id = UserDefaults.standard.string(forKey: "speechLocale") ?? ""
        guard !id.isEmpty else { return "auto" }
        return Locale(identifier: id).language.languageCode?.identifier ?? "auto"
    }
}

/// Download, verify, and delete catalog models. Main-thread state for the Settings UI.
@Observable
final class ModelStore {
    enum Phase: Equatable {
        case idle, downloading(Double), verifying, ready
        case failed(String)
    }

    static let shared = ModelStore()
    private(set) var phases: [String: Phase] = [:]
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var progress: [String: NSKeyValueObservation] = [:]

    init() {
        for model in SpeechCatalog.models { phases[model.id] = model.isDownloaded ? .ready : .idle }
    }

    func phase(_ model: SpeechModel) -> Phase { phases[model.id] ?? .idle }

    func download(_ model: SpeechModel) {
        guard tasks[model.id] == nil else { return }
        let dir = SpeechCatalog.directory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            phases[model.id] = .failed("Could not create the models folder.")
            return
        }
        let free = (try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? .max
        guard free > model.bytes + 200_000_000 else {
            phases[model.id] = .failed("Not enough disk space.")
            return
        }
        let part = dir.appendingPathComponent(model.id + ".part")
        // ponytail: no resume; a cancelled or failed download restarts. Add Range resume if large models fail often.
        let task = URLSession.shared.downloadTask(with: model.url) { [weak self] temp, response, error in
            // `temp` is deleted when this returns, so move it first.
            var failure: String?
            if let error {
                failure = (error as NSError).code == NSURLErrorCancelled ? nil : "Download failed. Check the connection."
                if failure == nil { return }
            } else if (response as? HTTPURLResponse)?.statusCode != 200 {
                failure = "Download failed (\((response as? HTTPURLResponse)?.statusCode ?? 0))."
            } else if let temp {
                try? FileManager.default.removeItem(at: part)
                do { try FileManager.default.moveItem(at: temp, to: part) } catch { failure = "Could not save the model." }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.clearTask(model.id)
                if let failure {
                    self.phases[model.id] = .failed(failure)
                } else {
                    self.verify(model, part: part)
                }
            }
        }
        progress[model.id] = task.progress.observe(\.fractionCompleted) { [weak self] value, _ in
            DispatchQueue.main.async {
                guard let self, case .downloading = self.phases[model.id] else { return }
                self.phases[model.id] = .downloading(value.fractionCompleted)
            }
        }
        tasks[model.id] = task
        phases[model.id] = .downloading(0)
        task.resume()
    }

    func cancel(_ model: SpeechModel) {
        tasks[model.id]?.cancel()
        clearTask(model.id)
        phases[model.id] = .idle
    }

    func delete(_ model: SpeechModel) {
        if UserDefaults.standard.string(forKey: "speechEngine") == model.id {
            UserDefaults.standard.set(SpeechCatalog.apple, forKey: "speechEngine")
        }
        WhisperEngine.shared.unload(model.file)
        try? FileManager.default.removeItem(at: model.file)
        phases[model.id] = .idle
    }

    private func verify(_ model: SpeechModel, part: URL) {
        phases[model.id] = .verifying
        DispatchQueue.global(qos: .utility).async {
            let size = (try? part.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
            var ok = Int64(size) == model.bytes && fileSHA256(part) == model.sha256
            if ok {
                try? FileManager.default.removeItem(at: model.file)
                ok = (try? FileManager.default.moveItem(at: part, to: model.file)) != nil
            }
            if !ok { try? FileManager.default.removeItem(at: part) }
            DispatchQueue.main.async {
                self.phases[model.id] = ok ? .ready : .failed("The download did not match. Try again.")
                if ok { UserDefaults.standard.set(model.id, forKey: "speechEngine") }
            }
        }
    }

    private func clearTask(_ id: String) {
        tasks[id] = nil
        progress[id]?.invalidate()
        progress[id] = nil
    }
}

func fileSHA256(_ url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
        let chunk = handle.readData(ofLength: 1 << 20)
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

/// whisper.cpp on a private serial queue. Keeps the last model loaded so the next dictation starts fast.
final class WhisperEngine {
    static let shared = WhisperEngine()
    private let queue = DispatchQueue(label: "com.jxngrx.jerox.whisper", qos: .userInitiated)
    private var context: OpaquePointer?
    private var loadedPath: String?

    /// `samples` are 16 kHz mono floats. `done` runs on the main thread; nil means the model failed.
    func transcribe(_ samples: [Float], model: SpeechModel, done: @escaping (String?) -> Void) {
        let language = SpeechCatalog.language(for: model)
        queue.async {
            let text = self.run(samples, path: model.file.path, language: language)
            DispatchQueue.main.async { done(text) }
        }
    }

    /// Free the model before the process exits: ggml's Metal backend asserts at exit while a context is alive.
    func shutdown() {
        queue.sync {
            if let context { whisper_free(context) }
            context = nil
            loadedPath = nil
        }
    }

    func unload(_ file: URL) {
        queue.async {
            guard self.loadedPath == file.path else { return }
            whisper_free(self.context)
            self.context = nil
            self.loadedPath = nil
        }
    }

    private func run(_ samples: [Float], path: String, language: String) -> String? {
        // Under ~0.3 s whisper tends to invent words; treat it as silence.
        guard samples.count > 4_800 else { return "" }
        if loadedPath != path {
            if let context { whisper_free(context) }
            context = whisper_init_from_file_with_params(path, whisper_context_default_params())
            loadedPath = context == nil ? nil : path
        }
        guard let context else { return nil }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.no_timestamps = true
        params.suppress_blank = true
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        let status = language.withCString { lang -> Int32 in
            params.language = lang
            return samples.withUnsafeBufferPointer { whisper_full(context, params, $0.baseAddress, Int32($0.count)) }
        }
        guard status == 0 else { return nil }
        return whisperText((0..<whisper_full_n_segments(context)).map { String(cString: whisper_full_get_segment_text(context, $0)) })
    }
}

/// Joins segments and drops whisper's non-speech markers such as "[BLANK_AUDIO]" or "(music)".
func whisperText(_ segments: [String]) -> String {
    segments
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { segment in
            guard let first = segment.first, let last = segment.last else { return false }
            return !((first == "[" && last == "]") || (first == "(" && last == ")"))
        }
        .joined(separator: " ")
}

/// Converts mic buffers to the 16 kHz mono float audio whisper expects. Call from one thread.
final class Resampler16k {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat

    init?(from input: AVAudioFormat) {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output) else { return nil }
        self.output = output
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * output.sampleRate / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return [] }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }
}

#if DEBUG
enum ModelsSelfCheck {
    static func run() {
        assert(whisperText([" Hello", "[BLANK_AUDIO]", " world. ", "(music)"]) == "Hello world.")
        assert(whisperText([]) == "")
        assert(SpeechCatalog.models.allSatisfy { $0.sha256.count == 64 && $0.bytes > 0 })
        assert(Set(SpeechCatalog.models.map(\.id)).count == SpeechCatalog.models.count)
        assert(SpeechCatalog.models.first { $0.id == "ggml-small.en-q5_1.bin" }!.englishOnly)
    }
}
#endif
