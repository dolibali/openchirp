import Foundation
import Combine

struct AIRequestConfig {
    let apiKey: String
    let baseURL: String
    let model: String
}

// MARK: - 单条 AI 配置模型
struct AIConfigProfile: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var apiKey: String
    var baseURL: String
    var model: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case apiKey
        case baseURL
        case model
    }

    init(id: UUID = UUID(), name: String, apiKey: String, baseURL: String, model: String) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        baseURL = try container.decode(String.self, forKey: .baseURL)
        model = try container.decode(String.self, forKey: .model)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
    }

    var requestConfig: AIRequestConfig {
        AIRequestConfig(
            apiKey: apiKey,
            baseURL: baseURL,
            model: model
        )
    }
}

enum AIConfigManagerError: LocalizedError {
    case saveFailed(detail: String)
    case loadFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let detail):
            return "AI 配置保存失败：\(detail)"
        case .loadFailed(let detail):
            return "AI 配置加载失败：\(detail)"
        }
    }
}

// MARK: - AI 配置管理器
class AIConfigManager: ObservableObject {
    static let shared = AIConfigManager()

    private let profilesKey = "ai_config_profiles"
    private let activeIDKey = "ai_config_active_id"
    private let migrationWarningKey = "ai_config_migration_warning_message"
    private let keychain = KeychainService.shared
    private let diagnostics = AppDiagnosticsLogger.shared

    @Published var profiles: [AIConfigProfile] = []
    @Published var activeID: UUID?
    @Published var migrationWarningMessage: String?

    init() {
        do {
            try load()
        } catch {
            diagnostics.error(
                domain: "ai_config",
                message: "加载 AI 配置失败",
                metadata: ["error": error.localizedDescription]
            )
        }

        if profiles.isEmpty {
            let defaultProfile = AIConfigProfile(
                name: "智谱 GLM",
                apiKey: "",
                baseURL: "https://open.bigmodel.cn/api/coding/paas/v4",
                model: "GLM-4.7-FlashX"
            )
            profiles = [defaultProfile]
            activeID = defaultProfile.id

            do {
                try persistMetadata(profiles: profiles, activeID: activeID)
            } catch {
                diagnostics.error(
                    domain: "ai_config",
                    message: "初始化默认 AI 配置失败",
                    metadata: ["error": error.localizedDescription]
                )
            }
        }
    }

    var activeProfile: AIConfigProfile? {
        profiles.first(where: { $0.id == activeID }) ?? profiles.first
    }

    var activeRequestConfig: AIRequestConfig? {
        activeProfile?.requestConfig
    }

    func activate(_ profile: AIConfigProfile) throws {
        let nextActiveID = profile.id
        try persistMetadata(profiles: profiles, activeID: nextActiveID)
        activeID = nextActiveID
    }

    func add(_ profile: AIConfigProfile) throws {
        try persistAPIKeyIfNeeded(for: profile)

        var nextProfiles = profiles
        nextProfiles.append(profile)
        let nextActiveID = profiles.isEmpty ? profile.id : activeID

        try persistMetadata(profiles: nextProfiles, activeID: nextActiveID)
        profiles = nextProfiles
        activeID = nextActiveID
        clearMigrationWarning()
    }

    func update(_ profile: AIConfigProfile) throws {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        try persistAPIKeyIfNeeded(for: profile)

        var nextProfiles = profiles
        nextProfiles[idx] = profile

        try persistMetadata(profiles: nextProfiles, activeID: activeID)
        profiles = nextProfiles
        clearMigrationWarning()
    }

    func delete(_ profile: AIConfigProfile) throws {
        var nextProfiles = profiles
        nextProfiles.removeAll { $0.id == profile.id }
        let nextActiveID = (activeID == profile.id) ? nextProfiles.first?.id : activeID

        try deleteAPIKey(for: profile)
        try persistMetadata(profiles: nextProfiles, activeID: nextActiveID)

        profiles = nextProfiles
        activeID = nextActiveID
    }

