import Foundation

/// Persists session transcripts as JSONL files with metadata sidecars.
actor SessionStore {
    private let sessionsDirectory: URL
    private var currentFile: URL?
    private var fileHandle: FileHandle?
    private let encoder = JSONEncoder()

    /// The filename stem of the current session (e.g. "session_2026-03-18_14-30-00").
    private(set) var currentSessionID: String?

    /// Tracks in-flight delayed writes.
    private var pendingWrites = 0
    private var pendingWriteWaiters: [CheckedContinuation<Void, Never>] = []

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        sessionsDirectory = appSupport.appendingPathComponent("OpenOats/sessions", isDirectory: true)

        try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        encoder.dateEncodingStrategy = .iso8601
    }

    func startSession(templateID: UUID? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stem = "session_\(formatter.string(from: Date()))"
        currentSessionID = stem
        let filename = "\(stem).jsonl"
        currentFile = sessionsDirectory.appendingPathComponent(filename)

        FileManager.default.createFile(atPath: currentFile!.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: currentFile!)
        fileHandle?.seekToEndOfFile()
    }

    func appendRecord(_ record: SessionRecord) {
        guard let fileHandle else { return }

        do {
            let data = try encoder.encode(record)
            fileHandle.write(data)
            fileHandle.write("\n".data(using: .utf8)!)
        } catch {
            print("SessionStore: failed to write record: \(error)")
        }
    }

    /// Pending records waiting for the 5-second enrichment window to close.
    private var pendingDelayedRecords: [(baseRecord: SessionRecord, suggestionEngine: SuggestionEngine?, transcriptStore: TranscriptStore?)] = []
    /// Single coalescing task — cancelled and rescheduled on each new utterance.
    private var delayedWriteTask: Task<Void, Never>?

    /// Coalesces delayed writes: cancels the previous timer on each new utterance,
    /// so at most 1 Task sleeps at a time. All records accumulated during the window
    /// are flushed together when the 5-second silence elapses.
    func appendRecordDelayed(
        baseRecord: SessionRecord,
        suggestionEngine: SuggestionEngine?,
        transcriptStore: TranscriptStore?
    ) {
        pendingWrites += 1
        pendingDelayedRecords.append((baseRecord, suggestionEngine, transcriptStore))
        delayedWriteTask?.cancel()
        delayedWriteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            await self.flushPendingDelayedRecords()
        }
    }

    private func flushPendingDelayedRecords() async {
        let records = pendingDelayedRecords
        pendingDelayedRecords.removeAll()
        for entry in records {
            let decision = await entry.suggestionEngine?.lastDecision
            let latestSuggestion = await entry.suggestionEngine?.suggestions.first
            let summary = await entry.transcriptStore?.conversationState.shortSummary

            let enrichedRecord = SessionRecord(
                speaker: entry.baseRecord.speaker,
                text: entry.baseRecord.text,
                timestamp: entry.baseRecord.timestamp,
                suggestions: latestSuggestion.map { [$0.text] },
                kbHits: latestSuggestion?.kbHits.map { $0.sourceFile },
                suggestionDecision: decision,
                surfacedSuggestionText: decision?.shouldSurface == true ? latestSuggestion?.text : nil,
                conversationStateSummary: summary?.isEmpty == false ? summary : nil
            )

            appendRecord(enrichedRecord)
            pendingWrites -= 1
            if pendingWrites == 0 {
                let waiters = pendingWriteWaiters
                pendingWriteWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
    }

    /// Force-flush all pending delayed records immediately (e.g., before session end).
    func forceFlushPendingWrites() async {
        delayedWriteTask?.cancel()
        delayedWriteTask = nil
        await flushPendingDelayedRecords()
    }

    /// Suspends until all in-flight delayed writes have completed.
    func awaitPendingWrites() async {
        guard pendingWrites > 0 else { return }
        // Force-flush immediately rather than waiting for the 5s timer
        await forceFlushPendingWrites()
    }

    func endSession() {
        try? fileHandle?.close()
        fileHandle = nil
        currentFile = nil
        currentSessionID = nil
    }

    // MARK: - Sidecar

    private func sidecarURL(for sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(sessionID).meta.json")
    }

    private func jsonlURL(for sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(sessionID).jsonl")
    }

    func writeSidecar(_ sidecar: SessionSidecar) {
        let url = sidecarURL(for: sidecar.index.id)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(sidecar)
            try data.write(to: url, options: .atomic)
        } catch {
            print("SessionStore: failed to write sidecar: \(error)")
        }
    }

    // MARK: - History

    func loadSessionIndex() -> [SessionIndex] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var indexMap: [String: SessionIndex] = [:]

        // Load from sidecar files
        for file in files where file.pathExtension == "json" && file.lastPathComponent.hasSuffix(".meta.json") {
            let stem = String(file.lastPathComponent.dropLast(".meta.json".count))
            guard let data = try? Data(contentsOf: file),
                  let sidecar = try? decoder.decode(SessionSidecar.self, from: data) else { continue }
            indexMap[stem] = sidecar.index
        }

        // Handle orphaned JSONL files
        for file in files where file.pathExtension == "jsonl" {
            let stem = file.deletingPathExtension().lastPathComponent
            guard indexMap[stem] == nil else { continue }

            // Parse date from filename: session_YYYY-MM-DD_HH-mm-ss
            let datePart = stem.replacingOccurrences(of: "session_", with: "")
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let startDate = fmt.date(from: datePart) ?? Date()

            // Count lines for utteranceCount
            let lineCount = (try? String(contentsOf: file, encoding: .utf8))?
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .count ?? 0

            indexMap[stem] = SessionIndex(
                id: stem,
                startedAt: startDate,
                title: nil,
                utteranceCount: lineCount,
                hasNotes: false
            )
        }

        return indexMap.values.sorted { $0.startedAt > $1.startedAt }
    }

    func loadTranscript(sessionID: String) -> [SessionRecord] {
        let url = jsonlURL(for: sessionID)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return content
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(SessionRecord.self, from: data)
            }
    }

    func loadNotes(sessionID: String) -> EnhancedNotes? {
        let url = sidecarURL(for: sessionID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let sidecar = try? decoder.decode(SessionSidecar.self, from: data) else { return nil }
        return sidecar.notes
    }

    func saveNotes(sessionID: String, notes: EnhancedNotes) {
        let url = sidecarURL(for: sessionID)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var sidecar: SessionSidecar
        if let data = try? Data(contentsOf: url),
           let existing = try? decoder.decode(SessionSidecar.self, from: data) {
            sidecar = existing
        } else {
            // Recover metadata from JSONL filename and content
            let datePart = sessionID.replacingOccurrences(of: "session_", with: "")
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let startDate = fmt.date(from: datePart) ?? Date()

            let jsonlFile = jsonlURL(for: sessionID)
            let lineCount = (try? String(contentsOf: jsonlFile, encoding: .utf8))?
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .count ?? 0

            sidecar = SessionSidecar(
                index: SessionIndex(
                    id: sessionID,
                    startedAt: startDate,
                    utteranceCount: lineCount,
                    hasNotes: false
                ),
                notes: nil
            )
        }

        sidecar.notes = notes
        let idx = sidecar.index
        sidecar = SessionSidecar(
            index: SessionIndex(
                id: idx.id,
                startedAt: idx.startedAt,
                endedAt: idx.endedAt,
                templateSnapshot: idx.templateSnapshot,
                title: idx.title,
                utteranceCount: idx.utteranceCount,
                hasNotes: true
            ),
            notes: notes
        )

        writeSidecar(sidecar)
    }

    var sessionsDirectoryURL: URL { sessionsDirectory }
}
