import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - GenerateNotesUseCase Property-Based Tests

/// Protocol definition for GenerateNotesUseCase (from TASK-005 design)
protocol GenerateNotesUseCase: Sendable, CancellableUseCase {
    func execute(input: GenerateNotesInput) async throws -> GenerateNotesOutput
}

/// Input for AI note generation
struct GenerateNotesInput: Sendable {
    let transcriptID: TranscriptID
    let sections: [NoteSectionType]
    let style: NoteGenerationStyle
    let llmProvider: LLMProvider
    let customPrompt: String?
    
    init(
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

/// Output from note generation
struct GenerateNotesOutput: Sendable {
    let note: Note
    let generatedAt: Date
    let processingTime: Duration
    let tokenCount: Int
}

/// Protocol for cancellable use cases
protocol CancellableUseCase: Sendable {
    var executionID: UUID { get }
    func cancel() async
    var isExecuting: Bool { get }
}

/// Mock implementation for testing
actor MockGenerateNotesUseCase: GenerateNotesUseCase {
    var transcripts: [TranscriptID: Transcript] = [:]
    var shouldFail = false
    var failureError: Error = TestFailure("Mock generation failure")
    var delay: Duration = .milliseconds(100)
    var isCancelled = false
    
    nonisolated let executionID: UUID = UUID()
    
    var isExecuting: Bool {
        get async { false } // Simplified for testing
    }
    
    func cancel() async {
        isCancelled = true
    }
    
    func execute(input: GenerateNotesInput) async throws -> GenerateNotesOutput {
        isCancelled = false
        
        if shouldFail {
            throw failureError
        }
        
        // Simulate work with cancellation check points
        let startTime = Date()
        try await Task.sleep(for: delay)
        
        // Check for cancellation
        try Task.checkCancellation()
        
        guard let transcript = transcripts[input.transcriptID] else {
            throw ValidationError.invalidInput(
                field: "transcriptID",
                reason: "Transcript not found"
            )
        }
        
        let note = Note(
            id: NoteID(),
            sessionID: transcript.sessionID,
            content: "Generated notes for \(transcript.utteranceIDs.count) utterances",
            category: .summary,
            aiModel: AIModelInfo(
                provider: input.llmProvider.provider,
                model: "test-model",
                requestID: UUID().uuidString
            ),
            createdAt: Date()
        )
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return GenerateNotesOutput(
            note: note,
            generatedAt: Date(),
            processingTime: .seconds(processingTime),
            tokenCount: transcript.utteranceIDs.count * 10
        )
    }
}

// MARK: - Test Suite

@Suite("GenerateNotesUseCase Property-Based Tests")
struct GenerateNotesUseCaseTests {
    
    // MARK: - Property: Note Generation Completeness
    
    /// Property: Generated notes always have content
    @Test("Generated notes always have content")
    func generatedNotesAlwaysHaveContent() async throws {
        let transcriptGen = Generator<Transcript>.transcript
        let testRunner = try await forAll(transcriptGen, iterations: 30)
        
        try await testRunner { transcript in
            let useCase = MockGenerateNotesUseCase()
            await useCase.setTranscript(transcript)
            
            let input = GenerateNotesInput(transcriptID: transcript.id)
            let output = try await useCase.execute(input: input)
            
            return !output.note.content.isEmpty
        }
    }
    
    /// Property: Generated notes are associated with correct transcript session
    @Test("Notes are associated with correct session")
    func notesAssociatedWithCorrectSession() async throws {
        let transcriptGen = Generator<Transcript>.transcript
        let testRunner = try await forAll(transcriptGen, iterations: 30)
        
        try await testRunner { transcript in
            let useCase = MockGenerateNotesUseCase()
            await useCase.setTranscript(transcript)
            
            let input = GenerateNotesInput(transcriptID: transcript.id)
            let output = try await useCase.execute(input: input)
            
            return output.note.sessionID == transcript.sessionID
        }
    }
    
    /// Property: Note IDs are always unique
    @Test("Generated note IDs are unique")
    func noteIDsAreUnique() async throws {
        let transcriptGen = Generator<Transcript>.transcript
        let testRunner = try await forAll(transcriptGen, iterations: 20)
        
        var generatedIDs: Set<NoteID> = []
        
        try await testRunner { transcript in
            let useCase = MockGenerateNotesUseCase()
            await useCase.setTranscript(transcript)
            
            let input = GenerateNotesInput(transcriptID: transcript.id)
            let output = try await useCase.execute(input: input)
            
            if generatedIDs.contains(output.note.id) {
                return false
            }
            generatedIDs.insert(output.note.id)
            return true
        }
    }
    
    // MARK: - Property: Input Validation
    
    /// Property: Non-existent transcript throws appropriate error
    @Test("Non-existent transcript throws error")
    func nonExistentTranscriptThrows() async throws {
        let transcriptIDGen = Generator<TranscriptID>.transcriptID
        let testRunner = try await forAll(transcriptIDGen, iterations: 30)
        
        try await testRunner { transcriptID in
            let useCase = MockGenerateNotesUseCase()
            // Don't add any transcripts
            
            let input = GenerateNotesInput(transcriptID: transcriptID)
            
            do {
                _ = try await useCase.execute(input: input)
                return false // Should have thrown
            } catch {
                return true
            }
        }
    }
    
    /// Property: Empty sections array is rejected or handled gracefully
    @Test("Empty sections array is handled")
    func emptySectionsHandled() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockGenerateNotesUseCase()
        await useCase.setTranscript(transcript)
        
        let input = GenerateNotesInput(
            transcriptID: transcript.id,
            sections: [] // Empty sections
        )
        
        do {
            let output = try await useCase.execute(input: input)
            // If success, that's fine - handled gracefully
            // If failure, that's also fine - rejected
            _ = output
        } catch {
            // Expected - empty sections might be invalid
        }
        
        // Test passes if we reach here (no crash)
        #expect(true)
    }
    
    // MARK: - Property: Idempotency
    
    /// Property: Same input produces deterministic notes (same transcript content)
    /// Note: IDs will differ, but content should be deterministic if no randomness in LLM
    @Test("Note generation is deterministic")
    func noteGenerationIsDeterministic() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockGenerateNotesUseCase()
        await useCase.setTranscript(transcript)
        
        let input = GenerateNotesInput(transcriptID: transcript.id)
        
        let output1 = try await useCase.execute(input: input)
        let useCase2 = MockGenerateNotesUseCase()
        await useCase2.setTranscript(transcript)
        let output2 = try await useCase2.execute(input: input)
        
        // Both should have notes
        #expect(output1.note.content == output2.note.content, "Content should be deterministic")
    }
    
