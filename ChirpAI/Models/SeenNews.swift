import Foundation
import SwiftData

@Model
final class SeenNews {
    @Attribute(.unique) var urlHash: String
    var title: String
    var seenAt: Date
    var expireAt: Date

    init(
        urlHash: String,
        title: String,
        seenAt: Date = Date(),
        expireAt: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    ) {
        self.urlHash = urlHash
        self.title = title
        self.seenAt = seenAt
        self.expireAt = expireAt
    }
}
