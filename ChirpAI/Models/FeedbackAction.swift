import Foundation

enum FeedbackAction: String, Codable, CaseIterable {
    case like
    case neutral
    case dislike
    case skip
}
