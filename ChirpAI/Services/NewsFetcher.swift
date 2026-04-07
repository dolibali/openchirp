import Foundation
import SwiftData
import Combine
import UIKit

enum FetchStage: String {
    case idle
    case fetchingRSS
    case preselecting
    case ranking
    case interrupted
    case failed
}

private enum RecoverableAIStage: String {
    case preselecting
    case ranking
}

private struct CandidateArticle {
    let title: String
    let summary: String
    let source: String
    let link: String
    let pubDate: Date
}

private struct AIFetchRecoveryState {
    var stage: RecoverableAIStage
    let allCandidates: [CandidateArticle]
    var filteredCandidates: [CandidateArticle]
    let profileSummary: String
    let seenTitles: [String]
}

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
    @Published private(set) var currentStage: FetchStage = .idle

    private let modelContext: ModelContext
    private let preferenceManager: PreferenceManager
    private let glmService = GLMService()
    private let rssParser = RSSParser()
    private let diagnostics = AppDiagnosticsLogger.shared
    private let session: URLSession
    private var recoveryState: AIFetchRecoveryState?
    private var didEnterBackgroundDuringAIStage = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    init(modelContext: ModelContext, preferenceManager: PreferenceManager) {
        self.modelContext = modelContext
        self.preferenceManager = preferenceManager
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    func fetchNextNews() async {
        guard !isFetching else { return }
        prepareFreshFetch()

        appendLog("🧹 清理历史冗余...")
        deleteOldNewsItems()

        currentStage = .fetchingRSS
        appendLog("🚀 初始化 RSS 探针...")

        do {
            let sources = loadRSSSources()
            let lookbackDays = preferenceManager.getRSSFetchLookbackDays()
            let recentThresholdDate = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? .distantPast
            var allCandidates: [CandidateArticle] = []

            appendLog("🗓️ 抓取策略：只扫描最近 \(lookbackDays) 天的文章")

            for source in sources {
                do {
                    let items = try await fetchRSSItems(from: source)
                    var added = 0
                    var skippedOld = 0
                    for item in items {
                        let publishedAt = item.pubDate ?? Date()
                        guard publishedAt >= recentThresholdDate else {
                            skippedOld += 1
                            continue
                        }

                        let urlHash = HashUtil.md5(item.link)
                        if !preferenceManager.isNewsSeen(urlHash: urlHash) {
                            allCandidates.append(CandidateArticle(
                                title: item.title,
                                summary: item.description,
                                source: item.source,
                                link: item.link,
                                pubDate: publishedAt
                            ))
                            added += 1
                        }
                    }
                    if skippedOld > 0 {
                        appendLog("➤ 扫描 [\(source.name)]: 发现 \(added) 篇候选，过滤旧文 \(skippedOld) 篇")
                    } else {
                        appendLog("➤ 扫描 [\(source.name)]: 发现 \(added) 篇候选")
                    }
                } catch {
                    diagnostics.error(
                        domain: "network",
                        message: "RSS 源抓取失败",
                        metadata: [
                            "source_name": source.name,
                            "source_url": source.url,
                            "error": error.localizedDescription
                        ]
                    )
                    appendLog("➤ 扫描 [\(source.name)]: 连接超时或被拒绝，跳过")
                }
            }

            guard !allCandidates.isEmpty else {
                appendLog("✅ 源数据收集完毕: 0 篇新候选推文")
                finishFetch()
                return
            }

            appendLog("✅ 源数据收集完毕，共发现 \(allCandidates.count) 篇候选文章")
            let profileSummary = preferenceManager.getCurrentProfileSummary() ?? "新用户，暂无偏好数据"
            let seenTitles = preferenceManager.getSeenTitles()
            recoveryState = AIFetchRecoveryState(
                stage: .preselecting,
                allCandidates: allCandidates,
                filteredCandidates: [],
                profileSummary: profileSummary,
                seenTitles: seenTitles
            )
            startBackgroundProtectionIfNeeded()

            // ── 第一阶段：只发标题给 AI 粗选（极低 token）──
            let filteredCandidates = try await runPreselect(
                allCandidates: allCandidates,
                profileSummary: profileSummary,
                seenTitles: seenTitles
            )

            guard !filteredCandidates.isEmpty else {
                appendLog("✅ [第1阶段] AI 判定：无标题符合偏好，本次跳过。")
                finishFetch()
                return
            }

            appendLog("✅ [第1阶段] 粗筛保留 \(filteredCandidates.count) 篇，进入精排...")
            recoveryState?.stage = .ranking
            recoveryState?.filteredCandidates = filteredCandidates

            // ── 第二阶段：携带完整摘要精排（高质量决策）──
            let pickResults = try await runRanking(
                filteredCandidates: filteredCandidates,
                profileSummary: profileSummary,
                seenTitles: seenTitles
            )

            try finalizeRankingResults(pickResults, filteredCandidates: filteredCandidates)
            finishFetch()
        } catch {
            if handleInterruptedAIRequestIfNeeded(error) {
                return
            }

            currentStage = .failed
            diagnostics.error(
                domain: "network",
                message: "新闻抓取流程失败",
                metadata: [
                    "stage": currentStage.rawValue,
                    "error": error.localizedDescription
                ]
            )
            appendLog("❌ 获取失败：\(error.localizedDescription)")
            statusMessage = "获取失败：\(error.localizedDescription)"
            finishFetch(clearRecoveryState: true)
        }
    }

    func noteEnteredBackground() {
        guard isFetching, currentStage == .preselecting || currentStage == .ranking else { return }
        guard !didEnterBackgroundDuringAIStage else { return }
        didEnterBackgroundDuringAIStage = true
        appendLog("⏸️ 已切到后台，若本次 AI 请求被系统中断，回到前台后会自动从当前阶段恢复。")
    }

    func resumeInterruptedFetchIfNeeded() async -> Bool {
        guard !isFetching, currentStage == .interrupted, let recoveryState else { return false }

        didEnterBackgroundDuringAIStage = false
        isFetching = true
        startBackgroundProtectionIfNeeded()

        let stageDescription = recoveryState.stage == .preselecting ? "标题粗筛" : "精选重排"
        appendLog("🔄 已回到前台，正在恢复 AI \(stageDescription)...")

        do {
            switch recoveryState.stage {
            case .preselecting:
                let filteredCandidates = try await runPreselect(
                    allCandidates: recoveryState.allCandidates,
                    profileSummary: recoveryState.profileSummary,
                    seenTitles: recoveryState.seenTitles
                )

                guard !filteredCandidates.isEmpty else {
                    appendLog("✅ [第1阶段] AI 判定：无标题符合偏好，本次跳过。")
                    finishFetch()
                    return true
                }

                appendLog("✅ [第1阶段] 粗筛保留 \(filteredCandidates.count) 篇，进入精排...")
                self.recoveryState?.stage = .ranking
                self.recoveryState?.filteredCandidates = filteredCandidates

                let pickResults = try await runRanking(
                    filteredCandidates: filteredCandidates,
                    profileSummary: recoveryState.profileSummary,
                    seenTitles: recoveryState.seenTitles
                )
                try finalizeRankingResults(pickResults, filteredCandidates: filteredCandidates)

            case .ranking:
                let pickResults = try await runRanking(
                    filteredCandidates: recoveryState.filteredCandidates,
                    profileSummary: recoveryState.profileSummary,
                    seenTitles: recoveryState.seenTitles
                )
                try finalizeRankingResults(pickResults, filteredCandidates: recoveryState.filteredCandidates)
            }

            finishFetch()
        } catch {
            if handleInterruptedAIRequestIfNeeded(error) {
                return true
            }

            currentStage = .failed
            diagnostics.error(
                domain: "network",
                message: "恢复被中断的 AI 抓取流程失败",
                metadata: [
                    "stage": recoveryState.stage.rawValue,
                    "error": error.localizedDescription
                ]
            )
            appendLog("❌ 恢复失败：\(error.localizedDescription)")
            statusMessage = "恢复失败：\(error.localizedDescription)"
            finishFetch(clearRecoveryState: true)
        }

        return true
    }

    private func fetchRSSItems(from source: RSSSource) async throws -> [RSSItem] {
        guard let url = URL(string: source.url) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse) = try await RetryExecutor.execute(
            stage: "rss_fetch",
            url: url
        ) { [self, request] in
            let (data, response) = try await self.session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (500...599).contains(httpResponse.statusCode) {
                let rawError = String(data: data, encoding: .utf8) ?? "无法解析的非UTF8数据"
                throw RetryableRequestError.httpStatus(code: httpResponse.statusCode, body: rawError)
            }
            return (data, response)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return []
        }
        return rssParser.parse(data: data, sourceName: source.name)
    }

    func loadRSSSources() -> [RSSSource] {
        RSSSourceManager.shared.loadEnabledSources()
    }

    private func prepareFreshFetch() {
        isFetching = true
        fetchLogs = []
        statusMessage = ""
        currentStage = .idle
        recoveryState = nil
        didEnterBackgroundDuringAIStage = false
        endBackgroundProtectionIfNeeded()
    }

    private func appendLog(_ message: String) {
        fetchLogs.append(message)
        statusMessage = message
    }

    private func runPreselect(
        allCandidates: [CandidateArticle],
        profileSummary: String,
        seenTitles: [String]
    ) async throws -> [CandidateArticle] {
        currentStage = .preselecting
        appendLog("🔍 [第1阶段] 发送 \(allCandidates.count) 个标题给 AI 粗筛...")

        let allTitles = allCandidates.map { $0.title }
        let preselectIndices = try await glmService.preselectByTitle(
            titles: allTitles,
            userProfile: profileSummary,
            seenTitles: seenTitles
        )

        return preselectIndices
            .filter { $0 >= 0 && $0 < allCandidates.count }
            .map { allCandidates[$0] }
    }

    private func runRanking(
        filteredCandidates: [CandidateArticle],
        profileSummary: String,
        seenTitles: [String]
    ) async throws -> [(index: Int, reasoning: String)] {
        currentStage = .ranking
        appendLog("🧠 [第2阶段] 发送完整摘要，进行精选与推荐理由生成...")

        let candidatesForAI = filteredCandidates.map { (title: $0.title, summary: $0.summary, source: $0.source) }
        return try await glmService.pickBestNews(
            candidates: candidatesForAI,
            userProfile: profileSummary,
            seenTitles: seenTitles
        )
    }

    private func finalizeRankingResults(
        _ pickResults: [(index: Int, reasoning: String)],
        filteredCandidates: [CandidateArticle]
    ) throws {
        if pickResults.isEmpty {
            appendLog("✅ [第2阶段] 精排后判定：暂无值得推送的内容，宁缺毋滥。")
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

        do {
            try modelContext.save()
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "保存精选新闻失败",
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }

        let count = pickResults.filter { $0.index >= 0 && $0.index < filteredCandidates.count }.count
        appendLog("✅ 完成！本次为您精选了 \(count) 篇推文")
        statusMessage = "本次为您精选了 \(count) 篇推文 🎉"
    }

    private func handleInterruptedAIRequestIfNeeded(_ error: Error) -> Bool {
        guard didEnterBackgroundDuringAIStage,
              recoveryState != nil,
              currentStage == .preselecting || currentStage == .ranking,
              isRecoverableBackgroundInterruption(error) else {
            return false
        }

        let stageText = currentStage == .preselecting ? "标题粗筛" : "精选重排"
        diagnostics.warning(
            domain: "network",
            message: "AI 请求在后台切换后被中断，等待回前台恢复",
            metadata: [
                "stage": currentStage.rawValue,
                "error": error.localizedDescription
            ]
        )
        currentStage = .interrupted
        appendLog("⏸️ \(stageText) 在后台被系统中断，回到前台后会自动从当前阶段继续。")
        finishFetch(clearRecoveryState: false, resetStageToIdle: false)

        if UIApplication.shared.applicationState == .active {
            appendLog("🔄 检测到应用已经回到前台，正在立即恢复当前 AI 阶段...")
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.resumeInterruptedFetchIfNeeded()
            }
        }

        return true
    }

    private func isRecoverableBackgroundInterruption(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    private func startBackgroundProtectionIfNeeded() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "openchirp-ai-fetch") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.appendLog("⏱️ 后台继续执行时间已用尽，若请求被中断，回到前台后会自动恢复。")
                self.endBackgroundProtectionIfNeeded()
            }
        }
    }

    private func endBackgroundProtectionIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func finishFetch(clearRecoveryState: Bool = true, resetStageToIdle: Bool = true) {
        isFetching = false
        didEnterBackgroundDuringAIStage = false
        endBackgroundProtectionIfNeeded()
        if clearRecoveryState {
            recoveryState = nil
        }
        if resetStageToIdle {
            currentStage = .idle
        }
    }

    private func deleteOldNewsItems() {
        let fetchDescriptor = FetchDescriptor<NewsItem>()
        do {
            let items = try modelContext.fetch(fetchDescriptor)
            let thresholdDate = Date().addingTimeInterval(-7 * 24 * 3600)
            var deletedCount = 0
            for item in items {
                if item.fetchedAt < thresholdDate {
                    modelContext.delete(item)
                    deletedCount += 1
                }
            }
            if deletedCount > 0 {
                try modelContext.save()
                diagnostics.info(
                    domain: "storage",
                    message: "已清理过期新闻缓存",
                    metadata: ["deleted_count": "\(deletedCount)"]
                )
            }
        } catch {
            diagnostics.error(
                domain: "storage",
                message: "清理旧新闻缓存失败",
                metadata: ["error": error.localizedDescription]
            )
        }
    }
}