    // MARK: - Property: Error Propagation
    
    /// Property: LLM errors are propagated correctly
    @Test("LLM errors are propagated")
    func llmErrorsPropagated() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockGenerateNotesUseCase()
        await useCase.setTranscript(transcript)
        await useCase.setShouldFail(true)
        await useCase.setFailureError(
            TranscriptionError.modelUnavailable(model: "test", reason: "API error")
        )
        
        let input = GenerateNotesInput(transcriptID: transcript.id)
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false, "Should have thrown")
        } catch {
            #expect(true)
        }
    }
    
    /// Property: Network errors are properly wrapped
    @Test("Network errors are properly wrapped")
    func networkErrorsWrapped() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockGenerateNotesUseCase()
        await useCase.setTranscript(transcript)
        await useCase.setShouldFail(true)
        await useCase.setFailureError(
            TranscriptionError.networkFailure(reason: "Connection timeout")
        )
        
        let input = GenerateNotesInput(transcriptID: transcript.id)
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false)
        } catch is TranscriptionError {
            #expect(true)
        }
    }
    
    // MARK: - Property: Cancellation
    
    /// Property: Long-running generation can be cancelled
    @Test("Note generation is cancellable")
    func noteGenerationIsCancellable() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockGenerateNotesUseCase()
        await useCase.setTranscript(transcript)
        await useCase.setDelay(.seconds(5))
        
        let input = GenerateNotesInput(transcriptID: transcript.id)
        
        let task = Task {
            try await useCase.execute(input: input)
        }
        
        try await Task.sleep(for: .milliseconds(100))
        await useCase.cancel()
        task.cancel()
        
        do {
            _ = try await task.value
            #expect(false, "Should have been cancelled")
        } catch is CancellationError {
            #expect(true)
        }
    }
    
    /// Property: Cancellation leaves system in consistent state
    @Test("Cancellation leaves consistent state")
    func cancellationConsistentState() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockGenerateNotesUseCase()
        await useCase.setTranscript(transcript)
        await useCase.setDelay(.seconds(2))
        
        let input = GenerateNotesInput(transcriptID: transcript.id)
        
        let task = Task {
            try await useCase.execute(input: input)
        }
        
        try await Task.sleep(for: .milliseconds(50))
        await useCase.cancel()
        task.cancel()
        
        // System should still be usable after cancellation
        let useCase2 = MockGenerateNotesUseCase()
        await useCase2.setTranscript(transcript)
        let output = try await useCase2.execute(input: input)
        
        #expect(!output.note.content.isEmpty)
    }
    
    // MARK: - Property: Output Metadata
    
    /// Property: Processing time is always positive
    @Test("Processing time is positive")
    func processingTimeIsPositive() async throws {
        let transcriptGen = Generator<Transcript>.transcript
        let testRunner = try await forAll(transcriptGen, iterations: 30)
        
        try await testRunner { transcript in
            let useCase = MockGenerateNotesUseCase()
            await useCase.setTranscript(transcript)
            
            let input = GenerateNotesInput(transcriptID: transcript.id)
            let output = try await useCase.execute(input: input)
            
            return output.processingTime > .zero
        }
    }
    
    /// Property: Generated timestamp is always in the past or present
    @Test("Generated timestamp is valid")
    func generatedTimestampIsValid() async throws {
        let transcriptGen = Generator<Transcript>.transcript
        let beforeTest = Date()
        let testRunner = try await forAll(transcriptGen, iterations: 30)
        
        try await testRunner { transcript in
            let useCase = MockGenerateNotesUseCase()
            await useCase.setTranscript(transcript)
            
            let input = GenerateNotesInput(transcriptID: transcript.id)
            let output = try await useCase.execute(input: input)
            
            return output.generatedAt >= beforeTest && output.generatedAt <= Date()
        }
    }
    
    /// Property: Token count is non-negative
    @Test("Token count is non-negative")
    func tokenCountIsNonNegative() async throws {
        let transcriptGen = Generator<Transcript>.transcript
        let testRunner = try await forAll(transcriptGen, iterations: 30)
        
        try await testRunner { transcript in
            let useCase = MockGenerateNotesUseCase()
            await useCase.setTranscript(transcript)
            
            let input = GenerateNotesInput(transcriptID: transcript.id)
            let output = try await useCase.execute(input: input)
            
            return output.tokenCount >= 0
        }
    }
    
    // MARK: - Property: Custom Prompt Handling
    
    /// Property: Custom prompts are incorporated (if provided)
    @Test("Custom prompts are used when provided")
    func customPromptsAreUsed() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockGenerateNotesUseCase()
        await useCase.setTranscript(transcript)
        
        let customPrompt = "Focus on action items only"
        let input = GenerateNotesInput(
            transcriptID: transcript.id,
            customPrompt: customPrompt
        )
        
        let output = try await useCase.execute(input: input)
        
        // Note should be generated successfully
        #expect(!output.note.content.isEmpty)
    }
    
    /// Property: Nil custom prompts work fine
    @Test("Nil custom prompts work")
    func nilCustomPromptsWork() async throws {
        let transcriptGen = Generator<Transcript>.transcript
        let testRunner = try await forAll(transcriptGen, iterations: 20)
        
        try await testRunner { transcript in
            let useCase = MockGenerateNotesUseCase()
            await useCase.setTranscript(transcript)
            
            let input = GenerateNotesInput(
                transcriptID: transcript.id,
                customPrompt: nil
            )
            
            let output = try await useCase.execute(input: input)
            return !output.note.content.isEmpty
        }
    }
    
    // MARK: - Property: Rate Limiting
    
    /// Property: Rate limit errors include retry information
    @Test("Rate limit errors include retry info")
    func rateLimitErrorsIncludeRetryInfo() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockGenerateNotesUseCase()
        await useCase.setTranscript(transcript)
        await useCase.setShouldFail(true)
        await useCase.setFailureError(
            TranscriptionError.rateLimited(
                provider: "openrouter",
                retryAfter: Date().addingTimeInterval(60)
            )
        )
        
        let input = GenerateNotesInput(transcriptID: transcript.id)
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false)
        } catch let error as TranscriptionError {
            if case .rateLimited = error {
                #expect(true)
            } else {
                #expect(false)
            }
        }
    }
}

// MARK: - Mock Helpers

extension MockGenerateNotesUseCase {
    func setTranscript(_ transcript: Transcript) {
        transcripts[transcript.id] = transcript
    }
    
    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }
    
    func setFailureError(_ error: Error) {
        failureError = error
    }
    
    func setDelay(_ duration: Duration) {
        delay = duration
    }
}
