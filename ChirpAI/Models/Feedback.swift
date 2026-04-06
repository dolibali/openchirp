import Foundation
import SwiftData

@Model
final class Feedback {
    @Attribute(.unique) var id: UUID
    var action: String
    var textFeedback: String?
    var createdAt: Date
    var newsItem: NewsItem?

    var feedbackAction: FeedbackAction? {
        FeedbackAction(rawValue: action)
    }

    init(
        id: UUID = UUID(),
        action: FeedbackAction,
        textFeedback: String? = nil,
        createdAt: Date = Date(),
        newsItem: NewsItem? = nil
    ) {
        self.id = id
        self.action = action.rawValue
        self.textFeedback = textFeedback
        self.createdAt = createdAt
        self.newsItem = newsItem
    }
}
