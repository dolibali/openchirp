import Foundation
import SwiftData
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var feedbacks: [Feedback] = []
    @Published var profileSummary: String = "暂无画像数据"
    @Published var isSummarizing = false
    @Published var isSubmittingDirectFeedback = false

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
    }

    func summarizeNow() async {
        isSummarizing = true
        defer { isSummarizing = false }

        do {
            let feedbacks = preferenceManager.getRecentFeedbacks(limit: 30)
            let currentProfile = preferenceManager.getCurrentProfileSummary()

            let newSummary = try await glmService.updateProfile(
                currentProfile: currentProfile,
                recentFeedbacks: feedbacks.map { fb in
                    (action: fb.action, textFeedback: fb.textFeedback, newsTitle: fb.newsItem?.title ?? "", newsSummary: fb.newsItem?.summary ?? "")
                }
            )
            preferenceManager.saveProfile(summary: newSummary)
            profileSummary = newSummary
        } catch {
            profileSummary = "总结失败：\(error.localizedDescription)"
        }
    }

    func submitDirectFeedback(_ text: String) async {
        guard !text.isEmpty else { return }
        isSubmittingDirectFeedback = true
        
        do {
            let currentProfile = preferenceManager.getCurrentProfileSummary()
            let newSummary = try await glmService.updateProfileDirectly(
                currentProfile: currentProfile,
                userInstruction: text
            )
            preferenceManager.saveProfile(summary: newSummary)
            profileSummary = newSummary
        } catch {
            print("直接更新偏好失败: \(error)")
        }
        
        isSubmittingDirectFeedback = false
    }

    func deleteFeedback(_ feedback: Feedback) {
        preferenceManager.deleteFeedback(feedback)
        loadData()
    }
}
