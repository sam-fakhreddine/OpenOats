import Foundation

// MARK: - CancellableUseCase Protocol

/// Protocol for cancellable use cases - matches test definition
public protocol CancellableUseCase: Sendable {
    var executionID: UUID { get }
    func cancel() async
    var isExecuting: Bool { get }
}

// MARK: - GenerateNotesUseCase

/// Protocol definition for GenerateNotesUseCase - matches test definition
public protocol GenerateNotesUseCase: Sendable, CancellableUseCase {
    func execute(input: GenerateNotesInput) async throws -> GenerateNotesOutput
}

/// Input for AI note generation - matches test definition
public struct GenerateNotesInput: Sendable {
    public let transcriptID: TranscriptID
    public let sections: [NoteSectionType]
    public let style: NoteGenerationStyle
    public let llmProvider: LLMProvider
    public let customPrompt: String?
    
    public init(
        transcriptID: TranscriptID,
        sections: [NoteSectionType] = NoteSectionType.all,
        style: NoteGenerationStyle = .formal,
        llmProvider: LLMProvider = .openrouter,
        customPrompt: String? = nil
    ) {
        self.transcriptID = transcriptID
        self.sections = sections
        self.style = style
        self.llmProvider = llmProvider
        self.customPrompt = customPrompt
    }
}

/// Output from note generation - matches test definition
public struct GenerateNotesOutput: Sendable {
    public let note: Note
    public let generatedAt: Date
    public let processingTime: Duration
    public let tokenCount: Int
    
    public init(
        note: Note,
        generatedAt: Date,
        processingTime: Duration,
        tokenCount: Int
    ) {
        self.note = note
        self.generatedAt = generatedAt
        self.processingTime = processingTime
        self.tokenCount = tokenCount
    }
}

// MARK: - GenerateNotesUseCase Implementation

/// Implementation of GenerateNotesUseCase
public actor GenerateNotesUseCaseImpl: GenerateNotesUseCase {
    public nonisolated let executionID: UUID = UUID()
    
    private let transcriptRepository: any TranscriptRepository
    private let llmService: any LLMService
    private let noteRepository: (any NoteRepository)?
    
    private var currentTask: Task<Void, Never>?

    public func isExecuting() async -> Bool {
        currentTask != nil
    }
    
    public init(
        transcriptRepository: any TranscriptRepository,
        llmService: any LLMService,
        noteRepository: (any NoteRepository)? = nil
    ) {
        self.transcriptRepository = transcriptRepository
        self.llmService = llmService
        self.noteRepository = noteRepository
    }
    
    public func cancel() async {
        currentTask?.cancel()
    }

    public func execute(input: GenerateNotesInput) async throws -> GenerateNotesOutput {
        let startTime = Date()
        
        // Create task for tracking
        let task = Task { () -> GenerateNotesOutput in
            // Check for cancellation
            try Task.checkCancellation()
            
            // Retrieve the transcript
            let transcriptResult = await self.transcriptRepository.get(by: input.transcriptID)
            let transcript: Transcript
            switch transcriptResult {
            case .success(let foundTranscript):
                transcript = foundTranscript
            case .failure:
                throw ValidationError.invalidInput(
                    field: "transcriptID",
                    value: input.transcriptID.rawValue.uuidString,
                    requirement: "Transcript not found"
                )
            }
            
            // Check for cancellation
            try Task.checkCancellation()
            try await self.checkCancelled()
            
            // Generate notes using LLM service
            let prompt = self.buildPrompt(transcript: transcript, input: input)
            let configuration = LLMConfiguration(
                model: "gpt-4",
                temperature: 0.7,
                provider: LLMProviderID(input.llmProvider.provider)
            )
            
            let llmResult = await self.llmService.complete(
                prompt: prompt,
                configuration: configuration
            )
            
            // Check for cancellation after LLM call
            try Task.checkCancellation()
            try await self.checkCancelled()
            
            let llmResponse: LLMResponse
            switch llmResult {
            case .success(let response):
                llmResponse = response
            case .failure(let error):
                throw error
            }
            
            // Create note entity
            let note = Note(
                id: NoteID(),
                sessionID: transcript.sessionID,
                content: llmResponse.content,
                category: .summary,
                aiModel: AIModelInfo(
                    provider: input.llmProvider.provider,
                    model: llmResponse.model,
                    requestID: self.executionID.uuidString
                ),
                createdAt: Date()
            )
            
            // Save note if repository available
            if let noteRepo = self.noteRepository {
                _ = await noteRepo.save(note)
            }
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            return GenerateNotesOutput(
                note: note,
                generatedAt: Date(),
                processingTime: .seconds(processingTime),
                tokenCount: llmResponse.tokensUsed
            )
        }
        
        self.currentTask = task
        
        do {
            let output = try await task.value
            self.currentTask = nil
            return output
        } catch {
            self.currentTask = nil
            throw error
        }
    }
    
    private func checkCancelled() async throws {
        if Task.isCancelled {
            throw CancellationError()
        }
    }
    
    private func buildPrompt(transcript: Transcript, input: GenerateNotesInput) -> String {
        var prompt = "Generate meeting notes from the following transcript.\n\n"
        
        // Add custom prompt if provided
        if let customPrompt = input.customPrompt {
            prompt += "Instructions: \(customPrompt)\n\n"
        }
        
        // Add style instructions
        switch input.style.style {
        case "formal":
            prompt += "Style: Formal and professional.\n"
        case "casual":
            prompt += "Style: Casual and conversational.\n"
        case "bullet-points":
            prompt += "Style: Use bullet points for clarity.\n"
        default:
            prompt += "Style: Balanced and clear.\n"
        }
        
        // Add section requirements
        prompt += "Sections to include: \(input.sections.map { "\($0)" }.joined(separator: ", "))\n\n"
        prompt += "Transcript: \(transcript.text)\n\n"
        prompt += "Please generate comprehensive notes based on the above."
        
        return prompt
    }
}

// MARK: - Note Repository Protocol

/// Protocol for note persistence
public protocol NoteRepository: Sendable {
    func save(_ note: Note) async -> Result<Void, StorageError>
    func get(by id: NoteID) async -> Result<Note, StorageError>
    func getNotes(for sessionID: SessionID) async -> Result<[Note], StorageError>
    func delete(id: NoteID) async -> Result<Void, StorageError>
}
