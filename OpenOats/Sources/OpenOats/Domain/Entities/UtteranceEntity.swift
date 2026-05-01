import Foundation

// MARK: - Utterance Entity

/// Represents a single speech segment with speaker identification and timing.
/// An utterance is the atomic unit of transcribed speech.
public struct UtteranceEntity: Sendable, Equatable, Hashable, Codable {
    /// Unique identifier for this utterance.
    public let id: UtteranceID
    
    /// ID of the parent transcript.
    public let transcriptID: TranscriptID
    
    /// ID of the speaker who spoke this utterance.
    public let speakerID: SpeakerID
    
    /// The transcribed text content.
    public let text: String
    
    /// Start time within the recording.
    public let startTime: Duration
    
    /// End time within the recording.
    public let endTime: Duration
    
    /// Confidence score (0.0 to 1.0) of the transcription.
    public let confidence: Double
    
    /// Creates a new UtteranceEntity instance.
    /// - Parameters:
    ///   - id: Unique identifier for this utterance.
    ///   - transcriptID: ID of the parent transcript.
    ///   - speakerID: ID of the speaker.
    ///   - text: The transcribed text.
    ///   - startTime: Start time within the recording.
    ///   - endTime: End time within the recording.
    ///   - confidence: Confidence score (0.0 to 1.0).
    public init(
        id: UtteranceID,
        transcriptID: TranscriptID,
        speakerID: SpeakerID,
        text: String,
        startTime: Duration,
        endTime: Duration,
        confidence: Double
    ) {
        self.id = id
        self.transcriptID = transcriptID
        self.speakerID = speakerID
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
    
    /// The duration of this utterance.
    public var duration: Duration {
        endTime - startTime
    }
    
    /// Whether this utterance has a valid time range.
    /// An utterance is valid if endTime > startTime.
    public var isValid: Bool {
        endTime > startTime
    }
}
