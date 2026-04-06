import SwiftUI

/// 轻量级反馈小弹窗 —— 仅含文字输入框，无需重新选择情绪
struct MiniFeedbackSheet: View {
    let news: NewsItem
    let defaultAction: FeedbackAction
    let onSubmit: (FeedbackAction, String?) -> Void
    let onDismiss: () -> Void

    @State private var feedbackText = ""
    @FocusState private var isFocused: Bool

    private var actionLabel: String {
        switch defaultAction {
        case .like:    return "👍 赞 ·"
        case .neutral: return "😐 一般 ·"
        case .dislike: return "👎 踩 ·"
        case .skip:    return "⏭ 跳过 ·"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 顶部标识行
            HStack {
                Text("\(actionLabel) 补充反馈")
                    .font(.headline)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            }

            // 标题提示
            Text(news.title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // 纯文字输入
            TextField("说说为什么？（可留空直接提交）", text: $feedbackText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...5)
                .focused($isFocused)

            // 提交
            Button {
                let text = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                onSubmit(defaultAction, text.isEmpty ? nil : text)
            } label: {
                Text("提交")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .onAppear { isFocused = true }
    }
}
