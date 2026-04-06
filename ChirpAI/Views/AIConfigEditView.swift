import SwiftUI

struct AIConfigEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = AIConfigManager.shared

    var existingProfile: AIConfigProfile?

    @State private var name: String = ""
    @State private var apiKey: String = ""
    @State private var baseURL: String = "https://open.bigmodel.cn/api/coding/paas/v4"
    @State private var model: String = "GLM-4.7-FlashX"

    @State private var isTesting = false
    @State private var testMessage = ""
    @State private var showTestResult = false

    private var isEditing: Bool { existingProfile != nil }
    private let glmService = GLMService()

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("配置名称（如：智谱 GLM-4）", text: $name)
                }
                Section("API 设置") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key").font(.caption).foregroundColor(.secondary)
                        SecureField("请输入 API Key", text: $apiKey)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Base URL").font(.caption).foregroundColor(.secondary)
                        TextField("API 地址", text: $baseURL)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("模型名称").font(.caption).foregroundColor(.secondary)
                        TextField("模型名称", text: $model)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                }
                Section {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView().progressViewStyle(CircularProgressViewStyle())
                                    .padding(.trailing, 6)
                                Text("测试中...")
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("测试连通性")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isTesting || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle(isEditing ? "编辑配置" : "新建配置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("连通性测试", isPresented: $showTestResult) {
                Button("好的", role: .cancel) { }
            } message: {
                Text(testMessage)
            }
            .onAppear {
                if let p = existingProfile {
                    name = p.name
                    apiKey = p.apiKey
                    baseURL = p.baseURL
                    model = p.model
                }
            }
        }
    }

    private func save() {
        var profile = existingProfile ?? AIConfigProfile(name: name, apiKey: apiKey, baseURL: baseURL, model: model)
        profile.name = name
        profile.apiKey = apiKey
        profile.baseURL = baseURL
        profile.model = model
        if isEditing {
            manager.update(profile)
        } else {
            manager.add(profile)
        }
        dismiss()
    }

    private func runTest() async {
        isTesting = true
        // 临时用当前表单里的值覆盖 Manager，测完后还原
        let oldActive = AIConfigManager.shared.activeProfile
        let tempProfile = AIConfigProfile(name: "temp", apiKey: apiKey, baseURL: baseURL, model: model)
        AIConfigManager.shared.add(tempProfile)
        AIConfigManager.shared.activate(tempProfile)

        do {
            let ok = try await glmService.testConnection()
            testMessage = ok ? "✅ 连接成功！AI 正常响应。" : "❌ 连接失败：未知错误"
        } catch {
            testMessage = "❌ 连接失败：\(error.localizedDescription)"
        }

        AIConfigManager.shared.delete(tempProfile)
        if let old = oldActive { AIConfigManager.shared.activate(old) }
        isTesting = false
        showTestResult = true
    }
}
