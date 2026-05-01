import Foundation

// MARK: - Domain Identifier Types

/// A strongly-typed identifier for Meeting entities.
/// Prevents accidental mixing of different ID kinds.
public struct MeetingID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: UUID
    
    /// Creates a new MeetingID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Creates a new MeetingID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Generates a new unique MeetingID.
    public init() {
        self.rawValue = UUID()
    }
}

/// A strongly-typed identifier for Session entities.
/// Prevents accidental mixing of different ID kinds.
public struct SessionID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: UUID
    
    /// Creates a new SessionID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Creates a new SessionID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Generates a new unique SessionID.
    public init() {
        self.rawValue = UUID()
    }
}

/// A strongly-typed identifier for Transcript entities.
/// Prevents accidental mixing of different ID kinds.
public struct TranscriptID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: UUID
    
    /// Creates a new TranscriptID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Creates a new TranscriptID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Generates a new unique TranscriptID.
    public init() {
        self.rawValue = UUID()
    }
}

/// A strongly-typed identifier for Utterance entities.
/// Prevents accidental mixing of different ID kinds.
public struct UtteranceID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: UUID
    
    /// Creates a new UtteranceID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Creates a new UtteranceID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Generates a new unique UtteranceID.
    public init() {
        self.rawValue = UUID()
    }
}

/// A strongly-typed identifier for Speaker entities.
/// Prevents accidental mixing of different ID kinds.
public struct SpeakerID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: UUID
    
    /// Creates a new SpeakerID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Creates a new SpeakerID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Generates a new unique SpeakerID.
    public init() {
        self.rawValue = UUID()
    }
}

/// A strongly-typed identifier for Note entities.
/// Prevents accidental mixing of different ID kinds.
public struct NoteID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: UUID
    
    /// Creates a new NoteID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Creates a new NoteID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Generates a new unique NoteID.
    public init() {
        self.rawValue = UUID()
    }
}

/// A strongly-typed identifier for AudioSegment entities.
/// Prevents accidental mixing of different ID kinds.
public struct AudioSegmentID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: UUID
    
    /// Creates a new AudioSegmentID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Creates a new AudioSegmentID with the specified UUID.
    /// - Parameter rawValue: The UUID value for this identifier.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /// Generates a new unique AudioSegmentID.
    public init() {
        self.rawValue = UUID()
    }
}

/// A strongly-typed identifier for transcription backends.
/// Prevents accidental mixing of backend identifiers with entity IDs.
public struct BackendID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: String
    
    /// Creates a new BackendID with the specified string value.
    /// - Parameter rawValue: The string identifier for the backend.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    /// Creates a new BackendID with the specified string value.
    /// - Parameter rawValue: The string identifier for the backend.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - Well-known Backend IDs

extension BackendID {
    /// MLX Whisper backend identifier.
    public static let mlxWhisper = BackendID("mlx-whisper")
    
    /// WhisperKit backend identifier.
    public static let whisperKit = BackendID("whisperkit")
    
    /// AssemblyAI backend identifier.
    public static let assemblyAI = BackendID("assemblyai")
    
    /// ElevenLabs Scribe backend identifier.
    public static let elevenLabsScribe = BackendID("elevenlabs-scribe")
    
    /// Parakeet backend identifier.
    public static let parakeet = BackendID("parakeet")
    
    /// Qwen3 backend identifier.
    public static let qwen3 = BackendID("qwen3")
}
