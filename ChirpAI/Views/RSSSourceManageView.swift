import SwiftUI

struct RSSSourceManageView: View {
    @State private var sources: [RSSSource] = []
    @State private var showAddSheet = false
    @State private var editingSource: RSSSource?
    
    @State private var isTesting = false
    @State private var showTestResult = false
    @State private var testResultMsg = ""

    var body: some View {
        List {
            ForEach(sources) { source in
                RSSSourceRow(source: source, onToggle: { enabled in
                    RSSSourceManager.shared.toggleSource(source, enabled: enabled)
                    loadSources()
                }, onEdit: {
                    editingSource = source
                }, onDelete: {
                    RSSSourceManager.shared.deleteSource(source)
                    loadSources()
                }, onTest: {
                    Task {
                        isTesting = true
                        do {
                            let count = try await RSSParser.testRSS(url: source.url)
                            testResultMsg = "✅ [\(source.name)] 连接成功！\n解析到 \(count) 篇文章。"
                        } catch {
                            testResultMsg = "❌ [\(source.name)] 测试失败：\n\(error.localizedDescription)"
                        }
                        isTesting = false
                        showTestResult = true
                    }
                }, status: RSSSourceManager.shared.getStatus(for: source.name))
            }
        }
        .alert("连通性测试", isPresented: $showTestResult) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(testResultMsg)
        }
        .overlay {
            if isTesting {
                ProgressView("正在连接...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("RSS 源管理")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                AddRSSSourceView(onSave: { name, url, category in
                    RSSSourceManager.shared.addSource(name: name, url: url, category: category)
                    showAddSheet = false
                    loadSources()
                }, onCancel: {
                    showAddSheet = false
                })
            }
        }
        .sheet(item: $editingSource) { source in
            NavigationStack {
                EditRSSSourceView(source: source, onSave: { updated in
                    RSSSourceManager.shared.updateSource(updated)
                    editingSource = nil
                    loadSources()
                }, onCancel: {
                    editingSource = nil
                })
            }
        }
        .onAppear {
            loadSources()
        }
    }

    private func loadSources() {
        sources = RSSSourceManager.shared.loadAllSources()
    }
}

struct RSSSourceRow: View {
    let source: RSSSource
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTest: () -> Void
    let status: (success: Bool, message: String, time: Date?)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(source.name)
                            .font(.headline)
                        if source.isBuiltIn {
                            Text("内置")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(source.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(source.category)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                        if let time = status.time {
                            Text(time, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !status.message.isEmpty && status.message != "未抓取" {
                        Text(status.message)
                            .font(.caption2)
                            .foregroundColor(status.success ? .green : .red)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { source.isEnabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                onEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
            
            Button {
                onTest()
            } label: {
                Label("探测", systemImage: "network")
            }
            .tint(.green)
        }
    }
}

struct AddRSSSourceView: View {
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var url = ""
    @State private var category = "综合"
    
    @State private var isTesting = false
    @State private var showTestResult = false
    @State private var testResultMsg = ""

    private let categories = ["科技", "财经", "体育", "娱乐", "国际", "时政", "商业", "综合", "健康", "教育"]

    var body: some View {
        Form {
            Section("源信息") {
                TextField("名称", text: $name)
                TextField("RSS URL", text: $url)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Picker("分类", selection: $category) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat)
                    }
                }
            }
            
            Section {
                Button {
                    Task {
                        isTesting = true
                        do {
                            let count = try await RSSParser.testRSS(url: url)
                            testResultMsg = "✅ 连接成功！已成功解析到 \(count) 篇文章。"
                        } catch {
                            testResultMsg = "❌ 测试失败：\n\(error.localizedDescription)"
                        }
                        isTesting = false
                        showTestResult = true
                    }
                } label: {
                    if isTesting {
                        ProgressView().progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("测试此源数据")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isTesting || url.isEmpty)
            }
        }
        .alert("探测结果", isPresented: $showTestResult) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(testResultMsg)
        }
        .navigationTitle("添加 RSS 源")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard !name.isEmpty, !url.isEmpty else { return }
                    onSave(name, url, category)
                }
                .disabled(name.isEmpty || url.isEmpty)
            }
        }
    }
}

struct EditRSSSourceView: View {
    @State var source: RSSSource
    let onSave: (RSSSource) -> Void
    let onCancel: () -> Void
    
    @State private var isTesting = false
    @State private var showTestResult = false
    @State private var testResultMsg = ""

    private let categories = ["科技", "财经", "体育", "娱乐", "国际", "时政", "商业", "综合", "健康", "教育"]

    var body: some View {
        Form {
            Section("源信息") {
                TextField("名称", text: $source.name)
                TextField("RSS URL", text: $source.url)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Picker("分类", selection: $source.category) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat)
                    }
                }
            }
            
            Section {
                Button {
                    Task {
                        isTesting = true
                        do {
                            let count = try await RSSParser.testRSS(url: source.url)
                            testResultMsg = "✅ 连接成功！已成功解析到 \(count) 篇文章。"
                        } catch {
                            testResultMsg = "❌ 测试失败：\n\(error.localizedDescription)"
                        }
                        isTesting = false
                        showTestResult = true
                    }
                } label: {
                    if isTesting {
                        ProgressView().progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("测试此源数据")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isTesting || source.url.isEmpty)
            }
        }
        .alert("探测结果", isPresented: $showTestResult) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(testResultMsg)
        }
        .navigationTitle("编辑 RSS 源")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { onSave(source) }
                .disabled(source.name.isEmpty || source.url.isEmpty)
            }
        }
    }
}
