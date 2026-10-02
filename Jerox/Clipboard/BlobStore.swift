import AppKit
import CryptoKit
import Foundation
import os

// ponytail: files over 8MB match on size, mtime, and path so a copy doesn't read the whole disk
func fileIdentity(_ url: URL) -> String {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
        return "dir:\(url.path)"
    }
    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let size = values?.fileSize ?? -1
    if size > 8 * 1024 * 1024 {
        let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "meta:\(size):\(mtime):\(url.path)"
    }
    return fileSHA256(url) ?? "path:\(url.path)"
}

func screenshotDirectory() -> URL {
    let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    guard let raw = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
          !raw.isEmpty else { return desktop }
    let path = (raw as NSString).expandingTildeInPath
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return desktop }
    return URL(fileURLWithPath: path, isDirectory: true)
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func storeBlob(id: UUID, ext: String?, payload: Data?, thumb: Data?) {
    let dir = ClipboardHistory.blobsURL
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        deleteBlobFiles(id: id)
        if let ext, let payload {
            try payload.write(to: dir.appendingPathComponent("\(id.uuidString).\(ext)"), options: .atomic)
        }
        if let thumb {
            try thumb.write(to: dir.appendingPathComponent("\(id.uuidString).thumb.png"), options: .atomic)
        }
    } catch {
        log.error("blob write failed: \(error.localizedDescription, privacy: .public)")
    }
}

func deleteBlobs(_ clips: [Clip]) {
    for clip in clips { deleteBlobFiles(id: clip.id) }
}

func deleteBlobFiles(id: UUID) {
    let dir = ClipboardHistory.blobsURL
    guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
    let prefix = id.uuidString
    for file in files where file.lastPathComponent.hasPrefix(prefix) {
        try? FileManager.default.removeItem(at: file)
    }
}

func blobData(_ clip: Clip) -> Data? {
    guard let ext = clip.blobExt else { return nil }
    return try? Data(contentsOf: ClipboardHistory.blobsURL.appendingPathComponent("\(clip.id.uuidString).\(ext)"))
}
