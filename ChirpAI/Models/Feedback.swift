import Foundation
import SwiftData

@Model
final class Feedback {
    @Attribute(.unique) var id: UUID
    var action: String
    var textFeedback: String?
    var createdAt: Date
    var profileIncorporatedAt: Date?
    var newsItem: NewsItem?

    var feedbackAction: FeedbackAction? {
        FeedbackAction(rawValue: action)
    }

    var isPendingProfileIncorporation: Bool {
        profileIncorporatedAt == nil
    }

    init(
        id: UUID = UUID(),
        action: FeedbackAction,
        textFeedback: String? = nil,
        createdAt: Date = Date(),
        profileIncorporatedAt: Date? = nil,
        newsItem: NewsItem? = nil
    ) {
        self.id = id
        self.action = action.rawValue
        self.textFeedback = textFeedback
        self.createdAt = createdAt
        self.profileIncorporatedAt = profileIncorporatedAt
        self.newsItem = newsItem
    }
}
