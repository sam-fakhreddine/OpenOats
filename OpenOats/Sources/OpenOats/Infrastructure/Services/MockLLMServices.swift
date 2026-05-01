import Foundation

// MARK: - Mock LLM Service

/// Mock implementation of LLMService for testing.
@available(macOS 15.0, *)
public actor MockLLMService: LLMService {
    private var isAvailableState: Bool
    private var completeResult: Result<LLMResponse, NetworkError>?
    private var chatResult: Result<LLMResponse, NetworkError>?
    private var streamChunks: [String]
    private var shouldThrowStreamError: NetworkError?
    private var availableModels: [String]
    
    public init(
        isAvailable: Bool = true,
        availableModels: [String] = ["gpt-4", "gpt-3.5-turbo", "claude-3"]
    ) {
        self.isAvailableState = isAvailable
        self.availableModels = availableModels
        self.streamChunks = []
        
        // Set default success results
        self.completeResult = .success(LLMResponse(
            content: "This is a mock response",
            model: "mock-model",
            tokensUsed: 100,
            finishReason: "stop"
        ))
        
        self.chatResult = .success(LLMResponse(
            content: "This is a mock chat response",
            model: "mock-model",
            tokensUsed: 150,
            finishReason: "stop"
        ))
    }
    
    public func complete(
        prompt: String,
        configuration: LLMConfiguration
    ) async -> Result<LLMResponse, NetworkError> {
        guard isAvailableState else {
            return .failure(.noConnectivity)
        }
        
        return completeResult ?? .failure(.apiFailure(
            endpoint: "/complete",
            statusCode: 500,
            message: "No mock result set"
        ))
    }
    
    public func chat(
        messages: [LLMMessage],
        configuration: LLMConfiguration
    ) async -> Result<LLMResponse, NetworkError> {
        guard isAvailableState else {
            return .failure(.noConnectivity)
        }
        
        return chatResult ?? .failure(.apiFailure(
            endpoint: "/chat",
            statusCode: 500,
            message: "No mock result set"
        ))
    }
    
    public func streamComplete(
        prompt: String,
        configuration: LLMConfiguration
    ) -> AsyncThrowingStream<String, NetworkError> {
        return AsyncThrowingStream { continuation in
            Task {
                if let error = self.shouldThrowStreamError {
                    continuation.finish(throwing: error)
                    return
                }
                
                guard self.isAvailableState else {
                    continuation.finish(throwing: NetworkError.noConnectivity)
                    return
                }
                
                // Yield mock chunks
                let chunks = self.streamChunks.isEmpty 
                    ? ["This ", "is ", "a ", "mock ", "streaming ", "response."]
                    : self.streamChunks
                
                for chunk in chunks {
                    continuation.yield(chunk)
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
                
                continuation.finish()
            }
        }
    }
    
    public func listAvailableModels() async -> Result<[String], NetworkError> {
        guard isAvailableState else {
            return .failure(.noConnectivity)
        }
        
        return .success(availableModels)
    }
    
    public func isAvailable() async -> Bool {
        return isAvailableState
    }
    
    // MARK: - Test Helpers
    
    public func setIsAvailableResult(_ available: Bool) {
        self.isAvailableState = available
    }
    
    public func setCompleteResult(_ result: Result<LLMResponse, NetworkError>) {
        self.completeResult = result
    }
    
    public func setChatResult(_ result: Result<LLMResponse, NetworkError>) {
        self.chatResult = result
    }
    
    public func setStreamChunks(_ chunks: [String]) {
        self.streamChunks = chunks
    }
    
    public func setShouldThrowStreamError(_ error: NetworkError?) {
        self.shouldThrowStreamError = error
    }
    
    public func setAvailableModels(_ models: [String]) {
        self.availableModels = models
    }
}

// MARK: - Mock Embedding Service

/// Mock implementation of EmbeddingService for testing.
@available(macOS 15.0, *)
public actor MockEmbeddingService: EmbeddingService {
    private var embeddings: [[Float]]
    private var shouldFail: Bool
    private var failWithError: NetworkError?
    
    public init(
        dimensions: Int = 1536,
        shouldFail: Bool = false
    ) {
        self.embeddings = []
        self.shouldFail = shouldFail
        
        // Generate mock embeddings
        for _ in 0..<10 {
            let embedding = (0..<dimensions).map { _ in Float.random(in: -1...1) }
            self.embeddings.append(embedding)
        }
    }
    
    public func embed(
        texts: [String],
        configuration: EmbeddingConfiguration
    ) async -> Result<[[Float]], NetworkError> {
        if let error = failWithError {
            return .failure(error)
        }
        
        if shouldFail {
            return .failure(.apiFailure(
                endpoint: "/embed",
                statusCode: 500,
                message: "Mock embedding failure"
            ))
        }
        
        let result = texts.map { _ in embeddings.randomElement() ?? Array(repeating: Float(0), count: configuration.dimensions) }
        return .success(result)
    }
    
    public func embed(
        text: String,
        configuration: EmbeddingConfiguration
    ) async -> Result<[Float], NetworkError> {
        let result = await embed(texts: [text], configuration: configuration)
        switch result {
        case .success(let embeddings):
            return .success(embeddings[0])
        case .failure(let error):
            return .failure(error)
        }
    }
    
    public func similarity(between embedding1: [Float], and embedding2: [Float]) -> Double {
        guard embedding1.count == embedding2.count else { return 0.0 }
        
        var dotProduct: Float = 0
        var norm1: Float = 0
        var norm2: Float = 0
        
        for i in 0..<embedding1.count {
            dotProduct += embedding1[i] * embedding2[i]
            norm1 += embedding1[i] * embedding1[i]
            norm2 += embedding2[i] * embedding2[i]
        }
        
        let denominator = sqrt(norm1) * sqrt(norm2)
        guard denominator > 0 else { return 0.0 }
        
        return Double(dotProduct / denominator)
    }
    
    // MARK: - Test Helpers
    
    public func setShouldFail(_ fail: Bool) {
        self.shouldFail = fail
    }
    
    public func setFailWithError(_ error: NetworkError?) {
        self.failWithError = error
    }
}

// MARK: - Mock AI Suggestion Service

/// Mock implementation of AISuggestionService for testing.
@available(macOS 15.0, *)
public actor MockAISuggestionService: AISuggestionService {
    private var suggestions: [AISuggestion]
    private var generatedNote: AINote?
    private var questionAnswer: String?
    private var shouldFail: Bool
    
    public init(
        suggestions: [AISuggestion] = [],
        shouldFail: Bool = false
    ) {
        self.suggestions = suggestions
        self.shouldFail = shouldFail
        
        // Set default mock data if none provided
        if suggestions.isEmpty {
            self.suggestions = [
                AISuggestion(
                    id: UUID(),
                    type: .actionItem,
                    title: "Follow up on project timeline",
                    description: "Discuss the project timeline with the team",
                    confidence: 0.85,
                    action: .createReminder(text: "Follow up on project timeline", date: Date())
                ),
                AISuggestion(
                    id: UUID(),
                    type: .summary,
                    title: "Meeting Summary",
                    description: "The meeting covered Q4 planning and budget allocation",
                    confidence: 0.92,
                    action: nil
                )
            ]
        }
        
        self.generatedNote = AINote(
            title: "Mock Meeting Notes",
            content: "These are mock AI-generated notes for testing purposes.",
            summary: "A summary of the meeting discussion",
            tags: ["test", "mock", "meeting"]
        )
        
        self.questionAnswer = "This is a mock answer to your question."
    }
    
    public func generateSuggestions(
        from transcript: Transcript,
        context: AIMeetingContext?
    ) async -> Result<[AISuggestion], NetworkError> {
        if shouldFail {
            return .failure(.apiFailure(
                endpoint: "/suggestions",
                statusCode: 500,
                message: "Mock suggestion generation failure"
            ))
        }
        
        return .success(suggestions)
    }
    
    public func generateNotes(
        from transcript: Transcript,
        style: AINoteStyle
    ) async -> Result<AINote, NetworkError> {
        if shouldFail {
            return .failure(.apiFailure(
                endpoint: "/notes",
                statusCode: 500,
                message: "Mock note generation failure"
            ))
        }
        
        guard let note = generatedNote else {
            return .failure(.apiFailure(
                endpoint: "/notes",
                statusCode: 500,
                message: "No mock note set"
            ))
        }
        
        return .success(note)
    }
    
    public func answerQuestion(
        _ question: String,
        basedOn transcript: Transcript
    ) async -> Result<String, NetworkError> {
        if shouldFail {
            return .failure(.apiFailure(
                endpoint: "/qa",
                statusCode: 500,
                message: "Mock Q&A failure"
            ))
        }
        
        return .success(questionAnswer ?? "Mock answer to: \(question)")
    }
    
    // MARK: - Test Helpers
    
    public func setSuggestions(_ suggestions: [AISuggestion]) {
        self.suggestions = suggestions
    }
    
    public func setGeneratedNote(_ note: AINote?) {
        self.generatedNote = note
    }
    
    public func setQuestionAnswer(_ answer: String?) {
        self.questionAnswer = answer
    }
    
    public func setShouldFail(_ fail: Bool) {
        self.shouldFail = fail
    }
}
