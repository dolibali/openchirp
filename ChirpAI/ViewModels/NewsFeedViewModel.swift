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

    private let modelContext: ModelContext
    private let preferenceManager: PreferenceManager
    private let glmService = GLMService()
    private let newsFetcher: NewsFetcher
    private var cancellables = Set<AnyCancellable>()

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
        let totalFeedbacks = preferenceManager.getFeedbackCount()
        // Only run after every 5 feedbacks
        guard totalFeedbacks > 0 && totalFeedbacks % 5 == 0 else {
            return
        }
        
        do {
            let feedbacks = preferenceManager.getRecentFeedbacks(limit: 20)
            let currentProfile = preferenceManager.getCurrentProfileSummary()

            let newSummary = try await glmService.updateProfile(
                currentProfile: currentProfile,
                recentFeedbacks: feedbacks.map { fb in
                    (action: fb.action, textFeedback: fb.textFeedback, newsTitle: fb.newsItem?.title ?? "", newsSummary: fb.newsItem?.summary ?? "")
                }
            )
            preferenceManager.saveProfile(summary: newSummary)
        } catch {
            print("AI 画像自动更新失败: \(error)")
        }
    }

    func openFeedbackSheet(for news: NewsItem, defaultAction: FeedbackAction) {
        selectedNewsForFeedback = news
        defaultFeedbackAction = defaultAction
        showFeedbackSheet = true
    }
}
