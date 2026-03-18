import Foundation

/// Metadata for a single saved transcript session (one .txt file from TranscriptLogger).
/// Only the header and line timestamps are read at init time; full body is loaded lazily.
struct TranscriptSession: Identifiable, Hashable, Sendable {
    let id: String          // filename without extension, e.g. "2026-03-18_14-30"
    let fileName: String    // full filename, e.g. "2026-03-18_14-30.txt"
    let filePath: URL
    let date: Date
    let durationSeconds: Int   // derived from first/last [HH:mm:ss] line; 0 if unparseable
    let utteranceCount: Int    // count of lines matching "^\[" pattern

    private static let stemFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm"
        return fmt
    }()

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "[HH:mm:ss]"
        return fmt
    }()

    private static let displayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }()

    /// Parse a TranscriptSession from a .txt file URL.
    /// Returns nil if the filename doesn't match the expected pattern.
    static func parse(from url: URL) -> TranscriptSession? {
        let fileName = url.lastPathComponent
        guard fileName.hasSuffix(".txt") else { return nil }
        let stem = String(fileName.dropLast(4)) // "yyyy-MM-dd_HH-mm"

        guard let date = stemFormatter.date(from: stem) else { return nil }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return TranscriptSession(
                id: stem, fileName: fileName, filePath: url,
                date: date, durationSeconds: 0, utteranceCount: 0
            )
        }

        let lines = content.components(separatedBy: "\n")
        let timestampLines = lines.filter { $0.hasPrefix("[") && $0.count > 9 }
        let utteranceCount = timestampLines.count

        var durationSeconds = 0
        if let first = timestampLines.first, let last = timestampLines.last, first != last {
            let firstToken = String(first.prefix(10))
            let lastToken  = String(last.prefix(10))
            if let t1 = timeFormatter.date(from: firstToken), let t2 = timeFormatter.date(from: lastToken) {
                durationSeconds = max(0, Int(t2.timeIntervalSince(t1)))
            }
        }

        return TranscriptSession(
            id: stem, fileName: fileName, filePath: url,
            date: date, durationSeconds: durationSeconds, utteranceCount: utteranceCount
        )
    }

    /// Human-readable duration string, e.g. "12m 34s" or "45s".
    var durationDisplay: String {
        guard durationSeconds > 0 else { return "—" }
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    /// Human-readable date string for the session list row.
    var dateDisplay: String {
        Self.displayFormatter.string(from: date)
    }
}
