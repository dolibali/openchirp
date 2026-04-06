import SwiftUI

/// 展开态日志面板（半屏 sheet）
struct AgentLogPanel: View {
    let logs: [String]
    let isRunning: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    // 状态条
                    HStack {
                        Circle()
                            .fill(isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(isRunning ? "运行中..." : "已完成")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(isRunning ? .green : .gray)
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
}
