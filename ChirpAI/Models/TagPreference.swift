import Foundation
import SwiftData

@Model
final class TagPreference {
    @Attribute(.unique) var name: String
    var score: Double
    var lastUpdated: Date
    var source: String

    init(
        name: String,
        score: Double = 0.0,
        lastUpdated: Date = Date(),
        source: String = "initial"
    ) {
        self.name = name
        self.score = score
        self.lastUpdated = lastUpdated
        self.source = source
    }
}
