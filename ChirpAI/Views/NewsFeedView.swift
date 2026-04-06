import SwiftUI
import SwiftData

struct NewsFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var hasStarted = false
    
    var body: some View {
        Group {
            if hasStarted {
                NewsFeedContentView(viewModel: _buildViewModel())
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("系统初始化...")
                        .foregroundColor(.secondary)
                }
                .onAppear {
                    hasStarted = true
                }
            }
        }
    }
    
    private func _buildViewModel() -> NewsFeedViewModel {
        let pm = PreferenceManager(modelContext: modelContext)
        return NewsFeedViewModel(modelContext: modelContext, preferenceManager: pm)
    }
}

struct NewsFeedContentView: View {
    @StateObject var viewModel: NewsFeedViewModel
    @State private var selectedNews: NewsItem?
    @State private var showLogPanel = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.newsItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "newspaper")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Button("获取推文") {
                            Task { await viewModel.fetchNext() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(viewModel.newsItems, id: \.id) { news in
                            NewsCardView(
                                news: news,
                                onTap: { selectedNews = news },
                                onLike: {
                                    Task { await viewModel.toggleFeedback(for: news, action: .like) }
                                },
                                onNeutral: {
                                    Task { await viewModel.toggleFeedback(for: news, action: .neutral) }
                                },
                                onDislike: {
                                    Task { await viewModel.toggleFeedback(for: news, action: .dislike) }
                                },
                                onLikeLongPress: {
                                    viewModel.openFeedbackSheet(for: news, defaultAction: .like)
                                },
                                onNeutralLongPress: {
                                    viewModel.openFeedbackSheet(for: news, defaultAction: .neutral)
                                },
                                onDislikeLongPress: {
                                    viewModel.openFeedbackSheet(for: news, defaultAction: .dislike)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.deleteNews(news)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.fetchNext()
                    }
                }
            }
            .navigationTitle("Chirps")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isFetching || !viewModel.logs.isEmpty {
                        Button {
                            showLogPanel = true
                        } label: {
                            HStack(spacing: 4) {
                                if viewModel.isFetching {
                                    BlinkingDot()
                                } else {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 5, height: 5)
                                }
                                Text(AgentStatusPill.stepPhrase(from: viewModel.logs))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Task { await viewModel.fetchNext() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isFetching)
                }
            }
            .sheet(isPresented: $showLogPanel) {
                AgentLogPanel(logs: viewModel.logs, isRunning: viewModel.isFetching)
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
            .sheet(isPresented: $viewModel.showFeedbackSheet) {
                if let news = viewModel.selectedNewsForFeedback {
                    MiniFeedbackSheet(
                        news: news,
                        defaultAction: viewModel.defaultFeedbackAction,
                        onSubmit: { action, text in
                            Task {
                                await viewModel.submitFeedback(for: news, action: action, textFeedback: text)
                                viewModel.showFeedbackSheet = false
                            }
                        },
                        onDismiss: { viewModel.showFeedbackSheet = false }
                    )
                    #if os(iOS)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
                    #endif
                }
            }
            .sheet(item: $selectedNews) { news in
                NavigationStack {
                    NewsDetailView(news: news)
                }
            }
            .onAppear {
                viewModel.loadNews()
            }
            .alert("提取结果", isPresented: $viewModel.showAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }
}
