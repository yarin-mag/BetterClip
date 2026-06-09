// BetterClip/Models/SnippetFolder.swift
import Foundation
import GRDB

struct SnippetFolder: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var parentId: Int64?
    var sortOrder: Int

    static let databaseTableName = "snippet_folders"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
