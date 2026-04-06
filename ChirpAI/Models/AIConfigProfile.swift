import Foundation
import Combine


// MARK: - 单条 AI 配置模型
struct AIConfigProfile: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var apiKey: String
    var baseURL: String
    var model: String
}

// MARK: - AI 配置管理器
class AIConfigManager: ObservableObject {
    static let shared = AIConfigManager()

    private let profilesKey = "ai_config_profiles"
    private let activeIDKey = "ai_config_active_id"

    @Published var profiles: [AIConfigProfile] = []
    @Published var activeID: UUID?

    init() {
        load()
        // 首次安装时插入默认配置
        if profiles.isEmpty {
            let defaultProfile = AIConfigProfile(
                name: "智谱 GLM",
                apiKey: "",
                baseURL: "https://open.bigmodel.cn/api/coding/paas/v4",
                model: "GLM-4.7-FlashX"
            )
            profiles = [defaultProfile]
            activeID = defaultProfile.id
            save()
        }
    }

    var activeProfile: AIConfigProfile? {
        profiles.first(where: { $0.id == activeID }) ?? profiles.first
    }

    func activate(_ profile: AIConfigProfile) {
        activeID = profile.id
        save()
    }

    func add(_ profile: AIConfigProfile) {
        profiles.append(profile)
        if profiles.count == 1 { activeID = profile.id }
        save()
    }

    func update(_ profile: AIConfigProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            save()
        }
    }

    func delete(_ profile: AIConfigProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeID == profile.id {
            activeID = profiles.first?.id
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        UserDefaults.standard.set(activeID?.uuidString, forKey: activeIDKey)
        objectWillChange.send()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([AIConfigProfile].self, from: data) {
            profiles = decoded
        }
        if let idStr = UserDefaults.standard.string(forKey: activeIDKey),
           let uuid = UUID(uuidString: idStr) {
            activeID = uuid
        }
    }
}
