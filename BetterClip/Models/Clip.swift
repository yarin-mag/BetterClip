// BetterClip/Models/Clip.swift
import Foundation
import GRDB

enum ClipType: String, Codable {
    case text, image, rtf, url, file
}

struct Clip: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var type: ClipType
    var textContent: String?
    var blobHash: String?
    var appSource: String?
    var createdAt: Date
    var lastUsedAt: Date

    static let databaseTableName = "clips"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
