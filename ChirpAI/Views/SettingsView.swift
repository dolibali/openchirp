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
            Section("阅读与偏好") {
                NavigationLink(destination: ProfileSettingsView(viewModel: viewModel)) {
                    Label("我的画像与调教", systemImage: "person.text.rectangle")
                }
                NavigationLink(destination: ScheduledDeliveryView()) {
                    Label("定时推送", systemImage: "clock.badge")
                }
                NavigationLink(destination: FeedbackLogsView(viewModel: viewModel)) {
                    Label("反馈记录", systemImage: "clock.arrow.circlepath")
                }
            }

            Section("系统配置") {
                NavigationLink(destination: RSSSourceManageView()) {
                    Label("RSS 源管理", systemImage: "dot.radiowaves.left.and.right")
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
            Section("我的偏好画像") {
                Text(viewModel.profileSummary)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            Section("直接调教设定") {
                TextField("告诉 AI 以后想看什么，或不想看什么...", text: $directFeedbackText, axis: .vertical)
                    .lineLimit(4...8)
                
                Button {
                    let text = directFeedbackText
                    Task {
                        await viewModel.submitDirectFeedback(text)
                        directFeedbackText = ""
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
                            if let text = fb.textFeedback, !text.isEmpty {
                                Text(text).font(.subheadline).lineLimit(2)
                            } else {
                                Text(fb.action == "like" ? "点赞" : (fb.action == "neutral" ? "一般" : "点踩"))
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                            Text(fb.createdAt, style: .date)
                                .font(.caption2).foregroundColor(.secondary)
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
