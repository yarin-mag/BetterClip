// BetterClip/Core/BlobStore.swift
import Foundation
import CryptoKit

final class BlobStore {
    static let shared = BlobStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BetterClip/blobs"))

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ data: Data) -> String {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent(hash)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        return hash
    }

    func read(hash: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(hash))
    }

    func delete(hash: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(hash))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
