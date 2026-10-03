import Foundation

/// Downloads one file over several parallel ranged connections. A single connection to the Hugging Face CDN is
/// often throttled to a fraction of the line speed; a handful of connections fills it. Each part retries and
/// resumes from where it stopped. All state lives on one serial queue.
final class SegmentedDownload: NSObject, URLSessionDataDelegate {
    private struct Part {
        var start: Int64
        var end: Int64 // inclusive
        var got: Int64 = 0
        var tries = 0
        var task: URLSessionDataTask?
        var finished: Bool { start + got > end }
    }

    private let source: URL
    private let destination: URL
    private let partCount = 8
    private let queue = DispatchQueue(label: "com.jxngrx.jerox.download")
    private var session: URLSession!
    private var parts: [Part] = []
    private var owners: [Int: Int] = [:] // task id -> part index
    private var handle: FileHandle?
    private var total: Int64 = 0
    private var lastReport = Date.distantPast
    private var done = false
    private var onProgress: (Double) -> Void
    private var onFinish: (String?) -> Void // nil means the file is complete

    init(source: URL, destination: URL, onProgress: @escaping (Double) -> Void, onFinish: @escaping (String?) -> Void) {
        self.source = source
        self.destination = destination
        self.onProgress = onProgress
        self.onFinish = onFinish
        super.init()
        let operations = OperationQueue()
        operations.underlyingQueue = queue
        operations.maxConcurrentOperationCount = 1
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = partCount
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config, delegate: self, delegateQueue: operations)
    }

    func start() {
        // A 1-byte ranged request finds the total size and the final CDN address, so the parts skip the redirect.
        var probe = URLRequest(url: source)
        probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        session.dataTask(with: probe) { [weak self] _, response, error in
            self?.queue.async { self?.begin(response as? HTTPURLResponse, error: error) }
        }.resume()
    }

    func cancel() {
        queue.async {
            self.done = true
            self.session.invalidateAndCancel()
            try? self.handle?.close()
            self.handle = nil
            try? FileManager.default.removeItem(at: self.destination)
        }
    }

    private func begin(_ response: HTTPURLResponse?, error: Error?) {
        guard !done else { return }
        if let status = response?.statusCode, status == 401 || status == 403 {
            return fail("This file needs a Hugging Face login, so Jerox cannot download it.")
        }
        guard error == nil, let response, response.statusCode == 206,
              let range = response.value(forHTTPHeaderField: "Content-Range"),
              let size = Int64(range.split(separator: "/").last ?? ""), size > 0 else {
            return fail("Download failed. Check the connection.")
        }
        total = size
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let file = try? FileHandle(forWritingTo: destination) else { return fail("Could not save the model.") }
        try? file.truncate(atOffset: UInt64(size))
        handle = file
        let each = (size + Int64(partCount) - 1) / Int64(partCount)
        parts = (0..<partCount).compactMap { i in
            let start = Int64(i) * each
            return start < size ? Part(start: start, end: min(size - 1, start + each - 1)) : nil
        }
        let address = response.url ?? source
        for index in parts.indices { launch(index, address) }
    }

    private func launch(_ index: Int, _ address: URL) {
        var request = URLRequest(url: address)
        request.setValue("bytes=\(parts[index].start + parts[index].got)-\(parts[index].end)", forHTTPHeaderField: "Range")
        let task = session.dataTask(with: request)
        parts[index].task = task
        owners[task.taskIdentifier] = index
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // A server that ignores Range would send the whole file to every part and corrupt the result.
        completionHandler((response as? HTTPURLResponse)?.statusCode == 206 ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !done, let index = owners[dataTask.taskIdentifier], let handle else { return }
        do {
            try handle.seek(toOffset: UInt64(parts[index].start + parts[index].got))
            try handle.write(contentsOf: data)
        } catch {
            return fail("Could not save the model. Is the disk full?")
        }
        parts[index].got += Int64(data.count)
        if Date().timeIntervalSince(lastReport) > 0.15 {
            lastReport = Date()
            onProgress(Double(parts.reduce(0) { $0 + $1.got }) / Double(max(total, 1)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !done, let index = owners.removeValue(forKey: task.taskIdentifier) else { return }
        if parts[index].finished {
            if parts.allSatisfy(\.finished) { finish() }
            return
        }
        parts[index].tries += 1
        guard parts[index].tries <= 5 else { return fail("Download failed. Check the connection.") }
        let address = task.originalRequest?.url ?? source
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.done else { return }
            self.launch(index, address)
        }
    }

    private func finish() {
        done = true
        try? handle?.close()
        handle = nil
        session.finishTasksAndInvalidate()
        onProgress(1)
        onFinish(nil)
    }

    private func fail(_ message: String) {
        guard !done else { return }
        done = true
        session.invalidateAndCancel()
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: destination)
        onFinish(message)
    }
}
