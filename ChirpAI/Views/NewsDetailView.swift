import SwiftUI
import SwiftData

struct NewsDetailView: View {
    let news: NewsItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(news.title)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack {
                    Text(news.sourceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(news.publishedAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let reasoning = news.reasoning, !reasoning.isEmpty {
                    Text(reasoning)
                        .font(.callout)
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)
                }

                Divider()

                if news.content.isEmpty {
                    Text(news.summary)
                        .font(.body)
                } else {
                    Text(news.content)
                        .font(.body)
                }

                if let url = URL(string: news.sourceURL) {
                    Link("阅读原文", destination: url)
                        .font(.subheadline)
                        .padding(.top, 8)
                }
            }
            .padding()
        }
        .navigationTitle("推文详情")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}
