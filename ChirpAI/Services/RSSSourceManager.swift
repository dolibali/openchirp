import Foundation

class RSSSourceManager {
    static let shared = RSSSourceManager()
    private let customSourcesKey = "custom_rss_sources"
    private let disabledSourcesKey = "disabled_rss_sources"
    private let deletedSourcesKey = "deleted_rss_sources"
    private let sourceStatusesKey = "rss_source_statuses"

    func loadAllSources() -> [RSSSource] {
        let deletedNames = loadDeletedNames()
        var sources = loadBuiltInSources().filter { !deletedNames.contains($0.name) }
        sources += loadCustomSources()
        let disabledNames = loadDisabledNames()
        for i in sources.indices {
            if disabledNames.contains(sources[i].name) {
                sources[i].isEnabled = false
            }
        }
        return sources
    }

    func loadEnabledSources() -> [RSSSource] {
        loadAllSources().filter { $0.isEnabled }
    }

    func addSource(name: String, url: String, category: String) {
        var custom = loadCustomSources()
        custom.append(RSSSource(name: name, url: url, category: category, isBuiltIn: false))
        saveCustomSources(custom)
    }

    func deleteSource(_ source: RSSSource) {
        if source.isBuiltIn {
            var deleted = loadDeletedNames()
            deleted.append(source.name)
            UserDefaults.standard.set(deleted, forKey: deletedSourcesKey)
        } else {
            var custom = loadCustomSources()
            custom.removeAll { $0.id == source.id }
            saveCustomSources(custom)
        }
    }

    func updateSource(_ source: RSSSource) {
        if source.isBuiltIn {
            return
        }
        var custom = loadCustomSources()
        if let idx = custom.firstIndex(where: { $0.id == source.id }) {
            custom[idx] = source
            saveCustomSources(custom)
        }
    }

    func toggleSource(_ source: RSSSource, enabled: Bool) {
        if source.isBuiltIn {
            var disabled = loadDisabledNames()
            if enabled {
                disabled.removeAll { $0 == source.name }
            } else {
                disabled.append(source.name)
            }
            UserDefaults.standard.set(disabled, forKey: disabledSourcesKey)
        } else {
            var custom = loadCustomSources()
            if let idx = custom.firstIndex(where: { $0.id == source.id }) {
                custom[idx].isEnabled = enabled
                saveCustomSources(custom)
            }
        }
    }

    func updateStatus(for sourceName: String, success: Bool, message: String?) {
        var statuses = loadSourceStatuses()
        statuses[sourceName] = [
            "success": success,
            "message": message ?? "",
            "time": ISO8601DateFormatter().string(from: Date())
        ]
        UserDefaults.standard.set(statuses, forKey: sourceStatusesKey)
    }

    func getStatus(for sourceName: String) -> (success: Bool, message: String, time: Date?) {
        let statuses = loadSourceStatuses()
        guard let info = statuses[sourceName] as? [String: Any] else { return (false, "未抓取", nil) }
        let success = info["success"] as? Bool ?? false
        let message = info["message"] as? String ?? ""
        let timeStr = info["time"] as? String
        let time = timeStr.flatMap { ISO8601DateFormatter().date(from: $0) }
        return (success, message, time)
    }

    private func loadBuiltInSources() -> [RSSSource] {
        guard let url = Bundle.main.url(forResource: "rss_sources", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        var sources = (try? JSONDecoder().decode([RSSSource].self, from: data)) ?? []
        for i in sources.indices {
            sources[i].isBuiltIn = true
        }
        return sources
    }

    private func loadCustomSources() -> [RSSSource] {
        guard let data = UserDefaults.standard.data(forKey: customSourcesKey) else { return [] }
        return (try? JSONDecoder().decode([RSSSource].self, from: data)) ?? []
    }

    private func saveCustomSources(_ sources: [RSSSource]) {
        if let data = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(data, forKey: customSourcesKey)
        }
    }

    private func loadDisabledNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: disabledSourcesKey) ?? []
    }

    private func loadDeletedNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: deletedSourcesKey) ?? []
    }

    private func loadSourceStatuses() -> [String: Any] {
        UserDefaults.standard.dictionary(forKey: sourceStatusesKey) ?? [:]
    }
}
