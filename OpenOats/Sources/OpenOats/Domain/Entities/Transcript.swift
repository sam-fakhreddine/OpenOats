import Foundation

// MARK: - Transcript Entity

/// Represents a collection of transcribed content from a session.
/// Contains references to all utterances in chronological order.
public struct Transcript: Sendable, Equatable, Hashable, Codable {
    /// Unique identifier for this transcript.
    public let id: TranscriptID
    
    /// ID of the parent session.
    public let sessionID: SessionID
    
    /// ISO language code (e.g., "en", "es", "fr").
    public let language: String
    
    /// IDs of all utterances in chronological order.
    public let utteranceIDs: [UtteranceID]
    
    /// Whether transcription is complete for this session.
    public let isComplete: Bool
    
    /// Creates a new Transcript instance.
    /// - Parameters:
    ///   - id: Unique identifier for this transcript.
    ///   - sessionID: ID of the parent session.
    ///   - language: ISO language code.
    ///   - utteranceIDs: IDs of utterances in chronological order.
    ///   - isComplete: Whether transcription is complete.
    public init(
        id: TranscriptID,
        sessionID: SessionID,
        language: String,
        utteranceIDs: [UtteranceID] = [],
        isComplete: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.language = language
        self.utteranceIDs = utteranceIDs
        self.isComplete = isComplete
    }
    
    /// Returns a new Transcript with an additional utterance ID appended.
    /// - Parameter utteranceID: The utterance ID to add.
    /// - Returns: A new Transcript with the utterance ID appended.
    public func withUtteranceID(_ utteranceID: UtteranceID) -> Transcript {
        Transcript(
            id: id,
            sessionID: sessionID,
            language: language,
            utteranceIDs: utteranceIDs + [utteranceID],
            isComplete: isComplete
        )
    }
    
    /// Returns a new Transcript marked as complete.
    /// - Returns: A new Transcript with isComplete set to true.
    public func markedComplete() -> Transcript {
        Transcript(
            id: id,
            sessionID: sessionID,
            language: language,
            utteranceIDs: utteranceIDs,
            isComplete: true
        )
    }
    
    /// The full transcript text, joined from all utterances.
    /// Note: This requires access to the actual Utterance entities
    /// to retrieve the text. Returns empty string if utterances not available.
    public var text: String {
        // This is a computed property that would typically
        // be resolved by a repository or use case.
        // For the domain entity, we return empty string
        // as the actual utterance text is not stored here.
        ""
    }
}
