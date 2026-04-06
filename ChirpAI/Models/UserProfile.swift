import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var summary: String
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        summary: String = "",
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.generatedAt = generatedAt
    }
}
