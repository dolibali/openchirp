import SwiftUI
import SwiftData

@main
struct ChirpAIApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        AppDiagnosticsLogger.shared.prune()
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                NewsFeedView()
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
        .modelContainer(for: [
            NewsItem.self,
            Feedback.self,
            UserProfile.self,
            SeenNews.self
        ])
    }
}
