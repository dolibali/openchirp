import Foundation

struct GLMConfig {
    static var apiKey: String {
        AIConfigManager.shared.activeProfile?.apiKey ?? ""
    }
    static var baseURL: String {
        AIConfigManager.shared.activeProfile?.baseURL ?? "https://open.bigmodel.cn/api/coding/paas/v4"
    }
    static var model: String {
        AIConfigManager.shared.activeProfile?.model ?? "GLM-4.7-FlashX"
    }
}

class GLMService {
    private let session = URLSession.shared
    private func callAPI(
        systemPrompt: String,
        userMessage: String,
        tools: [[String: Any]]? = nil
    ) async throws -> [String: Any] {
        let messages: [[String: String]] = [
            ["role": "system", "content": SystemPrompts.base + "\n\n" + systemPrompt],
            ["role": "user", "content": userMessage]
        ]

        var body: [String: Any] = [
            "model": GLMConfig.model,
            "messages": messages
        ]
        if let tools { body["tools"] = tools }

        let rawURL = GLMConfig.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullURL = rawURL.hasSuffix("/chat/completions") ? rawURL : rawURL + "/chat/completions"

        var request = URLRequest(url: URL(string: fullURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(GLMConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // 两阶段漏斗各需约 30-40s，总超时设 300s 保证复杂场景不超时
        request.timeoutInterval = 300

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GLMError.invalidResponse(detail: "无 HTTP Response")
        }
        if !(200...299).contains(httpResponse.statusCode) {
            let rawError = String(data: data, encoding: .utf8) ?? "无法解析的非UTF8数据"
            print("GLM ERROR RAW RESPONSE: \(rawError)")
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let msg = error["message"] as? String {
                throw GLMError.apiError(statusCode: httpResponse.statusCode, message: "\(msg) \n(裸数据: \(rawError))")
            }
            throw GLMError.apiError(statusCode: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode)\n(裸数据: \(rawError))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let rawData = String(data: data, encoding: .utf8) ?? ""
            throw GLMError.invalidResponse(detail: "JSON解析失败，裸数据：\(rawData)")
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            let rawData = String(data: data, encoding: .utf8) ?? ""
            throw GLMError.invalidResponse(detail: "Choices空或字段缺失，裸数据：\(rawData)")
        }
        return message
    }

    private func extractToolCall(_ response: [String: Any], toolName: String) throws -> [String: Any] {
        guard let toolCalls = response["tool_calls"] as? [[String: Any]],
              let firstCall = toolCalls.first,
              let function = firstCall["function"] as? [String: Any],
              let argsStr = function["arguments"] as? String else {
            throw GLMError.noToolCall
        }
        guard let argsData = argsStr.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            throw GLMError.invalidToolArgs
        }
        return args
    }

    func updateProfile(
        currentProfile: String?,
        recentFeedbacks: [(action: String, textFeedback: String?, newsTitle: String, newsSummary: String)]
    ) async throws -> String {
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "update_profile",
                    "description": "更新结构化用户偏好画像",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "profile_summary": ["type": "string", "description": "包含核心偏好、近期追踪、避雷不看的结构化画像文本"]
                        ],
                        "required": ["profile_summary"]
                    ]
                ]
            ]
        ]

        var feedbackList = ""
        for (i, fb) in recentFeedbacks.enumerated() {
            feedbackList += "反馈\(i + 1)："
            if fb.action == "like" {
                feedbackList += "点赞强烈推荐"
            } else if fb.action == "neutral" {
                feedbackList += "一般(已阅但反响平平)"
            } else if fb.action == "dislike" {
                feedbackList += "点踩极度反感"
            } else {
                feedbackList += "跳过"
            }
            if let text = fb.textFeedback, !text.isEmpty {
                feedbackList += "\n  【显式文字反馈（最高优先级）】：\(text)"
            }
            feedbackList += "\n  推文：\(fb.newsTitle)"
            feedbackList += "\n  摘要：\(fb.newsSummary.prefix(80))\n\n"
        }

        let previousProfile = currentProfile ?? "（新用户，暂无画像）"

        let userMessage = """
        当前用户画像：\(previousProfile)

        最近反馈记录：
        \(feedbackList)

        注意：如果某条记录里带有“显式文字反馈（最高优先级）”，请优先依据该文字反馈理解用户真实意图。

        请结合当前画像和最新反馈，输出更新后的结构化用户偏好画像。
        """

        let response = try await callAPI(
            systemPrompt: SystemPrompts.updateProfile,
            userMessage: userMessage,
            tools: tools
        )

        let args = try extractToolCall(response, toolName: "update_profile")
        guard let summary = args["profile_summary"] as? String else {
            throw GLMError.invalidToolArgs
        }
        return summary
    }

    func rebuildProfileFromHistory(
        allFeedbacks: [(action: String, textFeedback: String?, newsTitle: String, newsSummary: String)]
    ) async throws -> String {
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "update_profile",
                    "description": "基于全部历史反馈重建结构化用户偏好画像",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "profile_summary": ["type": "string", "description": "包含核心偏好、近期追踪、避雷不看的结构化画像文本"]
                        ],
                        "required": ["profile_summary"]
                    ]
                ]
            ]
        ]

        var feedbackList = ""
        for (i, fb) in allFeedbacks.enumerated() {
            feedbackList += "历史反馈\(i + 1)："
            if fb.action == "like" {
                feedbackList += "点赞强烈推荐"
            } else if fb.action == "neutral" {
                feedbackList += "一般(已阅但反响平平)"
            } else if fb.action == "dislike" {
                feedbackList += "点踩极度反感"
            } else {
                feedbackList += "跳过"
            }
            if let text = fb.textFeedback, !text.isEmpty {
                feedbackList += "\n  【显式文字反馈（最高优先级）】：\(text)"
            }
            feedbackList += "\n  推文：\(fb.newsTitle)"
            feedbackList += "\n  摘要：\(fb.newsSummary.prefix(80))\n\n"
        }

        let userMessage = """
        下面是用户的全部历史反馈记录（按时间顺序排列，从早到晚）：

        \(feedbackList)

        请忽略旧画像，直接基于这些完整历史反馈重建一版新的结构化用户画像。
        要兼顾：
        1. 从全部历史里抽取长期稳定的核心偏好
        2. 从较新的反馈里提取近期追踪
        3. 从全部历史里总结稳定的避雷不看
        4. 如果有显式文字反馈，优先以文字反馈为准
        """

        let response = try await callAPI(
            systemPrompt: SystemPrompts.updateProfile,
            userMessage: userMessage,
            tools: tools
        )

        let args = try extractToolCall(response, toolName: "update_profile")
        guard let summary = args["profile_summary"] as? String else {
            throw GLMError.invalidToolArgs
        }
        return summary
    }
    
    func updateProfileDirectly(currentProfile: String?, userInstruction: String) async throws -> String {
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "update_profile",
                    "description": "更新结构化用户偏好画像",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "profile_summary": ["type": "string", "description": "包含核心偏好、近期追踪、避雷不看的结构化画像文本"]
                        ],
                        "required": ["profile_summary"]
                    ]
                ]
            ]
        ]
        
        let previousProfile = currentProfile ?? "（新用户，暂无画像）"
        let userMessage = """
        当前用户画像：\(previousProfile)

        用户的直接修正指令：
        "\(userInstruction)"

        请听从用户的修正指令，输出更新后的结构化用户偏好画像。
        """
        
        let response = try await callAPI(
            systemPrompt: SystemPrompts.updateProfileDirectly,
            userMessage: userMessage,
            tools: tools
        )

        let args = try extractToolCall(response, toolName: "update_profile")
        guard let summary = args["profile_summary"] as? String else {
            throw GLMError.invalidToolArgs
        }
        return summary
    }

    // MARK: - 两阶段漏斗：第一阶段，仅传标题做粗选
    func preselectByTitle(
        titles: [String],
        userProfile: String,
        seenTitles: [String]
    ) async throws -> [Int] {
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "preselect_titles",
                    "description": "返回通过初筛的推文索引列表",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "selected_indices": [
                                "type": "array",
                                "items": ["type": "integer"],
                                "description": "通过初筛的候选索引列表（从0开始）"
                            ]
                        ],
                        "required": ["selected_indices"]
                    ]
                ]
            ]
        ]

        var titleList = ""
        for (i, title) in titles.enumerated() {
            titleList += "[\(i)] \(title)\n"
        }
        let seenList = seenTitles.isEmpty ? "（暂无）" : seenTitles.prefix(30).joined(separator: "\n")

        let userMessage = """
        用户偏好画像：\(userProfile)

        近期已看过（避免重复）：
        \(seenList)

        候选推文标题（共 \(titles.count) 条）：
        \(titleList)

        请快速过滤出值得进一步了解的标题索引，排除与偏好无关或触碰雷区的。
        """

        let response = try await callAPI(
            systemPrompt: SystemPrompts.preselectByTitle,
            userMessage: userMessage,
            tools: tools
        )

        let args = try extractToolCall(response, toolName: "preselect_titles")
        guard let indices = args["selected_indices"] as? [Int] else {
            throw GLMError.invalidToolArgs
        }
        return indices
    }

    func pickBestNews(
        candidates: [(title: String, summary: String, source: String)],
        userProfile: String,
        seenTitles: [String]
    ) async throws -> [(index: Int, reasoning: String)] {
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "pick_best_news",
                    "description": "从候选推文中选择最值得推荐的推文列表。宁缺毋滥，如果不符合偏好可以返回空列表。",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "selected_news": [
                                "type": "array",
                                "description": "选出的优质推文列表",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "selected_index": ["type": "integer", "description": "选中的候选推文索引(从0开始)"],
                                        "reasoning": ["type": "string", "description": "专属推荐理由，要求以 '💡 推荐理由：' 开头"]
                                    ],
                                    "required": ["selected_index", "reasoning"]
                                ]
                            ]
                        ],
                        "required": ["selected_news"]
                    ]
                ]
            ]
        ]

        var candidateList = ""
        for (i, c) in candidates.enumerated() {
            // 完整摘要传给 AI，不做截断，让模型充分理解内容再做判断
            candidateList += "[\(i)] \(c.title)\n摘要：\(c.summary)\n来源：\(c.source)\n\n"
        }

        let seenList = seenTitles.isEmpty ? "（暂无历史记录）" : seenTitles.prefix(50).joined(separator: "\n")

        let userMessage = """
        当前用户偏好画像：\(userProfile)

        已看过的推文标题（避免重复推荐）：
        \(seenList)

        候选推文（共 \(candidates.count) 条，请综合标题和摘要判断）：
        \(candidateList)

        请根据用户偏好，精选最值得推荐的文章，给出个性化推荐理由。如果全部不符合偏好，返回空列表即可。
        """

        let response = try await callAPI(
            systemPrompt: SystemPrompts.pickNews,
            userMessage: userMessage,
            tools: tools
        )

        let args = try extractToolCall(response, toolName: "pick_best_news")
        guard let items = args["selected_news"] as? [[String: Any]] else {
            throw GLMError.invalidToolArgs
        }

        var results: [(index: Int, reasoning: String)] = []
        for item in items {
            if let index = item["selected_index"] as? Int,
               let reasoning = item["reasoning"] as? String {
                results.append((index: index, reasoning: reasoning))
            }
        }
        return results
    }
    func testConnection() async throws -> Bool {
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "test_success",
                    "description": "测试成功后调用此工具",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "status": ["type": "string", "description": "固定返回 OK"]
                        ],
                        "required": ["status"]
                    ]
                ]
            ]
        ]
        
        let response = try await callAPI(
            systemPrompt: "你是一个测试助手，你的唯一任务就是调用 test_success 工具。禁止用文字回复，禁止解释，只调用工具。",
            userMessage: "ping",
            tools: tools
        )
        
        do {
            let args = try extractToolCall(response, toolName: "test_success")
            guard let status = args["status"] as? String, status == "OK" else {
                throw GLMError.invalidToolArgs
            }
            return true
        } catch GLMError.noToolCall {
            throw GLMError.functionCallingUnsupported(modelName: GLMConfig.model)
        }
    }
}

enum GLMError: LocalizedError {
    case invalidResponse(detail: String)
    case noToolCall
    case invalidToolArgs
    case apiError(statusCode: Int, message: String)
    case functionCallingUnsupported(modelName: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let info): return "API 返回格式异常: \(info)"
        case .noToolCall: return "模型未调用预期的工具，请检查模型是否支持 Function Calling"
        case .invalidToolArgs: return "模型返回的工具参数格式异常"
        case .apiError(let code, let msg): return "API 错误(\(code)): \(msg)"
        case .functionCallingUnsupported(let model): return "当前模型「\(model)」不支持工具调用（Function Calling），请切换到支持 Function Calling 的模型。建议使用 GLM-4 系列。"
        }
    }
}
