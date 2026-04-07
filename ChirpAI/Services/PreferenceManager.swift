import Foundation
import SwiftData

@MainActor
class PreferenceManager {
    private let modelContext: ModelContext
    private let diagnostics = AppDiagnosticsLogger.shared
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
        do {
            return try modelContext.fetch(descriptor).first?.summary
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "读取当前画像失败",
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    func saveProfile(summary: String) throws {
        let descriptor = FetchDescriptor<UserProfile>()
        do {
            let existing = try modelContext.fetch(descriptor)
            for old in existing {
                modelContext.delete(old)
            }

            let newProfile = UserProfile(summary: summary)
            modelContext.insert(newProfile)
            try modelContext.save()
        } catch {
            diagnostics.error(
                domain: "profile",
                message: "保存画像失败",
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }
    }

    func deleteFeedback(_ feedback: Feedback) throws {
        do {
            modelContext.delete(feedback)
            try modelContext.save()
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "删除反馈失败",
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }

        if getPendingFeedbackCount() == 0 {
            setNeedsProfileRefresh(false)
        }
    }

    func cleanupExpiredSeenNews() -> Int {
        let now = Date()
        let descriptor = FetchDescriptor<SeenNews>(
            predicate: #Predicate { $0.expireAt < now }
        )
        do {
            let expired = try modelContext.fetch(descriptor)
            for item in expired {
                modelContext.delete(item)
            }
            if !expired.isEmpty {
                try modelContext.save()
            }
            return expired.count
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "清理过期已读记录失败",
                metadata: ["error": error.localizedDescription]
            )
            return 0
        }
    }

    func isNewsSeen(urlHash: String) -> Bool {
        let descriptor = FetchDescriptor<SeenNews>(
            predicate: #Predicate { $0.urlHash == urlHash }
        )
        do {
            return try modelContext.fetchCount(descriptor) > 0
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "查询已读记录失败",
                metadata: [
                    "url_hash": urlHash,
                    "error": error.localizedDescription
                ]
            )
            return false
        }
    }

    func markNewsSeen(urlHash: String, title: String) {
        do {
            let seen = SeenNews(urlHash: urlHash, title: title)
            modelContext.insert(seen)
            try modelContext.save()
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "写入已读记录失败",
                metadata: [
                    "url_hash": urlHash,
                    "title": title,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    func getSeenTitles(limit: Int = 50) -> [String] {
        var descriptor = FetchDescriptor<SeenNews>(
            sortBy: [SortDescriptor(\.seenAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        do {
            return try modelContext.fetch(descriptor).map { $0.title }
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "读取已看标题失败",
                metadata: ["error": error.localizedDescription]
            )
            return []
        }
    }

    func getRecentFeedbacks(limit: Int = 30) -> [Feedback] {
        var descriptor = FetchDescriptor<Feedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "读取最近反馈失败",
                metadata: ["error": error.localizedDescription]
            )
            return []
        }
    }

    func getAllFeedbacksChronological() -> [Feedback] {
        let descriptor = FetchDescriptor<Feedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "读取历史反馈失败",
                metadata: ["error": error.localizedDescription]
            )
            return []
        }
    }

    func getFeedbackCount() -> Int {
        let descriptor = FetchDescriptor<Feedback>()
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "统计反馈数失败",
                metadata: ["error": error.localizedDescription]
            )
            return 0
        }
    }

    func getPendingFeedbacks(limit: Int = 30) -> [Feedback] {
        let descriptor = FetchDescriptor<Feedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            let allFeedbacks = try modelContext.fetch(descriptor)
            return Array(allFeedbacks.filter { $0.profileIncorporatedAt == nil }.prefix(limit))
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "读取待处理反馈失败",
                metadata: ["error": error.localizedDescription]
            )
            return []
        }
    }

    func getPendingFeedbackCount() -> Int {
        let descriptor = FetchDescriptor<Feedback>()
        do {
            let allFeedbacks = try modelContext.fetch(descriptor)
            return allFeedbacks.filter { $0.profileIncorporatedAt == nil }.count
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "统计待处理反馈失败",
                metadata: ["error": error.localizedDescription]
            )
            return 0
        }
    }

    func markFeedbacksIncorporated(_ feedbacks: [Feedback], at date: Date = Date()) throws {
        do {
            for feedback in feedbacks {
                feedback.profileIncorporatedAt = date
            }
            try modelContext.save()
        } catch {
            diagnostics.error(
                domain: "profile",
                message: "标记反馈已纳入画像失败",
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }
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
