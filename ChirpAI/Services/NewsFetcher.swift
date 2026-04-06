import Foundation
import SwiftData
import Combine

struct RSSSource: Codable, Identifiable {
    var id: UUID
    var name: String
    var url: String
    var category: String
    var isEnabled: Bool
    var isBuiltIn: Bool
    var lastFetchedAt: Date?
    var lastFetchStatus: String?

    init(id: UUID = UUID(), name: String, url: String, category: String, isEnabled: Bool = true, isBuiltIn: Bool = false, lastFetchedAt: Date? = nil, lastFetchStatus: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.category = category
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.lastFetchedAt = lastFetchedAt
        self.lastFetchStatus = lastFetchStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = try c.decode(String.self, forKey: .name)
        name = decodedName
        url = try c.decode(String.self, forKey: .url)
        category = try c.decode(String.self, forKey: .category)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        lastFetchedAt = try c.decodeIfPresent(Date.self, forKey: .lastFetchedAt)
        lastFetchStatus = try c.decodeIfPresent(String.self, forKey: .lastFetchStatus)
        if let existingId = try? c.decodeIfPresent(UUID.self, forKey: .id) {
            id = existingId
        } else {
            let hex = HashUtil.md5(decodedName)
            var bytes = [UInt8]()
            var idx = hex.startIndex
            for _ in 0..<16 {
                let end = hex.index(idx, offsetBy: 2)
                bytes.append(UInt8(hex[idx..<end], radix: 16) ?? 0)
                idx = end
            }
            id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }
    }
}

@MainActor
class NewsFetcher: ObservableObject {
    @Published var isFetching = false
    @Published var statusMessage = ""
    @Published var fetchLogs: [String] = []

    private let modelContext: ModelContext
    private let preferenceManager: PreferenceManager
    private let glmService = GLMService()
    private let rssParser = RSSParser()

    init(modelContext: ModelContext, preferenceManager: PreferenceManager) {
        self.modelContext = modelContext
        self.preferenceManager = preferenceManager
    }

    func fetchNextNews() async {
        guard !isFetching else { return }
        isFetching = true
        fetchLogs = []
        
        let appendLog: (String) -> Void = { msg in
            self.fetchLogs.append(msg)
            self.statusMessage = msg
        }
        
        appendLog("🧹 清理历史冗余...")
        deleteOldNewsItems()
        
        appendLog("🚀 初始化 RSS 探针...")

        do {
            let sources = loadRSSSources()
            var allCandidates: [(title: String, summary: String, source: String, link: String, pubDate: Date, rawSource: RSSSource)] = []

            for source in sources {
                if let items = try? await fetchRSSItems(from: source) {
                    var added = 0
                    for item in items {   // 不再限制每源条数，全部交给 AI 评判
                        let urlHash = HashUtil.md5(item.link)
                        if !preferenceManager.isNewsSeen(urlHash: urlHash) {
                            allCandidates.append((
                                title: item.title,
                                summary: item.description,
                                source: item.source,
                                link: item.link,
                                pubDate: item.pubDate ?? Date(),
                                rawSource: source
                            ))
                            added += 1
                        }
                    }
                    appendLog("➤ 扫描 [\(source.name)]: 发现 \(added) 篇候选")
                } else {
                    appendLog("➤ 扫描 [\(source.name)]: 连接超时或被拒绝，跳过")
                }
            }

            guard !allCandidates.isEmpty else {
                appendLog("✅ 源数据收集完毕: 0 篇新候选推文")
                isFetching = false
                return
            }

            appendLog("✅ 源数据收集完毕，共发现 \(allCandidates.count) 篇候选文章")
            let profileSummary = preferenceManager.getCurrentProfileSummary() ?? "新用户，暂无偏好数据"
            let seenTitles = preferenceManager.getSeenTitles()

            // ── 第一阶段：只发标题给 AI 粗选（极低 token）──
            appendLog("🔍 [第1阶段] 发送 \(allCandidates.count) 个标题给 AI 粗筛...")
            let allTitles = allCandidates.map { $0.title }
            let preselectIndices = try await glmService.preselectByTitle(
                titles: allTitles,
                userProfile: profileSummary,
                seenTitles: seenTitles
            )

            guard !preselectIndices.isEmpty else {
                appendLog("✅ [第1阶段] AI 判定：无标题符合偏好，本次跳过。")
                isFetching = false
                return
            }

            let filteredCandidates = preselectIndices
                .filter { $0 >= 0 && $0 < allCandidates.count }
                .map { allCandidates[$0] }

            appendLog("✅ [第1阶段] 粗筛保留 \(filteredCandidates.count) 篇，进入精排...")

            // ── 第二阶段：携带完整摘要精排（高质量决策）──
            appendLog("🧠 [第2阶段] 发送完整摘要，进行精选与推荐理由生成...")
            let candidatesForAI = filteredCandidates.map { (title: $0.title, summary: $0.summary, source: $0.source) }
            let pickResults = try await glmService.pickBestNews(
                candidates: candidatesForAI,
                userProfile: profileSummary,
                seenTitles: seenTitles
            )

            if pickResults.isEmpty {
                appendLog("✅ [第2阶段] 精排后判定：暂无值得推送的内容，宁缺毋滥。")
                isFetching = false
                return
            }

            for pickResult in pickResults {
                guard pickResult.index >= 0 && pickResult.index < filteredCandidates.count else {
                    continue
                }

                let selected = filteredCandidates[pickResult.index]

                let newsItem = NewsItem(
                    title: selected.title,
                    summary: selected.summary,
                    content: "",
                    sourceURL: selected.link,
                    sourceName: selected.source,
                    publishedAt: selected.pubDate,
                    fetchedAt: Date(),
                    reasoning: pickResult.reasoning
                )
                modelContext.insert(newsItem)

                let urlHash = HashUtil.md5(selected.link)
                preferenceManager.markNewsSeen(urlHash: urlHash, title: selected.title)

                appendLog("🎉 精选成功：[\(selected.source)] \(selected.title)")
            }
            // 完成汇总
            let count = pickResults.filter { $0.index >= 0 && $0.index < filteredCandidates.count }.count
            appendLog("✅ 完成！本次为您精选了 \(count) 篇推文")
            statusMessage = "本次为您精选了 \(count) 篇推文 🎉"
        } catch {
            appendLog("❌ 获取失败：\(error.localizedDescription)")
            statusMessage = "获取失败：\(error.localizedDescription)"
        }

        isFetching = false
    }

    private func fetchRSSItems(from source: RSSSource) async throws -> [RSSItem] {
        guard let url = URL(string: source.url) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return []
        }
        return rssParser.parse(data: data, sourceName: source.name)
    }

    func loadRSSSources() -> [RSSSource] {
        RSSSourceManager.shared.loadEnabledSources()
    }
    
    private func deleteOldNewsItems() {
        let fetchDescriptor = FetchDescriptor<NewsItem>()
        if let items = try? modelContext.fetch(fetchDescriptor) {
            let thresholdDate = Date().addingTimeInterval(-7 * 24 * 3600)
            var deletedCount = 0
            for item in items {
                if item.fetchedAt < thresholdDate {
                    modelContext.delete(item)
                    deletedCount += 1
                }
            }
            if deletedCount > 0 {
                print("Deleted \(deletedCount) old news items.")
            }
        }
    }
}
