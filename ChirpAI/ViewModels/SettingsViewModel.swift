import Foundation
import SwiftData
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var feedbacks: [Feedback] = []
    @Published var profileSummary: String = "暂无画像数据"
    @Published var isSummarizing = false
    @Published var isSubmittingDirectFeedback = false
    @Published var showStatusAlert = false
    @Published var statusAlertTitle = ""
    @Published var statusAlertMessage = ""
    @Published var pendingFeedbackCount = 0
    @Published var needsProfileRefresh = false
    @Published var profileRefreshFailureMessage = ""
    @Published var autoProfileRefreshThreshold = 10
    @Published var rssFetchLookbackDays = 7
    @Published var isRebuildingFromHistory = false

    private let modelContext: ModelContext
    private let preferenceManager: PreferenceManager
    private let glmService = GLMService()

    init(modelContext: ModelContext, preferenceManager: PreferenceManager) {
        self.modelContext = modelContext
        self.preferenceManager = preferenceManager
    }

    func loadData() {
        var descriptor = FetchDescriptor<Feedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        feedbacks = (try? modelContext.fetch(descriptor)) ?? []

        if let summary = preferenceManager.getCurrentProfileSummary() {
            profileSummary = summary
        }

        refreshProfileSyncState()
    }

    func summarizeNow() async {
        let pendingFeedbacks = preferenceManager.getPendingFeedbacks(limit: 30)
        guard !pendingFeedbacks.isEmpty else {
            presentStatusAlert(
                title: "暂无可更新内容",
                message: "当前没有待纳入画像的新反馈。你可以继续对推荐内容点赞、一般或点踩，也可以直接在下方输入你的偏好要求。"
            )
            return
        }

        isSummarizing = true
        defer { isSummarizing = false }

        do {
            let currentProfile = preferenceManager.getCurrentProfileSummary()

            let newSummary = try await glmService.updateProfile(
                currentProfile: currentProfile,
                recentFeedbacks: pendingFeedbacks.map { fb in
                    (action: fb.action, textFeedback: fb.textFeedback, newsTitle: fb.newsItem?.title ?? "", newsSummary: fb.newsItem?.summary ?? "")
                }
            )
            preferenceManager.saveProfile(summary: newSummary)
            preferenceManager.markFeedbacksIncorporated(pendingFeedbacks)
            preferenceManager.setNeedsProfileRefresh(false)
            profileSummary = newSummary
            refreshProfileSyncState()
            presentStatusAlert(
                title: "画像已更新",
                message: "已根据待处理的反馈记录重新生成当前画像。"
            )
        } catch {
            preferenceManager.setNeedsProfileRefresh(true, failureMessage: error.localizedDescription)
            refreshProfileSyncState()
            presentStatusAlert(
                title: "更新失败",
                message: "暂时无法根据历史反馈更新画像。\n\n错误信息：\(error.localizedDescription)"
            )
        }
    }

    func rebuildProfileFromAllFeedbacks() async {
        let allFeedbacks = preferenceManager.getAllFeedbacksChronological()
        guard !allFeedbacks.isEmpty else {
            presentStatusAlert(
                title: "暂无历史反馈",
                message: "还没有历史反馈可用于重建画像。你可以先对推荐内容点赞、一般或点踩。"
            )
            return
        }

        isRebuildingFromHistory = true
        defer { isRebuildingFromHistory = false }

        do {
            let newSummary = try await glmService.rebuildProfileFromHistory(
                allFeedbacks: allFeedbacks.map { fb in
                    (action: fb.action, textFeedback: fb.textFeedback, newsTitle: fb.newsItem?.title ?? "", newsSummary: fb.newsItem?.summary ?? "")
                }
            )
            preferenceManager.saveProfile(summary: newSummary)
            preferenceManager.markFeedbacksIncorporated(allFeedbacks)
            preferenceManager.setNeedsProfileRefresh(false)
            profileSummary = newSummary
            refreshProfileSyncState()
            presentStatusAlert(
                title: "重建完成",
                message: "已基于全部 \(allFeedbacks.count) 条历史反馈重建画像。"
            )
        } catch {
            preferenceManager.setNeedsProfileRefresh(true, failureMessage: error.localizedDescription)
            refreshProfileSyncState()
            presentStatusAlert(
                title: "重建失败",
                message: "暂时无法根据全部历史反馈重建画像。\n\n错误信息：\(error.localizedDescription)"
            )
        }
    }

    @discardableResult
    func submitDirectFeedback(_ text: String) async -> Bool {
        guard !text.isEmpty else { return false }
        isSubmittingDirectFeedback = true
        
        do {
            let currentProfile = preferenceManager.getCurrentProfileSummary()
            let newSummary = try await glmService.updateProfileDirectly(
                currentProfile: currentProfile,
                userInstruction: text
            )
            preferenceManager.saveProfile(summary: newSummary)
            profileSummary = newSummary
            refreshProfileSyncState()
            isSubmittingDirectFeedback = false
            return true
        } catch {
            presentStatusAlert(
                title: "调教失败",
                message: "暂时无法应用这次直接调教。\n\n错误信息：\(error.localizedDescription)"
            )
            isSubmittingDirectFeedback = false
            return false
        }
    }

    func deleteFeedback(_ feedback: Feedback) {
        preferenceManager.deleteFeedback(feedback)
        loadData()
    }

    func updateAutoProfileRefreshThreshold(_ threshold: Int) {
        preferenceManager.setAutoProfileRefreshThreshold(threshold)
        autoProfileRefreshThreshold = preferenceManager.getAutoProfileRefreshThreshold()
    }

    func updateRSSFetchLookbackDays(_ days: Int) {
        preferenceManager.setRSSFetchLookbackDays(days)
        rssFetchLookbackDays = preferenceManager.getRSSFetchLookbackDays()
    }

    private func refreshProfileSyncState() {
        pendingFeedbackCount = preferenceManager.getPendingFeedbackCount()
        needsProfileRefresh = preferenceManager.needsProfileRefresh()
        profileRefreshFailureMessage = preferenceManager.getProfileRefreshFailureMessage() ?? ""
        autoProfileRefreshThreshold = preferenceManager.getAutoProfileRefreshThreshold()
        rssFetchLookbackDays = preferenceManager.getRSSFetchLookbackDays()
    }

    private func presentStatusAlert(title: String, message: String) {
        statusAlertTitle = title
        statusAlertMessage = message
        showStatusAlert = true
    }
}
