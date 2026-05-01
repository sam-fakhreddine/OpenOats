import Foundation

// MARK: - AI Model Info

/// Information about the AI model used to generate a note.
public struct AIModelInfo: Sendable, Equatable, Hashable, Codable {
    /// The AI provider (e.g., "openrouter", "ollama").
    public let provider: String
    
    /// The specific model name.
    public let model: String
    
    /// The request ID for tracking/auditing.
    public let requestID: String?
    
    /// Creates a new AIModelInfo instance.
    /// - Parameters:
    ///   - provider: The AI provider.
    ///   - model: The model name.
    ///   - requestID: The request ID for tracking.
    public init(
        provider: String,
        model: String,
        requestID: String? = nil
    ) {
        self.provider = provider
        self.model = model
        self.requestID = requestID
    }
}

// MARK: - Note Category

/// Categories for AI-generated notes.
public enum NoteCategory: String, Sendable, Equatable, Hashable, Codable {
    /// General meeting summary.
    case summary
    
    /// Action items or tasks.
    case actionItem
    
    /// Decisions made during the meeting.
    case decision
    
    /// Key insights or takeaways.
    case insight
}

// MARK: - Note Entity

/// Represents an AI-generated note from a meeting session.
/// Notes are created by LLM services from transcript content.
public struct Note: Sendable, Equatable, Hashable, Codable {
    /// Type alias for category to match test expectations.
    public typealias Category = NoteCategory
    
    /// Unique identifier for this note.
    public let id: NoteID
    
    /// ID of the parent session.
    public let sessionID: SessionID
    
    /// The note content.
    public let content: String
    
    /// Category of the note.
    public let category: Category
    
    /// Information about the AI model used.
    public let aiModel: AIModelInfo?
    
    /// When the note was created.
    public let createdAt: Date
    
    /// Creates a new Note instance.
    /// - Parameters:
    ///   - id: Unique identifier for this note.
    ///   - sessionID: ID of the parent session.
    ///   - content: The note content.
    ///   - category: Category of the note.
    ///   - aiModel: Information about the AI model used.
    ///   - createdAt: When the note was created.
    public init(
        id: NoteID,
        sessionID: SessionID,
        content: String,
        category: Category,
        aiModel: AIModelInfo? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.content = content
        self.category = category
        self.aiModel = aiModel
        self.createdAt = createdAt
    }
}
