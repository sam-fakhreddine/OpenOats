import Foundation

// MARK: - Mock Session Repository

/// Mock implementation of SessionRepositoryProtocol for testing.
@available(macOS 15.0, *)
public actor MockSessionRepository: SessionRepositoryProtocol {
    private var sessions: [SessionID: Session] = [:]
    private var statistics: SessionStorageStats
    
    public init(
        statistics: SessionStorageStats = SessionStorageStats(
            totalSessions: 0,
            totalAudioDuration: .zero,
            totalStorageSize: 0,
            oldestSession: nil,
            newestSession: nil
        )
    ) {
        self.statistics = statistics
    }
    
    public func save(_ session: Session) async -> Result<Void, StorageError> {
        sessions[session.id] = session
        updateStatistics()
        return .success(())
    }
    
    public func get(by id: SessionID) async -> Result<Session, StorageError> {
        guard let session = sessions[id] else {
            return .failure(.notFound(entity: "Session", id: id.rawValue.uuidString))
        }
        return .success(session)
    }
    
    public func getSessions(for meetingID: MeetingID) async -> Result<[Session], StorageError> {
        let matchingSessions = sessions.values.filter { $0.meetingID == meetingID }
        return .success(Array(matchingSessions))
    }
    
    public func list(query: SessionQuery) async -> Result<[Session], StorageError> {
        var result = Array(sessions.values)
        
        if let meetingID = query.meetingID {
            result = result.filter { $0.meetingID == meetingID }
        }
        
        if let dateRange = query.dateRange {
            result = result.filter { dateRange.contains($0.startTime) }
        }
        
        // Sort
        switch query.sortBy {
        case .startTime:
            result.sort { query.sortOrder == .ascending ? $0.startTime < $1.startTime : $0.startTime > $1.startTime }
        case .duration:
            result.sort { query.sortOrder == .ascending ? ($0.duration ?? 0) < ($1.duration ?? 0) : ($0.duration ?? 0) > ($1.duration ?? 0) }
        case .title:
            // Sessions don't have titles, fall back to startTime
            result.sort { query.sortOrder == .ascending ? $0.startTime < $1.startTime : $0.startTime > $1.startTime }
        }
        
        if let limit = query.limit {
            result = Array(result.prefix(limit))
        }
        
        return .success(result)
    }
    
    public func delete(id: SessionID) async -> Result<Void, StorageError> {
        guard sessions.removeValue(forKey: id) != nil else {
            return .failure(.notFound(entity: "Session", id: id.rawValue.uuidString))
        }
        updateStatistics()
        return .success(())
    }
    
    public func exists(id: SessionID) async -> Bool {
        return sessions[id] != nil
    }
    
    public func count() async -> Int {
        return sessions.count
    }
    
    public func getStatistics() async -> SessionStorageStats {
        return statistics
    }
    
    // MARK: - Private Helpers
    
    private func updateStatistics() {
        let totalSessions = sessions.count
        let oldestSession = sessions.values.map { $0.startTime }.min()
        let newestSession = sessions.values.map { $0.startTime }.max()
        
        statistics = SessionStorageStats(
            totalSessions: totalSessions,
            totalAudioDuration: .zero,
            totalStorageSize: Int64(totalSessions * 1024 * 1024),
            oldestSession: oldestSession,
            newestSession: newestSession
        )
    }
    
    // MARK: - Test Helpers
    
    public func preloadSessions(_ sessions: [Session]) {
        for session in sessions {
            self.sessions[session.id] = session
        }
        updateStatistics()
    }
    
    public func clear() {
        sessions.removeAll()
        updateStatistics()
    }
}

// MARK: - Mock Transcript Repository

/// Mock implementation of TranscriptRepository for testing.
@available(macOS 15.0, *)
public actor MockTranscriptRepository: TranscriptRepository {
    private var transcripts: [TranscriptID: Transcript] = [:]
    private var getForSessionResult: Result<Transcript?, StorageError>?
    private var searchResults: [String: [Transcript]] = [:]
    private var exportResults: [TranscriptID: Result<URL, StorageError>] = [:]
    
    public init() {}
    
    public func save(_ transcript: Transcript) async -> Result<Void, StorageError> {
        transcripts[transcript.id] = transcript
        return .success(())
    }
    
    public func get(by id: TranscriptID) async -> Result<Transcript, StorageError> {
        guard let transcript = transcripts[id] else {
            return .failure(.notFound(entity: "Transcript", id: id.rawValue.uuidString))
        }
        return .success(transcript)
    }
    
    public func getTranscript(for sessionID: SessionID) async -> Result<Transcript?, StorageError> {
        if let result = getForSessionResult {
            return result
        }
        
        let transcript = transcripts.values.first { $0.sessionID == sessionID }
        return .success(transcript)
    }
    
    public func search(query: String, meetingID: MeetingID?) async -> Result<[Transcript], StorageError> {
        if let results = searchResults[query] {
            return .success(results)
        }
        
        // Simple mock search: return all transcripts if query is not empty
        let results = query.isEmpty ? [] : Array(transcripts.values)
        return .success(results)
    }
    
    public func delete(id: TranscriptID) async -> Result<Void, StorageError> {
        guard transcripts.removeValue(forKey: id) != nil else {
            return .failure(.notFound(entity: "Transcript", id: id.rawValue.uuidString))
        }
        return .success(())
    }
    
    public func export(
        transcriptID: TranscriptID,
        format: TranscriptExportFormat
    ) async -> Result<URL, StorageError> {
        if let result = exportResults[transcriptID] {
            return result
        }
        
        let exportURL = URL(fileURLWithPath: "/tmp/export_\(transcriptID.rawValue.uuidString).\(format.rawValue)")
        return .success(exportURL)
    }
    
    // MARK: - Test Helpers
    
    public func preloadTranscripts(_ transcripts: [Transcript]) {
        for transcript in transcripts {
            self.transcripts[transcript.id] = transcript
        }
    }
    
    public func setGetForSessionResult(_ result: Result<Transcript?, StorageError>) {
        self.getForSessionResult = result
    }
    
    public func setSearchResults(_ results: [Transcript], for query: String) {
        self.searchResults[query] = results
    }
    
    public func setExportResult(_ result: Result<URL, StorageError>, for transcriptID: TranscriptID) {
        self.exportResults[transcriptID] = result
    }
    
    public func clear() {
        transcripts.removeAll()
        searchResults.removeAll()
        exportResults.removeAll()
    }
}

