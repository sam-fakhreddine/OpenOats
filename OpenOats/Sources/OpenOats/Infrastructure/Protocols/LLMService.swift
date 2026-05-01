import Foundation

// MARK: - LLM Service

/// A message in a conversation.
public struct LLMMessage: Sendable, Equatable {
    public let role: LLMRole
    public let content: String
    
    public init(role: LLMRole, content: String) {
        self.role = role
        self.content = content
    }
}

/// LLM message roles.
public enum LLMRole: String, Sendable, Equatable, Codable {
    case system
    case user
    case assistant
}

/// Configuration for LLM requests.
public struct LLMConfiguration: Sendable, Equatable {
    public let model: String
    public let temperature: Double
    public let maxTokens: Int?
    public let provider: LLMProviderID
    
    public init(
        model: String,
        temperature: Double = 0.7,
        maxTokens: Int? = nil,
        provider: LLMProviderID = .openRouter
    ) {
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.provider = provider
    }
}

/// Response from LLM.
public struct LLMResponse: Sendable, Equatable {
    public let content: String
    public let model: String
    public let tokensUsed: Int
    public let finishReason: String?
    
    public init(
        content: String,
        model: String,
        tokensUsed: Int,
        finishReason: String?
    ) {
        self.content = content
        self.model = model
        self.tokensUsed = tokensUsed
        self.finishReason = finishReason
    }
}

/// Protocol for LLM interactions (OpenRouter, Ollama, etc.).
public protocol LLMService: Sendable {
    /// Send a single prompt and get response.
    func complete(
        prompt: String,
        configuration: LLMConfiguration
    ) async -> Result<LLMResponse, NetworkError>
    
    /// Send a conversation and get response.
    func chat(
        messages: [LLMMessage],
        configuration: LLMConfiguration
    ) async -> Result<LLMResponse, NetworkError>
    
    /// Stream response for real-time display.
    func streamComplete(
        prompt: String,
        configuration: LLMConfiguration
    ) -> AsyncThrowingStream<String, NetworkError>
    
    /// List available models.
    func listAvailableModels() async -> Result<[String], NetworkError>
    
    /// Check if service is available.
    func isAvailable() async -> Bool
}

// MARK: - Embedding Service

/// Configuration for embedding generation.
public struct EmbeddingConfiguration: Sendable, Equatable {
    public let model: String
    public let dimensions: Int
    public let provider: EmbeddingProviderID
    
    public init(
        model: String,
        dimensions: Int = 1536,
        provider: EmbeddingProviderID = .voyage
    ) {
        self.model = model
        self.dimensions = dimensions
        self.provider = provider
    }
}

/// Protocol for text embedding generation.
public protocol EmbeddingService: Sendable {
    /// Generate embeddings for texts.
    /// - Parameters:
    ///   - texts: Texts to embed.
    ///   - configuration: Embedding configuration.
    /// - Returns: Array of embedding vectors.
    func embed(
        texts: [String],
        configuration: EmbeddingConfiguration
    ) async -> Result<[[Float]], NetworkError>
    
    /// Generate embedding for a single text (convenience).
    func embed(
        text: String,
        configuration: EmbeddingConfiguration
    ) async -> Result<[Float], NetworkError>
    
    /// Calculate cosine similarity between two embeddings.
    func similarity(between embedding1: [Float], and embedding2: [Float]) -> Double
}

// MARK: - Suggestion Service

/// A suggested action or content from AI analysis.
/// Note: Named AISuggestion to avoid conflict with existing Suggestion type.
public struct AISuggestion: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let type: AISuggestionType
    public let title: String
    public let description: String
    public let confidence: Double
    public let action: AISuggestionAction?
    
    public init(
        id: UUID,
        type: AISuggestionType,
        title: String,
        description: String,
        confidence: Double,
        action: AISuggestionAction?
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.confidence = confidence
        self.action = action
    }
}

/// AI suggestion types.
public enum AISuggestionType: String, Sendable, Equatable, Codable {
    case actionItem    // Task to follow up on
    case summary       // Summary of a section
    case question      // Unanswered question
    case decision      // Decision made in meeting
    case insight       // AI-generated insight
}

/// AI suggestion actions.
public enum AISuggestionAction: Sendable, Equatable {
    case createNote(title: String, content: String)
    case addToCalendar(title: String, date: Date)
    case sendEmail(recipient: String, subject: String, body: String)
    case createReminder(text: String, date: Date)
}

/// Meeting context for AI suggestions.
public struct AIMeetingContext: Sendable, Equatable {
    public let meetingType: String?
    public let participants: [String]?
    public let scheduledDuration: Duration?
    public let agendaItems: [String]?
    
    public init(
        meetingType: String? = nil,
        participants: [String]? = nil,
        scheduledDuration: Duration? = nil,
        agendaItems: [String]? = nil
    ) {
        self.meetingType = meetingType
        self.participants = participants
        self.scheduledDuration = scheduledDuration
        self.agendaItems = agendaItems
    }
}

/// Note style options for AI generation.
public enum AINoteStyle: String, Sendable, Equatable, Codable {
    case concise
    case detailed
    case bulletPoints
    case narrative
}

/// Note structure for AI-generated notes.
/// Note: Named AINote to avoid conflict with existing Note type.
public struct AINote: Sendable, Equatable {
    public let title: String
    public let content: String
    public let summary: String?
    public let tags: [String]
    
    public init(
        title: String,
        content: String,
        summary: String? = nil,
        tags: [String] = []
    ) {
        self.title = title
        self.content = content
        self.summary = summary
        self.tags = tags
    }
}

/// Protocol for AI-powered suggestions.
public protocol AISuggestionService: Sendable {
    /// Generate suggestions from a transcript.
    /// - Parameters:
    ///   - transcript: The transcript to analyze.
    ///   - context: Additional context (meeting type, participants, etc.).
    /// - Returns: List of suggestions.
    func generateSuggestions(
        from transcript: Transcript,
        context: AIMeetingContext?
    ) async -> Result<[AISuggestion], NetworkError>
    
    /// Generate meeting notes from transcript.
    func generateNotes(
        from transcript: Transcript,
        style: AINoteStyle
    ) async -> Result<AINote, NetworkError>
    
    /// Answer a question about the meeting.
    func answerQuestion(
        _ question: String,
        basedOn transcript: Transcript
    ) async -> Result<String, NetworkError>
}
