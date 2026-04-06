import Foundation
import SwiftData
import Combine

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var selectedCategories: Set<String> = []
    @Published var selectedStyle: String? = nil

    let categories = [
        "科技", "财经", "体育", "娱乐", "国际",
        "国内", "职场", "情感", "搞笑", "汽车",
        "房产", "科普", "军事", "健康", "教育"
    ]
    let styles = [
        "深度长文", "轻松幽默", "资讯快报", "数据分析",
        "主观评论", "大V观点", "一图读懂", "视频解说"
    ]

    private let preferenceManager: PreferenceManager

    init(preferenceManager: PreferenceManager) {
        self.preferenceManager = preferenceManager
    }

    func toggleCategory(_ cat: String) {
        if selectedCategories.contains(cat) {
            selectedCategories.remove(cat)
        } else {
            selectedCategories.insert(cat)
        }
    }

    func savePreferences() {
        let styleStr = selectedStyle != nil ? "，偏好的风格是：\(selectedStyle!)" : ""
        let summary = "用户初始兴趣：" + Array(selectedCategories).joined(separator: "、") + styleStr
        preferenceManager.saveProfile(summary: summary)
    }
}
