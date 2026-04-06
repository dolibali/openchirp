import Foundation
import SwiftData

@Model
final class NewsItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var summary: String
    var content: String
    var sourceURL: String
    var sourceName: String
    var publishedAt: Date
    var fetchedAt: Date
    var imageURL: String?
    var reasoning: String?
    @Relationship(deleteRule: .cascade) var feedbacks: [Feedback]

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        content: String = "",
        sourceURL: String,
        sourceName: String,
        publishedAt: Date,
        fetchedAt: Date = Date(),
        imageURL: String? = nil,
        reasoning: String? = nil,
        feedbacks: [Feedback] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.content = content
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.imageURL = imageURL
        self.reasoning = reasoning
        self.feedbacks = feedbacks
    }
}