    func hasAPIKey(_ profile: AIConfigProfile) -> Bool {
        !profile.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func dismissMigrationWarning() {
        clearMigrationWarning()
    }

    func requestConfig(for profile: AIConfigProfile) -> AIRequestConfig {
        profile.requestConfig
    }

    private func load() throws {
        migrationWarningMessage = UserDefaults.standard.string(forKey: migrationWarningKey)
        if let idStr = UserDefaults.standard.string(forKey: activeIDKey),
           let uuid = UUID(uuidString: idStr) {
            activeID = uuid
        }

        if let data = UserDefaults.standard.data(forKey: profilesKey) {
            do {
                var decoded = try JSONDecoder().decode([AIConfigProfile].self, from: data)
                var migratedAnyLegacyKey = false
                var migrationFailed = false

                for index in decoded.indices {
                    let account = keychainAccount(for: decoded[index].id)
                    let legacyAPIKey = decoded[index].apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

                    do {
                        if let keychainAPIKey = try keychain.load(account: account),
                           !keychainAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            decoded[index].apiKey = keychainAPIKey
                        } else if !legacyAPIKey.isEmpty {
                            try keychain.save(legacyAPIKey, account: account)
                            migratedAnyLegacyKey = true
                        }
                    } catch {
                        migrationFailed = true
                        let message = "检测到旧版明文 API Key，自动迁移到安全存储失败。请进入 AI 配置重新保存一次。"
                        setMigrationWarning(message)
                        diagnostics.error(
                            domain: "ai_config",
                            message: "迁移旧版 API Key 到 Keychain 失败",
                            metadata: [
                                "profile_id": decoded[index].id.uuidString,
                                "profile_name": decoded[index].name,
                                "error": error.localizedDescription
                            ]
                        )
                    }
                }

                profiles = decoded

                if migratedAnyLegacyKey && !migrationFailed {
                    try persistMetadata(profiles: decoded, activeID: activeID)
                    clearMigrationWarning()
                }
            } catch {
                throw AIConfigManagerError.loadFailed(detail: error.localizedDescription)
            }
        }
    }

    private func persistMetadata(profiles: [AIConfigProfile], activeID: UUID?) throws {
        do {
            let data = try JSONEncoder().encode(profiles)
            UserDefaults.standard.set(data, forKey: profilesKey)
            UserDefaults.standard.set(activeID?.uuidString, forKey: activeIDKey)
            objectWillChange.send()
        } catch {
            diagnostics.error(
                domain: "ai_config",
                message: "写入 AI 配置元数据失败",
                metadata: ["error": error.localizedDescription]
            )
            throw AIConfigManagerError.saveFailed(detail: error.localizedDescription)
        }
    }

    private func persistAPIKeyIfNeeded(for profile: AIConfigProfile) throws {
        let trimmedKey = profile.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmedKey.isEmpty {
                try keychain.delete(account: keychainAccount(for: profile.id))
            } else {
                try keychain.save(trimmedKey, account: keychainAccount(for: profile.id))
            }
        } catch {
            diagnostics.error(
                domain: "ai_config",
                message: "写入 API Key 到 Keychain 失败",
                metadata: [
                    "profile_id": profile.id.uuidString,
                    "profile_name": profile.name,
                    "error": error.localizedDescription
                ]
            )
            throw AIConfigManagerError.saveFailed(detail: error.localizedDescription)
        }
    }

    private func deleteAPIKey(for profile: AIConfigProfile) throws {
        do {
            try keychain.delete(account: keychainAccount(for: profile.id))
        } catch {
            diagnostics.error(
                domain: "ai_config",
                message: "删除 Keychain 中的 API Key 失败",
                metadata: [
                    "profile_id": profile.id.uuidString,
                    "profile_name": profile.name,
                    "error": error.localizedDescription
                ]
            )
            throw AIConfigManagerError.saveFailed(detail: error.localizedDescription)
        }
    }

    private func keychainAccount(for id: UUID) -> String {
        "profile.\(id.uuidString)"
    }

    private func setMigrationWarning(_ message: String) {
        migrationWarningMessage = message
        UserDefaults.standard.set(message, forKey: migrationWarningKey)
    }

    private func clearMigrationWarning() {
        migrationWarningMessage = nil
        UserDefaults.standard.removeObject(forKey: migrationWarningKey)
    }
}
