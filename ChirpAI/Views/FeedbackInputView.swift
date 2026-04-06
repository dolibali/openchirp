import SwiftUI

struct FeedbackInputView: View {
    let news: NewsItem
    let onSubmit: (FeedbackAction, String?) -> Void
    let onDismiss: () -> Void

    @State private var feedbackText = ""
    @State private var selectedAction: FeedbackAction
    
    init(news: NewsItem, defaultAction: FeedbackAction = .like, onSubmit: @escaping (FeedbackAction, String?) -> Void, onDismiss: @escaping () -> Void) {
        self.news = news
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        _selectedAction = State(initialValue: defaultAction)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(news.title)
                    .font(.headline)
                    .lineLimit(2)

                Picker("反馈类型", selection: $selectedAction) {
                    Text("推").tag(FeedbackAction.like)
                    Text("一般").tag(FeedbackAction.neutral)
                    Text("踩").tag(FeedbackAction.dislike)
                }
                .pickerStyle(.segmented)

                TextField("说点什么（可选）...", text: $feedbackText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Button("提交反馈") {
                    let text = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSubmit(selectedAction, text.isEmpty ? nil : text)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("反馈")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onDismiss() }
                }
            }
        }
    }
}
