import Foundation
import OSLog

enum DiagnosticLogLevel: String, Codable {
    case info
    case warning
    case error
}

struct DiagnosticLogEntry: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let level: DiagnosticLogLevel
    let domain: String
    let message: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        level: DiagnosticLogLevel,
        domain: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.level = level
        self.domain = domain
        self.message = message
        self.metadata = metadata
    }
}

final class DiagnosticLogStore {
    static let shared = DiagnosticLogStore()

    private let queue = DispatchQueue(label: "com.openchirp.diagnostic-log-store")
    private let maxEntries = 500
    private let retentionInterval: TimeInterval = 7 * 24 * 60 * 60
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Diagnostics", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("diagnostic_logs.json")
        prune()
    }

    func append(_ entry: DiagnosticLogEntry) {
        queue.sync {
            var entries = loadEntriesLocked()
            entries.append(entry)
            entries = pruneEntries(entries)
            saveEntriesLocked(entries)
        }
    }

    func entries() -> [DiagnosticLogEntry] {
        queue.sync {
            pruneLocked()
            return loadEntriesLocked().sorted { $0.createdAt > $1.createdAt }
        }
    }

    func clear() {
        queue.sync {
            saveEntriesLocked([])
        }
    }

    func prune() {
        queue.sync {
            pruneLocked()
        }
    }

    private func pruneLocked() {
        let entries = pruneEntries(loadEntriesLocked())
        saveEntriesLocked(entries)
    }

    private func pruneEntries(_ entries: [DiagnosticLogEntry]) -> [DiagnosticLogEntry] {
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        let filtered = entries
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
        return Array(filtered.prefix(maxEntries))
    }

    private func loadEntriesLocked() -> [DiagnosticLogEntry] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        do {
            return try JSONDecoder().decode([DiagnosticLogEntry].self, from: data)
        } catch {
            return []
        }
    }

    private func saveEntriesLocked(_ entries: [DiagnosticLogEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Ignore file write failures here to avoid recursive logging loops.
        }
    }
}

final class AppDiagnosticsLogger {
    static let shared = AppDiagnosticsLogger()

    private let logger = Logger(subsystem: "com.openchirp.app", category: "diagnostics")
    private let store: DiagnosticLogStore

    init(store: DiagnosticLogStore = .shared) {
        self.store = store
        store.prune()
    }

    func info(domain: String, message: String, metadata: [String: String] = [:]) {
        log(level: .info, domain: domain, message: message, metadata: metadata)
    }

    func warning(domain: String, message: String, metadata: [String: String] = [:]) {
        log(level: .warning, domain: domain, message: message, metadata: metadata)
    }

    func error(domain: String, message: String, metadata: [String: String] = [:]) {
        log(level: .error, domain: domain, message: message, metadata: metadata)
    }

    func prune() {
        store.prune()
    }

    func entries() -> [DiagnosticLogEntry] {
        store.entries()
    }

    func clear() {
        store.clear()
    }

    private func log(level: DiagnosticLogLevel, domain: String, message: String, metadata: [String: String]) {
        store.prune()

        let entry = DiagnosticLogEntry(
            level: level,
            domain: domain,
            message: message,
            metadata: metadata
        )

        let metadataDescription = metadata.isEmpty
            ? ""
            : " | " + metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
        let composedMessage = "[\(domain)] \(message)\(metadataDescription)"

        switch level {
        case .info:
            logger.info("\(composedMessage, privacy: .public)")
        case .warning:
            logger.warning("\(composedMessage, privacy: .public)")
        case .error:
            logger.error("\(composedMessage, privacy: .public)")
        }

        store.append(entry)
    }
}
