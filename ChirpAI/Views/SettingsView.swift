import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var hasStarted = false
    
    var body: some View {
        Group {
            if hasStarted {
                SettingsContentView(viewModel: _buildViewModel())
            } else {
                ProgressView().onAppear { hasStarted = true }
            }
        }
    }
    
    private func _buildViewModel() -> SettingsViewModel {
        let pm = PreferenceManager(modelContext: modelContext)
        return SettingsViewModel(modelContext: modelContext, preferenceManager: pm)
    }
}

struct SettingsContentView: View {
    @StateObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            if viewModel.needsProfileRefresh || viewModel.pendingFeedbackCount > 0 {
                Section(viewModel.needsProfileRefresh ? "画像待处理" : "画像同步") {
                    NavigationLink(destination: ProfileSettingsView(viewModel: viewModel)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.needsProfileRefresh ? "画像更新曾失败，建议尽快重试" : "有 \(viewModel.pendingFeedbackCount) 条新反馈待纳入画像")
                                .font(.subheadline)
                                .foregroundColor(viewModel.needsProfileRefresh ? .red : .primary)
                            Text(viewModel.needsProfileRefresh
                                 ? (viewModel.profileRefreshFailureMessage.isEmpty
                                    ? "进入“我的画像与调教”后点击“立即更新画像”，系统会继续尝试把这些反馈写入长期画像。"
                                    : "最近一次失败原因：\(viewModel.profileRefreshFailureMessage)")
                                 : "这些反馈会在累计到一定数量后自动纳入画像，你也可以手动立即更新。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("偏好设置") {
                NavigationLink(destination: ProfileSettingsView(viewModel: viewModel)) {
                    HStack {
                        Label("我的画像与调教", systemImage: "person.text.rectangle")
                        Spacer()
                        if viewModel.needsProfileRefresh {
                            SyncBadge(text: "待重试", color: .red, systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                        } else if viewModel.pendingFeedbackCount > 0 {
                            SyncBadge(text: "\(viewModel.pendingFeedbackCount) 待处理", color: .orange, systemImage: "tray.and.arrow.down.fill")
                        }
                    }
                }
                NavigationLink(destination: ScheduledDeliveryView()) {
                    Label("定时推送", systemImage: "clock.badge")
                }
            }

            Section("连接配置") {
                NavigationLink(destination: RSSSourceManageView()) {
                    Label("RSS 源管理", systemImage: "dot.radiowaves.left.and.right")
                }
                NavigationLink(destination: RSSFetchSettingsView(viewModel: viewModel)) {
                    HStack {
                        Label("RSS 抓取策略", systemImage: "calendar.badge.clock")
                        Spacer()
                        Text("最近 \(viewModel.rssFetchLookbackDays) 天")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink(destination: AISettingsView()) {
                    Label("AI 配置", systemImage: "cpu")
                }
            }
        }
        .navigationTitle("设置")
        .onAppear {
            viewModel.loadData()
        }
    }
}

struct ProfileSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var directFeedbackText = ""

    var body: some View {
        List {
            Section("当前画像") {
                Text(viewModel.profileSummary)
                    .font(.body)
                    .foregroundColor(.primary)
            }

            if viewModel.needsProfileRefresh || viewModel.pendingFeedbackCount > 0 {
                Section("同步状态") {
                    VStack(alignment: .leading, spacing: 8) {
                        if viewModel.needsProfileRefresh {
                            Text("仍有 \(viewModel.pendingFeedbackCount) 条反馈尚未成功写入画像。")
                                .foregroundColor(.red)
                            if !viewModel.profileRefreshFailureMessage.isEmpty {
                                Text("最近一次失败原因：\(viewModel.profileRefreshFailureMessage)")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("当前有 \(viewModel.pendingFeedbackCount) 条反馈待纳入画像。")
                                .foregroundColor(.primary)
                            Text("系统会在新增反馈累计到一定数量时自动更新，你也可以现在手动触发。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("快速操作") {
                Button {
                    Task {
                        await viewModel.summarizeNow()
                    }
                } label: {
                    HStack {
                        if viewModel.isSummarizing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding(.trailing, 8)
                        }
                        Text(viewModel.isSummarizing ? "正在更新画像..." : "立即更新画像")
                    }
                }
                .disabled(viewModel.isSummarizing)

                Text("用最近待处理的反馈立即刷新当前画像。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                Button {
                    Task {
                        await viewModel.rebuildProfileFromAllFeedbacks()
                    }
                } label: {
                    HStack {
                        if viewModel.isRebuildingFromHistory {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding(.trailing, 8)
                        }
                        Text(viewModel.isRebuildingFromHistory ? "正在根据全部历史反馈重建..." : "根据全部历史反馈重建画像")
                    }
                }
                .disabled(viewModel.isRebuildingFromHistory || viewModel.isSummarizing)

                Text("用全部历史反馈重新校准画像，适合画像跑偏或切换模型后使用。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("自动更新策略") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("触发阈值")
                        Spacer()

                        Button {
                            viewModel.updateAutoProfileRefreshThreshold(viewModel.autoProfileRefreshThreshold - 1)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                        }
                        .disabled(viewModel.autoProfileRefreshThreshold <= 1)

                        Text("\(viewModel.autoProfileRefreshThreshold)")
                            .frame(minWidth: 28)
                            .font(.body.monospacedDigit())

                        Text("条")
                            .foregroundColor(.secondary)

                        Button {
                            viewModel.updateAutoProfileRefreshThreshold(viewModel.autoProfileRefreshThreshold + 1)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .disabled(viewModel.autoProfileRefreshThreshold >= 20)
                    }
                    .buttonStyle(.borderless)

                    Text("数值越小更新越快，越大则更省调用。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section("反馈与历史") {
                NavigationLink(destination: FeedbackLogsView(viewModel: viewModel)) {
                    HStack {
                        Label("反馈记录", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        if viewModel.needsProfileRefresh {
                            SyncBadge(text: "待重试", color: .red, systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                        } else if viewModel.pendingFeedbackCount > 0 {
                            SyncBadge(text: "\(viewModel.pendingFeedbackCount) 待处理", color: .orange, systemImage: "tray.and.arrow.down")
                        }
                    }
                }

                Text("回看每次点赞、点踩和文字反馈，以及它们是否已经写入画像。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("手动调教") {
                Text("直接告诉 AI 想看什么、不想看什么，适合表达明确偏好。")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                TextField("例如：少看泛娱乐，多给我 AI 工程和创业相关的深度内容", text: $directFeedbackText, axis: .vertical)
                    .lineLimit(4...8)

                Button {
                    let text = directFeedbackText
                    Task {
                        let didSucceed = await viewModel.submitDirectFeedback(text)
                        if didSucceed {
                            directFeedbackText = ""
                        }
                    }
                } label: {
                    HStack {
                        if viewModel.isSubmittingDirectFeedback {
                            ProgressView().progressViewStyle(CircularProgressViewStyle())
                                .padding(.trailing, 8)
                        }
                        Text("强制扭转画像")
                    }
                }
                .disabled(directFeedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmittingDirectFeedback)
            }
        }
        .navigationTitle("画像调教")
        .alert(viewModel.statusAlertTitle, isPresented: $viewModel.showStatusAlert) {
            Button("好的", role: .cancel) { }
        } message: {
            Text(viewModel.statusAlertMessage)
        }
    }
}

struct FeedbackLogsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            if viewModel.feedbacks.isEmpty {
                Text("暂无反馈").foregroundColor(.secondary)
            } else {
                ForEach(viewModel.feedbacks, id: \.id) { fb in
                    HStack {
                        Image(systemName: fb.action == "like" ? "hand.thumbsup" : (fb.action == "neutral" ? "eyes" : "hand.thumbsdown"))
                            .foregroundColor(fb.action == "like" ? .green : (fb.action == "neutral" ? .gray : .red))
                        VStack(alignment: .leading) {
                            Text(fb.newsItem?.title ?? "关联文章已不可用")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            if let sourceName = fb.newsItem?.sourceName {
                                Text(sourceName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let text = fb.textFeedback, !text.isEmpty {
                                Text(text)
                                    .font(.subheadline)
                                    .lineLimit(2)
                            }
                            HStack(spacing: 8) {
                                Text(fb.action == "like" ? "点赞" : (fb.action == "neutral" ? "一般" : "点踩"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                SyncBadge(
                                    text: fb.isPendingProfileIncorporation ? "待处理" : "已同步",
                                    color: fb.isPendingProfileIncorporation ? .orange : .green,
                                    systemImage: fb.isPendingProfileIncorporation ? "clock.badge.exclamationmark" : "checkmark.circle.fill"
                                )
                                Text(fb.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.deleteFeedback(fb)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("历史反馈")
    }
}

struct SyncBadge: View {
    let text: String
    let color: Color
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct RSSFetchSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            Section("扫描范围") {
                Stepper(value: rssLookbackBinding, in: 1...30) {
                    HStack {
                        Text("只扫描最近的文章")
                        Spacer()
                        Text("\(viewModel.rssFetchLookbackDays) 天")
                            .foregroundColor(.secondary)
                    }
                }

                Text("超过这个时间窗口的 RSS 文章，会在进入 AI 初筛前直接过滤。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("RSS 抓取策略")
    }

    private var rssLookbackBinding: Binding<Int> {
        Binding(
            get: { viewModel.rssFetchLookbackDays },
            set: { viewModel.updateRSSFetchLookbackDays($0) }
        )
    }
}

struct AISettingsView: View {
    @ObservedObject private var manager = AIConfigManager.shared
    @State private var showAddSheet = false
    @State private var editingProfile: AIConfigProfile? = nil

    var body: some View {
        List {
            ForEach(manager.profiles) { profile in
                Button {
                    manager.activate(profile)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(profile.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                if profile.id == manager.activeID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                            }
                            Text(profile.model)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if profile.apiKey.isEmpty {
                            Text("未配置 Key")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        manager.delete(profile)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        editingProfile = profile
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("AI 配置")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AIConfigEditView()
        }
        .sheet(item: $editingProfile) { profile in
            AIConfigEditView(existingProfile: profile)
        }
    }
}

struct ScheduledDeliveryView: View {
    @State private var scheduledTimes: [Date] = []
    @State private var selectedTime = Date()
    @State private var showAuthAlert = false

    var body: some View {
        List {
            Section(header: Text("本地通知设定"), footer: Text("iOS 会在您设定的时间准时弹出通知，点击即可立即加载推文。这不仅能打破后台刷新的不确定性，同时也极大地节省了无意义的后台待机耗电。")) {
                DatePicker("选择时间", selection: $selectedTime, displayedComponents: .hourAndMinute)
                Button("添加推送时间点") {
                    addTime(selectedTime)
                }
            }
            
            Section("已设定的推送时间") {
                if scheduledTimes.isEmpty {
                    Text("暂无设定的推送").foregroundColor(.secondary)
                } else {
                    ForEach(scheduledTimes, id: \.self) { time in
                        Text(time, style: .time)
                    }
                    .onDelete(perform: removeTime)
                }
            }
        }
        .navigationTitle("定时推送")
        .onAppear {
            requestNotificationPermission()
            loadTimes()
        }
        .alert("需要通知权限", isPresented: $showAuthAlert) {
            Button("前往设置", role: .none) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("我们需要通知权限来在指定时间提醒你阅读推文。")
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if !granted {
                    showAuthAlert = true
                }
            }
        }
    }
    
    private func addTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let cleanDate = Calendar.current.date(from: components) else { return }
        
        if !scheduledTimes.contains(cleanDate) {
            scheduledTimes.append(cleanDate)
            scheduledTimes.sort()
            saveAndSchedule()
        }
    }
    
    private func removeTime(at offsets: IndexSet) {
        scheduledTimes.remove(atOffsets: offsets)
        saveAndSchedule()
    }
    
    private func loadTimes() {
        if let data = UserDefaults.standard.data(forKey: "scheduledTimes"),
           let dates = try? JSONDecoder().decode([Date].self, from: data) {
            scheduledTimes = dates
        }
    }
    
    private func saveAndSchedule() {
        if let data = try? JSONEncoder().encode(scheduledTimes) {
            UserDefaults.standard.set(data, forKey: "scheduledTimes")
        }
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        for (i, time) in scheduledTimes.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "推文送达 📰"
            content.body = "已经为您准备好了此时刻的精选 AI 推文，点击立刻获取。"
            content.sound = .default
            
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "news_trigger_\(i)", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request)
        }
    }
}
