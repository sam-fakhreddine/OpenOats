import Foundation
import Observation

@Observable
@MainActor
final class HistoryStore {
    private(set) var sessions: [TranscriptSession] = []
    var searchText: String = ""

    /// Sorted newest-first, filtered by searchText (matches date string or filename).
    var filteredSessions: [TranscriptSession] {
        guard !searchText.isEmpty else { return sessions }
        let q = searchText.lowercased()
        return sessions.filter {
            $0.dateDisplay.lowercased().contains(q) ||
            $0.fileName.lowercased().contains(q)
        }
    }

    /// Scan directory for .txt transcript files and rebuild the session list.
    func load(from directory: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let fm = FileManager.default
            guard let urls = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            let loaded = urls
                .filter { $0.pathExtension == "txt" }
                .compactMap { TranscriptSession.parse(from: $0) }
                .sorted { $0.date > $1.date }

            await MainActor.run {
                self?.sessions = loaded
            }
        }
    }

    /// Load the full text content of a session file (called lazily when a session is selected).
    func loadContent(for session: TranscriptSession) async -> String {
        await Task.detached(priority: .userInitiated) {
            (try? String(contentsOf: session.filePath, encoding: .utf8)) ?? "(Could not read file)"
        }.value
    }

    /// Delete a session file from disk and remove it from the in-memory list.
    func delete(_ session: TranscriptSession) throws {
        try FileManager.default.removeItem(at: session.filePath)
        sessions.removeAll { $0.id == session.id }
    }
}
