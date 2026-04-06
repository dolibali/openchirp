import Foundation
import SwiftData

@MainActor
class PreferenceManager {
    private let modelContext: ModelContext
    private let needsProfileRefreshKey = "needs_profile_refresh"
    private let profileRefreshFailureMessageKey = "profile_refresh_failure_message"
    private let autoProfileRefreshThresholdKey = "auto_profile_refresh_threshold"
    private let autoProfileRefreshThresholdMigrationKey = "auto_profile_refresh_threshold_migrated_v2"
    private let rssFetchLookbackDaysKey = "rss_fetch_lookback_days"
    private let defaultAutoProfileRefreshThreshold = 10
    private let defaultRSSFetchLookbackDays = 7

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

        if getPendingFeedbackCount() == 0 {
            setNeedsProfileRefresh(false)
        }
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

    func getAllFeedbacksChronological() -> [Feedback] {
        let descriptor = FetchDescriptor<Feedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func getFeedbackCount() -> Int {
        let descriptor = FetchDescriptor<Feedback>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func getPendingFeedbacks(limit: Int = 30) -> [Feedback] {
        let descriptor = FetchDescriptor<Feedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allFeedbacks = (try? modelContext.fetch(descriptor)) ?? []
        return Array(allFeedbacks.filter { $0.profileIncorporatedAt == nil }.prefix(limit))
    }

    func getPendingFeedbackCount() -> Int {
        let descriptor = FetchDescriptor<Feedback>()
        let allFeedbacks = (try? modelContext.fetch(descriptor)) ?? []
        return allFeedbacks.filter { $0.profileIncorporatedAt == nil }.count
    }

    func markFeedbacksIncorporated(_ feedbacks: [Feedback], at date: Date = Date()) {
        for feedback in feedbacks {
            feedback.profileIncorporatedAt = date
        }
        try? modelContext.save()
    }

    func setNeedsProfileRefresh(_ needsRefresh: Bool, failureMessage: String? = nil) {
        UserDefaults.standard.set(needsRefresh, forKey: needsProfileRefreshKey)
        if needsRefresh, let failureMessage, !failureMessage.isEmpty {
            UserDefaults.standard.set(failureMessage, forKey: profileRefreshFailureMessageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: profileRefreshFailureMessageKey)
        }
    }

    func needsProfileRefresh() -> Bool {
        let needsRefresh = UserDefaults.standard.bool(forKey: needsProfileRefreshKey)
        if needsRefresh && getPendingFeedbackCount() == 0 {
            setNeedsProfileRefresh(false)
            return false
        }
        return needsRefresh
    }

    func getProfileRefreshFailureMessage() -> String? {
        guard needsProfileRefresh() else { return nil }
        return UserDefaults.standard.string(forKey: profileRefreshFailureMessageKey)
    }

    func getAutoProfileRefreshThreshold() -> Int {
        migrateLegacyAutoProfileRefreshThresholdIfNeeded()
        let threshold = UserDefaults.standard.integer(forKey: autoProfileRefreshThresholdKey)
        guard threshold > 0 else { return defaultAutoProfileRefreshThreshold }
        return min(max(threshold, 1), 20)
    }

    func setAutoProfileRefreshThreshold(_ threshold: Int) {
        let sanitized = min(max(threshold, 1), 20)
        UserDefaults.standard.set(sanitized, forKey: autoProfileRefreshThresholdKey)
    }

    func getRSSFetchLookbackDays() -> Int {
        let days = UserDefaults.standard.integer(forKey: rssFetchLookbackDaysKey)
        guard days > 0 else { return defaultRSSFetchLookbackDays }
        return min(max(days, 1), 30)
    }

    func setRSSFetchLookbackDays(_ days: Int) {
        let sanitized = min(max(days, 1), 30)
        UserDefaults.standard.set(sanitized, forKey: rssFetchLookbackDaysKey)
    }

    private func migrateLegacyAutoProfileRefreshThresholdIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: autoProfileRefreshThresholdMigrationKey) else { return }

        let storedThreshold = UserDefaults.standard.integer(forKey: autoProfileRefreshThresholdKey)
        if storedThreshold == 20 {
            UserDefaults.standard.set(defaultAutoProfileRefreshThreshold, forKey: autoProfileRefreshThresholdKey)
        }

        UserDefaults.standard.set(true, forKey: autoProfileRefreshThresholdMigrationKey)
    }
}
