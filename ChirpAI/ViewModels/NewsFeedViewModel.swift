import Foundation
import SwiftData
import Combine

@MainActor
class NewsFeedViewModel: ObservableObject {
    @Published var newsItems: [NewsItem] = []
    @Published var isFetching = false
    @Published var statusMessage = ""
    @Published var logs: [String] = []
    
    @Published var showAlert = false
    @Published var alertMessage = ""
    
    @Published var showFeedbackSheet = false
    @Published var selectedNewsForFeedback: NewsItem?
    @Published var defaultFeedbackAction: FeedbackAction = .like
    @Published var showProfileUpdateFailureAlert = false
    @Published var profileUpdateFailureMessage = ""

    private let modelContext: ModelContext
    private let preferenceManager: PreferenceManager
    private let glmService = GLMService()
    private let newsFetcher: NewsFetcher
    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingProfile = false

    init(modelContext: ModelContext, preferenceManager: PreferenceManager) {
        self.modelContext = modelContext
        self.preferenceManager = preferenceManager
        self.newsFetcher = NewsFetcher(modelContext: modelContext, preferenceManager: preferenceManager)

        newsFetcher.$statusMessage
            .receive(on: RunLoop.main)
            .assign(to: \.statusMessage, on: self)
            .store(in: &cancellables)

        newsFetcher.$fetchLogs
            .receive(on: RunLoop.main)
            .assign(to: \.logs, on: self)
            .store(in: &cancellables)

        newsFetcher.$isFetching
            .receive(on: RunLoop.main)
            .assign(to: \.isFetching, on: self)
            .store(in: &cancellables)
    }

    func loadNews() {
        let descriptor = FetchDescriptor<NewsItem>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        newsItems = (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchNext() async {
        await newsFetcher.fetchNextNews()

        if !newsFetcher.statusMessage.contains("获取失败") {
            await retryPendingProfileUpdateIfNeeded()
        }
        
        let finalMsg = newsFetcher.statusMessage
        if !finalMsg.isEmpty {
            alertMessage = finalMsg
            showAlert = true
        }
        
        loadNews()
    }
    
    func deleteNews(_ news: NewsItem) {
        if let idx = newsItems.firstIndex(where: { $0.id == news.id }) {
            newsItems.remove(at: idx)
        }
        modelContext.delete(news)
        try? modelContext.save()
    }

    func toggleFeedback(for news: NewsItem, action: FeedbackAction) async {
        let targetId: UUID? = news.id
        let fetchDescriptor = FetchDescriptor<Feedback>(
            predicate: #Predicate { $0.newsItem?.id == targetId }
        )
        let existingFeedbacks = (try? modelContext.fetch(fetchDescriptor)) ?? []
        let alreadyHasThisAction = existingFeedbacks.contains { $0.action == action.rawValue }
        
        // Remove existing feedbacks for this news (to ensure exclusive choice or handle cancellation)
        for old in existingFeedbacks {
            modelContext.delete(old)
        }
        try? modelContext.save()
        
        if alreadyHasThisAction {
            // Un-toggled successfully
            loadNews()
            return
        }

        let feedback = Feedback(
            action: action,
            textFeedback: nil,
            newsItem: news
        )
        modelContext.insert(feedback)
        try? modelContext.save()
        
        await checkAndRunProfileUpdate()
        loadNews()
    }

    func submitFeedback(for news: NewsItem, action: FeedbackAction, textFeedback: String?) async {
        // Remove existing generic feedback
        let targetId: UUID? = news.id
        let fetchDescriptor = FetchDescriptor<Feedback>(
            predicate: #Predicate { $0.newsItem?.id == targetId }
        )
        let existingFeedbacks = (try? modelContext.fetch(fetchDescriptor)) ?? []
        for old in existingFeedbacks {
            modelContext.delete(old)
        }
        
        let feedback = Feedback(
            action: action,
            textFeedback: textFeedback,
            newsItem: news
        )
        modelContext.insert(feedback)
        try? modelContext.save()

        await checkAndRunProfileUpdate()
        loadNews()
    }
    
    private func checkAndRunProfileUpdate() async {
        let pendingCount = preferenceManager.getPendingFeedbackCount()
        let threshold = preferenceManager.getAutoProfileRefreshThreshold()
        // 仅在新增反馈累计到一定数量时自动更新，避免重复消费旧记录
        guard pendingCount > 0 && pendingCount % threshold == 0 else {
            return
        }

        let feedbacks = preferenceManager.getPendingFeedbacks(limit: 30)
        await runProfileUpdate(with: feedbacks, showFailureAlert: true)
    }

    func openFeedbackSheet(for news: NewsItem, defaultAction: FeedbackAction) {
        selectedNewsForFeedback = news
        defaultFeedbackAction = defaultAction
        showFeedbackSheet = true
    }

    func retryPendingProfileUpdateIfNeeded() async {
        guard preferenceManager.needsProfileRefresh() else { return }
        let feedbacks = preferenceManager.getPendingFeedbacks(limit: 30)
        guard !feedbacks.isEmpty else {
            preferenceManager.setNeedsProfileRefresh(false)
            return
        }

        await runProfileUpdate(with: feedbacks, showFailureAlert: false)
    }

    private func runProfileUpdate(with feedbacks: [Feedback], showFailureAlert: Bool) async {
        guard !feedbacks.isEmpty, !isUpdatingProfile else { return }
        isUpdatingProfile = true
        defer { isUpdatingProfile = false }

        do {
            let currentProfile = preferenceManager.getCurrentProfileSummary()
            let newSummary = try await glmService.updateProfile(
                currentProfile: currentProfile,
                recentFeedbacks: feedbacks.map { fb in
                    (action: fb.action, textFeedback: fb.textFeedback, newsTitle: fb.newsItem?.title ?? "", newsSummary: fb.newsItem?.summary ?? "")
                }
            )
            preferenceManager.saveProfile(summary: newSummary)
            preferenceManager.markFeedbacksIncorporated(feedbacks)
            preferenceManager.setNeedsProfileRefresh(false)
        } catch {
            let message = error.localizedDescription
            print("AI 画像自动更新失败: \(message)")
            preferenceManager.setNeedsProfileRefresh(true, failureMessage: message)

            if showFailureAlert {
                profileUpdateFailureMessage = "画像自动更新失败。你可以前往设置里的“我的画像与调教”，点击“立即更新画像”重试。\n\n错误信息：\(message)"
                showProfileUpdateFailureAlert = true
            }
        }
    }
}
