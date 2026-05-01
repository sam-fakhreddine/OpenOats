import Foundation

// MARK: - Session Repository Protocol

/// Query parameters for listing sessions.
public struct SessionQuery: Sendable, Equatable {
    public var meetingID: MeetingID?
    public var dateRange: ClosedRange<Date>?
    public var hasTranscript: Bool?
    public var sortBy: SortField
    public var sortOrder: SortOrder
    public var limit: Int?
    
    public init(
        meetingID: MeetingID? = nil,
        dateRange: ClosedRange<Date>? = nil,
        hasTranscript: Bool? = nil,
        sortBy: SortField = .startTime,
        sortOrder: SortOrder = .descending,
        limit: Int? = nil
    ) {
        self.meetingID = meetingID
        self.dateRange = dateRange
        self.hasTranscript = hasTranscript
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.limit = limit
    }
}

/// Sort field options.
public enum SortField: String, Sendable, Equatable, Codable {
    case startTime
    case duration
    case title
}

/// Sort order options.
public enum SortOrder: String, Sendable, Equatable, Codable {
    case ascending
    case descending
}

/// Protocol for session persistence and retrieval.
/// Note: Named SessionRepositoryProtocol to avoid conflict with existing SessionRepository actor.
public protocol SessionRepositoryProtocol: Sendable {
    /// Save a session.
    func save(_ session: Session) async -> Result<Void, StorageError>
    
    /// Get a session by ID.
    func get(by id: SessionID) async -> Result<Session, StorageError>
    
    /// Get all sessions for a meeting.
    func getSessions(for meetingID: MeetingID) async -> Result<[Session], StorageError>
    
    /// List sessions with query parameters.
    func list(query: SessionQuery) async -> Result<[Session], StorageError>
    
    /// Delete a session.
    func delete(id: SessionID) async -> Result<Void, StorageError>
    
    /// Check if a session exists.
    func exists(id: SessionID) async -> Bool
    
    /// Get the total count of sessions.
    func count() async -> Int
    
    /// Get storage statistics.
    func getStatistics() async -> SessionStorageStats
}

/// Session storage statistics.
public struct SessionStorageStats: Sendable, Equatable {
    public let totalSessions: Int
    public let totalAudioDuration: Duration
    public let totalStorageSize: Int64
    public let oldestSession: Date?
    public let newestSession: Date?
    
    public init(
        totalSessions: Int,
        totalAudioDuration: Duration,
        totalStorageSize: Int64,
        oldestSession: Date?,
        newestSession: Date?
    ) {
        self.totalSessions = totalSessions
        self.totalAudioDuration = totalAudioDuration
        self.totalStorageSize = totalStorageSize
        self.oldestSession = oldestSession
        self.newestSession = newestSession
    }
}

// MARK: - Transcript Repository

/// Protocol for transcript persistence and retrieval.
public protocol TranscriptRepository: Sendable {
    /// Save a transcript.
    func save(_ transcript: Transcript) async -> Result<Void, StorageError>
    
    /// Get a transcript by ID.
    func get(by id: TranscriptID) async -> Result<Transcript, StorageError>
    
    /// Get transcript for a specific session.
    func getTranscript(for sessionID: SessionID) async -> Result<Transcript?, StorageError>
    
    /// Search transcripts.
    func search(query: String, meetingID: MeetingID?) async -> Result<[Transcript], StorageError>
    
    /// Delete a transcript.
    func delete(id: TranscriptID) async -> Result<Void, StorageError>
    
    /// Export transcript to various formats.
    func export(
        transcriptID: TranscriptID,
        format: TranscriptExportFormat
    ) async -> Result<URL, StorageError>
}

/// Transcript export format options.
public enum TranscriptExportFormat: String, Sendable, Equatable, Codable {
    case txt
    case srt  // Subtitles
    case vtt  // WebVTT
    case json
    case markdown
}

// MARK: - Settings Repository

/// Keys for user preferences.
public enum SettingsKey: String, Sendable, CaseIterable, Codable {
    case defaultTranscriptionBackend
    case defaultLanguage
    case autoStartRecording
    case enableSpeakerDiarization
    case enableAISummaries
    case audioQuality
    case storageLimit
    case showConfidenceScores
    case enableCloudSync
}

/// Protocol for user preferences persistence.
public protocol SettingsRepository: Sendable {
    /// Get a string setting.
    func string(for key: SettingsKey) -> String?
    
    /// Get a boolean setting.
    func bool(for key: SettingsKey) -> Bool
    
    /// Get an integer setting.
    func integer(for key: SettingsKey) -> Int
    
    /// Get a double setting.
    func double(for key: SettingsKey) -> Double
    
    /// Get raw data setting.
    func data(for key: SettingsKey) -> Data?
    
    /// Get a codable setting.
    func codable<T: Codable & Sendable>(for key: SettingsKey) -> T?
    
    /// Set a string setting.
    func set(_ value: String?, for key: SettingsKey)
    
    /// Set a boolean setting.
    func set(_ value: Bool, for key: SettingsKey)
    
    /// Set an integer setting.
    func set(_ value: Int, for key: SettingsKey)
    
    /// Set a double setting.
    func set(_ value: Double, for key: SettingsKey)
    
    /// Set raw data.
    func set(_ value: Data?, for key: SettingsKey)
    
    /// Set a codable value.
    func set<T: Codable & Sendable>(_ value: T?, for key: SettingsKey)
    
    /// Remove a setting.
    func remove(key: SettingsKey)
    
    /// Reset all settings to defaults.
    func resetToDefaults()
    
    /// Add observer for settings changes.
    func addObserver(for key: SettingsKey, callback: @Sendable @escaping () -> Void) -> SettingsObserverToken
    
    /// Remove observer.
    func removeObserver(_ token: SettingsObserverToken)
}

/// Token for settings observer.
public struct SettingsObserverToken: Sendable, Hashable, Equatable {
    public let id: UUID
    
    public init(id: UUID = UUID()) {
        self.id = id
    }
}

// MARK: - Meeting Repository Protocol

/// Protocol for meeting persistence and retrieval.
/// Note: Named MeetingRepositoryProtocol to avoid conflict with potential future MeetingRepository type.
public protocol MeetingRepositoryProtocol: Sendable {
    /// Save a meeting.
    func save(_ meeting: Meeting) async -> Result<Void, StorageError>
    
    /// Get a meeting by ID.
    func get(by id: MeetingID) async -> Result<Meeting, StorageError>
    
    /// Get all meetings.
    func list() async -> Result<[Meeting], StorageError>
    
    /// Delete a meeting.
    func delete(id: MeetingID) async -> Result<Void, StorageError>
    
    /// Check if a meeting exists.
    func exists(id: MeetingID) async -> Bool
    
    /// Get meetings within a date range.
    func getMeetings(in dateRange: ClosedRange<Date>) async -> Result<[Meeting], StorageError>
}
