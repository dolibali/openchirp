import SwiftUI
import SwiftData

struct OnboardingView: View {
    let onComplete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var step = 0
    @State private var selectedCategories: Set<String> = []
    @State private var customInstructions: String = ""

    private let categories = [
        "科技", "财经", "体育", "娱乐", "国际",
        "健康", "教育", "汽车", "游戏", "美食"
    ]
    private let styles = ["快讯速览", "深度长文", "都要"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                if step == 0 {
                    welcomeView
                } else if step == 1 {
                    categoryView
                } else if step == 2 {
                    instructionView
                }

                Spacer()

                HStack {
                    if step > 0 {
                        Button("上一步") { step -= 1 }
                    }
                    Spacer()
                    if step < 2 {
                        Button("下一步") { step += 1 }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("开始使用") {
                            savePreferences()
                            onComplete()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("欢迎")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("跳过") { onComplete() }
                }
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            Text("欢迎使用 ChirpAI")
                .font(.title)
                .fontWeight(.bold)
            Text("先聊几句了解你的喜好，之后会越来越懂你。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private var categoryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("你平时关注哪些领域？")
                .font(.title3)
                .fontWeight(.semibold)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(categories, id: \.self) { cat in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedCategories.contains(cat) {
                                selectedCategories.remove(cat)
                            } else {
                                selectedCategories.insert(cat)
                            }
                        }
                    }) {
                        Text(cat)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(selectedCategories.contains(cat) ? .white : .primary)
                            .background(selectedCategories.contains(cat) ? Color.blue : Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedCategories.contains(cat) ? Color.blue : Color.clear, lineWidth: 2)
                            )
                    }
                }
            }
        }
        .padding(.top, 20)
    }

    private var instructionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("还有什么特别嘱咐 AI 的吗？")
                .font(.title3)
                .fontWeight(.semibold)
                
            Text("例如：不想看到任何花边推文、多推荐干货长文...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("告诉 AI 你的阅读雷区或偏好...", text: $customInstructions, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(5...8)
        }
        .padding(.top, 20)
    }

    private func savePreferences() {
        var parts = Array(selectedCategories)
        if !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("特别指令：\(customInstructions)")
        }
        let summary = "用户初始兴趣：" + parts.joined(separator: "、")
        let pm = PreferenceManager(modelContext: modelContext)
        pm.saveProfile(summary: summary)
    }
}
