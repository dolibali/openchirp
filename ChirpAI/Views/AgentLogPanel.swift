import SwiftUI

/// 展开态日志面板（半屏 sheet）
struct AgentLogPanel: View {
    let logs: [String]
    let isRunning: Bool
    let fetchStage: FetchStage

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    // 状态条
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(statusColor)
                        Spacer()
                        Text("\(logs.count) 条日志")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.green.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.08))

                    Divider().overlay(Color.green.opacity(0.3))

                    // 日志滚动区域
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                                    Text("> \(log)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.green)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                            .padding(16)
                        }
                        .onChange(of: logs.count) {
                            guard !logs.isEmpty else { return }
                            withAnimation {
                                proxy.scrollTo(logs.count - 1, anchor: .bottom)
                            }
                        }
                        .onAppear {
                            if !logs.isEmpty {
                                proxy.scrollTo(logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agentic LLM Pipeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
        }
    }

    private var statusText: String {
        switch fetchStage {
        case .interrupted:
            return "已中断，待恢复"
        case .failed:
            return "已失败"
        case .idle:
            return isRunning ? "运行中..." : "已完成"
        case .fetchingRSS:
            return "抓取 RSS 中..."
        case .preselecting:
            return "标题粗筛中..."
        case .ranking:
            return "精选重排中..."
        }
    }

    private var statusColor: Color {
        switch fetchStage {
        case .interrupted:
            return .orange
        case .failed:
            return .red
        case .idle:
            return isRunning ? .green : .gray
        case .fetchingRSS, .preselecting, .ranking:
            return .green
        }
    }
}
