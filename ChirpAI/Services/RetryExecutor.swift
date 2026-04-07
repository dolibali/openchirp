import Foundation

struct RetryPolicy {
    let maxRetries: Int
    let retryDelays: [TimeInterval]

    static let standard = RetryPolicy(
        maxRetries: 2,
        retryDelays: [0.8, 1.6]
    )
}

enum RetryableRequestError: LocalizedError {
    case httpStatus(code: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let body):
            return "HTTP \(code): \(body)"
        }
    }
}

enum RetryExecutor {
    static func execute<T>(
        policy: RetryPolicy = .standard,
        stage: String,
        url: URL?,
        logger: AppDiagnosticsLogger? = .shared,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0

        while true {
            do {
                return try await operation()
            } catch {
                let shouldRetry = attempt < policy.maxRetries && isRetryable(error)
                let metadata = retryMetadata(
                    stage: stage,
                    attempt: attempt + 1,
                    url: url,
                    error: error
                )

                if shouldRetry {
                    logger?.warning(
                        domain: "network",
                        message: "请求失败，准备重试",
                        metadata: metadata
                    )
                    let delay = policy.retryDelays[safe: attempt] ?? policy.retryDelays.last ?? 0.8
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                logger?.error(
                    domain: "network",
                    message: "请求最终失败",
                    metadata: metadata
                )
                throw error
            }
        }
    }

    static func isRetryable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }

        if case RetryableRequestError.httpStatus(let code, _) = error {
            return (500...599).contains(code)
        }

        return false
    }

    private static func retryMetadata(stage: String, attempt: Int, url: URL?, error: Error) -> [String: String] {
        var metadata: [String: String] = [
            "stage": stage,
            "attempt": "\(attempt)"
        ]

        if let url {
            metadata["url"] = url.absoluteString
            metadata["host"] = url.host ?? ""
        }

        if let urlError = error as? URLError {
            metadata["error_code"] = "\(urlError.code.rawValue)"
        } else if case RetryableRequestError.httpStatus(let code, _) = error {
            metadata["error_code"] = "\(code)"
        } else {
            metadata["error_code"] = String(describing: error)
        }

        return metadata
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