// MARK: - Mock Settings Repository

/// Mock implementation of SettingsRepository for testing.
@available(macOS 15.0, *)
public actor MockSettingsRepository: SettingsRepository {
    private var settings: [SettingsKey: Any] = [:]
    private var observers: [SettingsKey: [SettingsObserverToken: @Sendable () -> Void]] = [:]
    
    public init() {
        // Set default values
        resetToDefaults()
    }
    
    public func string(for key: SettingsKey) -> String? {
        return settings[key] as? String
    }
    
    public func bool(for key: SettingsKey) -> Bool {
        return settings[key] as? Bool ?? false
    }
    
    public func integer(for key: SettingsKey) -> Int {
        return settings[key] as? Int ?? 0
    }
    
    public func double(for key: SettingsKey) -> Double {
        return settings[key] as? Double ?? 0.0
    }
    
    public func data(for key: SettingsKey) -> Data? {
        return settings[key] as? Data
    }
    
    public func codable<T: Codable & Sendable>(for key: SettingsKey) -> T? {
        guard let data = settings[key] as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    public func set(_ value: String?, for key: SettingsKey) {
        settings[key] = value
        notifyObservers(for: key)
    }
    
    public func set(_ value: Bool, for key: SettingsKey) {
        settings[key] = value
        notifyObservers(for: key)
    }
    
    public func set(_ value: Int, for key: SettingsKey) {
        settings[key] = value
        notifyObservers(for: key)
    }
    
    public func set(_ value: Double, for key: SettingsKey) {
        settings[key] = value
        notifyObservers(for: key)
    }
    
    public func set(_ value: Data?, for key: SettingsKey) {
        settings[key] = value
        notifyObservers(for: key)
    }
    
    public func set<T: Codable & Sendable>(_ value: T?, for key: SettingsKey) {
        if let value = value {
            settings[key] = try? JSONEncoder().encode(value)
        } else {
            settings[key] = nil
        }
        notifyObservers(for: key)
    }
    
    public func remove(key: SettingsKey) {
        settings[key] = nil
        notifyObservers(for: key)
    }
    
    public func resetToDefaults() {
        settings.removeAll()
        settings[.autoStartRecording] = false
        settings[.enableSpeakerDiarization] = false
        settings[.enableAISummaries] = false
        settings[.showConfidenceScores] = false
        settings[.enableCloudSync] = false
        settings[.storageLimit] = 0
    }
    
    public func addObserver(for key: SettingsKey, callback: @Sendable @escaping () -> Void) -> SettingsObserverToken {
        let token = SettingsObserverToken()
        if observers[key] == nil {
            observers[key] = [:]
        }
        observers[key]?[token] = callback
        return token
    }
    
    public func removeObserver(_ token: SettingsObserverToken) {
        for key in observers.keys {
            observers[key]?.removeValue(forKey: token)
        }
    }
    
    // MARK: - Private Helpers
    
    private func notifyObservers(for key: SettingsKey) {
        guard let keyObservers = observers[key] else { return }
        for callback in keyObservers.values {
            callback()
        }
    }
    
    // MARK: - Test Helpers
    
    public func preloadSettings(_ values: [SettingsKey: Any]) {
        for (key, value) in values {
            settings[key] = value
        }
    }
    
    public func clear() {
        settings.removeAll()
        observers.removeAll()
    }
}

// MARK: - Mock Meeting Repository

/// Mock implementation of MeetingRepositoryProtocol for testing.
@available(macOS 15.0, *)
public actor MockMeetingRepository: MeetingRepositoryProtocol {
    private var meetings: [MeetingID: Meeting] = [:]
    
    public init() {}
    
    public func save(_ meeting: Meeting) async -> Result<Void, StorageError> {
        meetings[meeting.id] = meeting
        return .success(())
    }
    
    public func get(by id: MeetingID) async -> Result<Meeting, StorageError> {
        guard let meeting = meetings[id] else {
            return .failure(.notFound(entity: "Meeting", id: id.rawValue.uuidString))
        }
        return .success(meeting)
    }
    
    public func list() async -> Result<[Meeting], StorageError> {
        return .success(Array(meetings.values))
    }
    
    public func delete(id: MeetingID) async -> Result<Void, StorageError> {
        guard meetings.removeValue(forKey: id) != nil else {
            return .failure(.notFound(entity: "Meeting", id: id.rawValue.uuidString))
        }
        return .success(())
    }
    
    public func exists(id: MeetingID) async -> Bool {
        return meetings[id] != nil
    }
    
    public func getMeetings(in dateRange: ClosedRange<Date>) async -> Result<[Meeting], StorageError> {
        let result = meetings.values.filter { meeting in
            dateRange.contains(meeting.startTime)
        }
        return .success(Array(result))
    }
    
    // MARK: - Test Helpers
    
    public func preloadMeetings(_ meetings: [Meeting]) {
        for meeting in meetings {
            self.meetings[meeting.id] = meeting
        }
    }
    
    public func clear() {
        meetings.removeAll()
    }
}
