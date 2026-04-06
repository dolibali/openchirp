import Foundation
import SwiftData

@MainActor
class PreferenceManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func getCurrentProfileSummary() -> String? {
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.summary
    }

    func saveProfile(summary: String) {
        let descriptor = FetchDescriptor<UserProfile>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        for old in existing {
            modelContext.delete(old)
        }

        let newProfile = UserProfile(summary: summary)
        modelContext.insert(newProfile)
        try? modelContext.save()
    }

    func deleteFeedback(_ feedback: Feedback) {
        modelContext.delete(feedback)
        try? modelContext.save()
    }

    func cleanupExpiredSeenNews() {
        let now = Date()
        let descriptor = FetchDescriptor<SeenNews>(
            predicate: #Predicate { $0.expireAt < now }
        )
        let expired = (try? modelContext.fetch(descriptor)) ?? []
        for item in expired {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    func isNewsSeen(urlHash: String) -> Bool {
        let descriptor = FetchDescriptor<SeenNews>(
            predicate: #Predicate { $0.urlHash == urlHash }
        )
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    func markNewsSeen(urlHash: String, title: String) {
        let seen = SeenNews(urlHash: urlHash, title: title)
        modelContext.insert(seen)
        try? modelContext.save()
    }

    func getSeenTitles(limit: Int = 50) -> [String] {
        var descriptor = FetchDescriptor<SeenNews>(
            sortBy: [SortDescriptor(\.seenAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor))?.map { $0.title } ?? []
    }

    func getRecentFeedbacks(limit: Int = 30) -> [Feedback] {
        var descriptor = FetchDescriptor<Feedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func getFeedbackCount() -> Int {
        let descriptor = FetchDescriptor<Feedback>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
}
