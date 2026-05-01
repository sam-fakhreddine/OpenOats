import Foundation

// MARK: - Voice Signature

/// Represents a speaker's voice characteristics for identification.
/// Contains embedding vectors and metadata for voice matching.
public struct VoiceSignature: Sendable, Equatable, Hashable, Codable {
    /// Voice embedding vector for matching.
    public let embedding: [Double]
    
    /// Number of samples used to create this signature.
    public let sampleCount: Int
    
    /// Creates a new VoiceSignature instance.
    /// - Parameters:
    ///   - embedding: Voice embedding vector.
    ///   - sampleCount: Number of samples used.
    public init(embedding: [Double], sampleCount: Int) {
        self.embedding = embedding
        self.sampleCount = sampleCount
    }
}

// MARK: - Speaker Entity

/// Represents a speaker identified during transcription.
/// Contains identity information and voice signature for matching.
public struct SpeakerEntity: Sendable, Equatable, Hashable, Codable {
    /// Unique identifier for this speaker.
    public let id: SpeakerID
    
    /// Display name of the speaker.
    public let name: String
    
    /// Voice signature for speaker identification.
    public let voiceSignature: VoiceSignature?
    
    /// Creates a new SpeakerEntity instance.
    /// - Parameters:
    ///   - id: Unique identifier for this speaker.
    ///   - name: Display name of the speaker.
    ///   - voiceSignature: Voice signature for matching, if available.
    public init(
        id: SpeakerID,
        name: String,
        voiceSignature: VoiceSignature? = nil
    ) {
        self.id = id
        self.name = name
        self.voiceSignature = voiceSignature
    }
    
    /// Returns a new SpeakerEntity with the specified voice signature.
    /// - Parameter voiceSignature: The voice signature to set.
    /// - Returns: A new SpeakerEntity with the voice signature updated.
    public func withVoiceSignature(_ voiceSignature: VoiceSignature) -> SpeakerEntity {
        SpeakerEntity(
            id: id,
            name: name,
            voiceSignature: voiceSignature
        )
    }
}
