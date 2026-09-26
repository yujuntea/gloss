import Foundation
import SwiftData

@Model
final class QueryRecord {
    @Attribute(.unique) var id: UUID
    var inputText: String?
    var inputKind: String
    var kindParamsJSON: String?
    var origin: String
    var thumbnail: Data?
    var responseMarkdown: String
    var model: String
    var createdAt: Date
    var isStarred: Bool

    init(id: UUID = UUID(), inputText: String?, inputKind: String, kindParamsJSON: String? = nil,
         origin: String, thumbnail: Data? = nil, responseMarkdown: String, model: String,
         createdAt: Date = Date(), isStarred: Bool = false) {
        self.id = id
        self.inputText = inputText
        self.inputKind = inputKind
        self.kindParamsJSON = kindParamsJSON
        self.origin = origin
        self.thumbnail = thumbnail
        self.responseMarkdown = responseMarkdown
        self.model = model
        self.createdAt = createdAt
        self.isStarred = isStarred
    }
}

@Model
final class ResponseCache {
    @Attribute(.unique) var key: String
    var response: String
    var createdAt: Date
    var lastAccessedAt: Date

    init(key: String, response: String, createdAt: Date = Date(), lastAccessedAt: Date = Date()) {
        self.key = key
        self.response = response
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
}
