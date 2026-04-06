import SwiftUI

struct AgentStatusPill {
    static func stepPhrase(from logs: [String]) -> String {
        guard let last = logs.last else { return "准备就绪" }
        if last.contains("精选成功") || last.contains("完成") { return "已完成精选" }
        if last.contains("跳过") || last.contains("暂无值得") || last.contains("无标题符合") { return "本次无推荐" }
        if last.contains("获取失败") || last.contains("❌") { return "请求出现错误" }
        if last.contains("清理") { return "清理历史数据" }
        if last.contains("初始化") || last.contains("探针") { return "初始化中" }
        if last.contains("扫描") || last.contains("RSS") || last.contains("候选") { return "抓取 RSS 源" }
        if last.contains("源数据收集完毕") { return "数据收集完成" }
        if last.contains("第1阶段") || last.contains("粗筛") || last.contains("标题") { return "AI 粗筛标题中" }
        if last.contains("粗筛保留") { return "粗筛完成，进入精排" }
        if last.contains("第2阶段") || last.contains("精排") || last.contains("摘要") { return "AI 精选推文中" }
        return "运行中"
    }
}
