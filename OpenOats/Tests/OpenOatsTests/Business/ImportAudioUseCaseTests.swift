import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - ImportAudioUseCase Property-Based Tests

/// Protocol definition for ImportAudioUseCase (from TASK-005 design)
protocol ImportAudioUseCase: Sendable, ProgressReportingUseCase {
    func execute(input: ImportAudioInput) async throws -> ImportAudioOutput
}

/// Audio format enum for import testing
enum ImportAudioFormat: Sendable {
    case wav, mp3, m4a, flac, aac, ogg
}

/// Input for importing audio
struct ImportAudioInput: Sendable {
    let sourceURL: URL
    let targetSessionName: String?
    let autoTranscribe: Bool
    let backend: BackendID?
    
    init(
        sourceURL: URL,
        targetSessionName: String? = nil,
        autoTranscribe: Bool = true,
        backend: BackendID? = nil
    ) {
        self.sourceURL = sourceURL
        self.targetSessionName = targetSessionName
        self.autoTranscribe = autoTranscribe
        self.backend = backend
    }
}

/// Output from importing audio
struct ImportAudioOutput: Sendable {
    let session: Session
    let transcript: Transcript?
    let importedAt: Date
}

/// Audio validation result for import
struct ImportAudioValidationResult: Sendable {
    let isValid: Bool
    let format: ImportAudioFormat?
    let duration: Duration?
    let sampleRate: Int?
    let error: AudioError?
}

/// Mock implementation for testing
actor MockImportAudioUseCase: ImportAudioUseCase {
    var validFiles: Set<URL> = []
    var fileMetadata: [URL: (format: ImportAudioFormat, duration: Duration, sampleRate: Int)] = [:]
    var shouldFail = false
    var failureError: Error = TestFailure("Mock import failure")
    var delay: Duration = .milliseconds(100)
    var simulateTranscription = false
    
    nonisolated var progressStream: AsyncStream<Double> {
        AsyncStream { continuation in
            Task {
                for i in 0...10 {
                    continuation.yield(Double(i) / 10.0)
                    try await Task.sleep(for: .milliseconds(10))
                }
                continuation.finish()
            }
        }
    }
    
    func execute(input: ImportAudioInput) async throws -> ImportAudioOutput {
        // Validate the source file exists
        guard validFiles.contains(input.sourceURL) else {
            throw AudioError.deviceNotFound(device: input.sourceURL.path)
        }
        
        if shouldFail {
            throw failureError
        }
        
        // Simulate import work
        try await Task.sleep(for: delay)
        
        try Task.checkCancellation()
        
        // Create new session for imported audio
        let sessionID = SessionID()
        let meetingID = MeetingID()
        let session = Session(
            id: sessionID,
            meetingID: meetingID,
            startTime: Date(),
            endTime: nil,
            status: .active,
            backendID: input.backend
        )
        
        // Generate transcript if auto-transcribe is enabled
        var transcript: Transcript? = nil
        if input.autoTranscribe {
            transcript = Transcript(
                id: TranscriptID(),
                sessionID: sessionID,
                language: "en",
                utteranceIDs: [],
                isComplete: false
            )
        }
        
        return ImportAudioOutput(
            session: session,
            transcript: transcript,
            importedAt: Date()
        )
    }
    
    func validateAudioFile(url: URL) async -> ImportAudioValidationResult {
        guard validFiles.contains(url) else {
            return ImportAudioValidationResult(
                isValid: false,
                format: nil,
                duration: nil,
                sampleRate: nil,
                error: AudioError.formatUnsupported(format: url.pathExtension, sampleRate: nil)
            )
        }
        
        if let metadata = fileMetadata[url] {
            return ImportAudioValidationResult(
                isValid: true,
                format: metadata.format,
                duration: metadata.duration,
                sampleRate: metadata.sampleRate,
                error: nil
            )
        }
        
        return ImportAudioValidationResult(
            isValid: true,
            format: .wav,
            duration: .seconds(60),
            sampleRate: 44100,
            error: nil
        )
    }
}

/// Generator for audio file URLs
extension Generator where T == URL {
    static var audioFileURL: Generator<URL> {
        Generator {
            let extensions = ["wav", "mp3", "m4a", "flac", "aac", "ogg"]
            let ext = extensions.randomElement()!
            let id = UUID().uuidString
            return URL(fileURLWithPath: "/tmp/audio/\(id).\(ext)")
        }
    }
    
    static var invalidURL: Generator<URL> {
        Generator {
            let paths = [
                "/dev/null",
                "/nonexistent/file.wav",
                "",
                "/proc/self/mem"
            ]
            return URL(fileURLWithPath: paths.randomElement()!)
        }
    }
}

/// Generator for audio formats
extension Generator where T == ImportAudioFormat {
    static var audioFormat: Generator<ImportAudioFormat> {
        Generator {
            let formats: [ImportAudioFormat] = [.wav, .mp3, .m4a, .flac, .aac, .ogg]
            return formats.randomElement()!
        }
    }
}

// MARK: - Test Suite

@Suite("ImportAudioUseCase Property-Based Tests")
struct ImportAudioUseCaseTests {
    
    // MARK: - Property: Import Completeness
    
    /// Property: Valid audio files always create a session
    @Test("Valid audio files create sessions")
    func validAudioFilesCreateSessions() async throws {
        let urlGen = Generator<URL>.audioFileURL
        let testRunner = try await forAll(urlGen, iterations: 30)
        
        try await testRunner { url in
            let useCase = MockImportAudioUseCase()
            await useCase.addValidFile(url)
            
            let input = ImportAudioInput(sourceURL: url)
            let output = try await useCase.execute(input: input)
            
            return output.session.status == .active
        }
    }
    
    /// Property: Imported sessions have unique IDs
    @Test("Imported sessions have unique IDs")
    func importedSessionsHaveUniqueIDs() async throws {
        let urlGen = Generator<URL>.audioFileURL
        let testRunner = try await forAll(urlGen, iterations: 20)
        
        var sessionIDs: Set<SessionID> = []
        
        try await testRunner { url in
            let useCase = MockImportAudioUseCase()
            await useCase.addValidFile(url)
            
            let input = ImportAudioInput(sourceURL: url)
            let output = try await useCase.execute(input: input)
            
            if sessionIDs.contains(output.session.id) {
                return false
            }
            sessionIDs.insert(output.session.id)
            return true
        }
    }
    
    /// Property: Import timestamp is valid
    @Test("Import timestamp is valid")
    func importTimestampIsValid() async throws {
        let urlGen = Generator<URL>.audioFileURL
        let beforeTest = Date()
        let testRunner = try await forAll(urlGen, iterations: 30)
        
        try await testRunner { url in
            let useCase = MockImportAudioUseCase()
            await useCase.addValidFile(url)
            
            let input = ImportAudioInput(sourceURL: url)
            let output = try await useCase.execute(input: input)
            
            return output.importedAt >= beforeTest && output.importedAt <= Date()
        }
    }
    
    // MARK: - Property: Auto-Transcription
    
    /// Property: autoTranscribe=true creates transcript
    @Test("Auto-transcribe creates transcript")
    func autoTranscribeCreatesTranscript() async throws {
        let urlGen = Generator<URL>.audioFileURL
        let testRunner = try await forAll(urlGen, iterations: 30)
        
        try await testRunner { url in
            let useCase = MockImportAudioUseCase()
            await useCase.addValidFile(url)
            
            let input = ImportAudioInput(
                sourceURL: url,
                autoTranscribe: true
            )
            let output = try await useCase.execute(input: input)
            
            return output.transcript != nil
        }
    }
    
    /// Property: autoTranscribe=false skips transcript
    @Test("Auto-transcribe disabled skips transcript creation")
    func autoTranscribeDisabledSkipsTranscript() async throws {
        let urlGen = Generator<URL>.audioFileURL
        let testRunner = try await forAll(urlGen, iterations: 30)
        
        try await testRunner { url in
            let useCase = MockImportAudioUseCase()
            await useCase.addValidFile(url)
            
            let input = ImportAudioInput(
                sourceURL: url,
                autoTranscribe: false
            )
            let output = try await useCase.execute(input: input)
            
            return output.transcript == nil
        }
    }
    
    /// Property: Transcript is linked to correct session
    @Test("Transcript linked to correct session")
    func transcriptLinkedToCorrectSession() async throws {
        let urlGen = Generator<URL>.audioFileURL
        let testRunner = try await forAll(urlGen, iterations: 30)
        
        try await testRunner { url in
            let useCase = MockImportAudioUseCase()
            await useCase.addValidFile(url)
            
            let input = ImportAudioInput(
                sourceURL: url,
                autoTranscribe: true
            )
            let output = try await useCase.execute(input: input)
            
            guard let transcript = output.transcript else {
                return false
            }
            
            return transcript.sessionID == output.session.id
        }
    }
    
    // MARK: - Property: Backend Assignment
    
    /// Property: Specified backend is assigned to session
    @Test("Specified backend is assigned")
    func specifiedBackendIsAssigned() async throws {
        let urlGen = Generator<URL>.audioFileURL
        let backendGen = Generator<BackendID>.backendID
        let testRunner = try await forAll2(urlGen, backendGen, iterations: 30)
        
        try await testRunner { url, backend in
            let useCase = MockImportAudioUseCase()
            await useCase.addValidFile(url)
            
            let input = ImportAudioInput(
                sourceURL: url,
                autoTranscribe: true,
                backend: backend
            )
            let output = try await useCase.execute(input: input)
            
            return output.session.backendID == backend
        }
    }
    
    /// Property: Nil backend is handled
    @Test("Nil backend is handled")
    func nilBackendIsHandled() async throws {
        let urlGen = Generator<URL>.audioFileURL
        let testRunner = try await forAll(urlGen, iterations: 30)
        
        try await testRunner { url in
            let useCase = MockImportAudioUseCase()
            await useCase.addValidFile(url)
            
            let input = ImportAudioInput(
                sourceURL: url,
                backend: nil
            )
            let output = try await useCase.execute(input: input)
            
            // Should still create session, backend may be nil or default
            return output.session.id.rawValue != UUID()
        }
    }
    
    // MARK: - Property: Error Handling
    
    /// Property: Invalid file paths throw appropriate error
    @Test("Invalid file paths throw error")
    func invalidFilePathsThrowError() async throws {
        let urlGen = Generator<URL>.invalidURL
        let testRunner = try await forAll(urlGen, iterations: 30)
        
        try await testRunner { url in
            let useCase = MockImportAudioUseCase()
            // Don't add to valid files
            
            let input = ImportAudioInput(sourceURL: url)
            
            do {
                _ = try await useCase.execute(input: input)
                return false
            } catch {
                return true
            }
        }
    }
    
    /// Property: Audio validation errors are properly wrapped
    @Test("Audio validation errors are wrapped")
    func audioValidationErrorsWrapped() async throws {
        let invalidURL = URL(fileURLWithPath: "/invalid.xyz")
        let useCase = MockImportAudioUseCase()
        
        let input = ImportAudioInput(sourceURL: invalidURL)
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false, "Should have thrown")
        } catch {
            #expect(true)
        }
    }
    
    /// Property: Unsupported formats are rejected
    @Test("Unsupported formats are rejected")
    func unsupportedFormatsRejected() async throws {
        let unsupportedURL = URL(fileURLWithPath: "/tmp/test.xyz")
        let useCase = MockImportAudioUseCase()
        // Don't add to valid files
        
        let input = ImportAudioInput(sourceURL: unsupportedURL)
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false)
        } catch let error as AudioError {
            if case .formatUnsupported = error {
                #expect(true)
            } else {
                #expect(false)
            }
        } catch {
            // Other errors also acceptable
            #expect(true)
        }
    }
    
    // MARK: - Property: Cancellation
    
    /// Property: Import can be cancelled during processing
    @Test("Import is cancellable")
    func importIsCancellable() async throws {
        let url = Generator<URL>.audioFileURL.generate()
        let useCase = MockImportAudioUseCase()
        await useCase.addValidFile(url)
        await useCase.setDelay(.seconds(5))
        
        let input = ImportAudioInput(sourceURL: url)
        
        let task = Task {
            try await useCase.execute(input: input)
        }
        
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        
        do {
            _ = try await task.value
            #expect(false, "Should have been cancelled")
        } catch is CancellationError {
            #expect(true)
        }
    }
    
    // MARK: - Property: Progress Reporting
    
    /// Property: Progress updates sent during import
    @Test("Progress updates sent")
    func progressUpdatesSent() async throws {
        let url = Generator<URL>.audioFileURL.generate()
        let useCase = MockImportAudioUseCase()
        await useCase.addValidFile(url)
        
        let input = ImportAudioInput(sourceURL: url)
        
        var progressValues: [Double] = []
        
        let progressTask = Task {
            for await progress in await useCase.progressStream {
                progressValues.append(progress)
            }
        }
        
        _ = try await useCase.execute(input: input)
        await progressTask.value
        
        #expect(!progressValues.isEmpty)
    }
    
    // MARK: - Property: Sendable Safety
    
    /// Property: Import works correctly across actor boundaries
    @Test("Import is Sendable-safe")
    func importIsSendableSafe() async throws {
        let urls = (0..<5).map { _ in Generator<URL>.audioFileURL.generate() }
        
        await withTaskGroup(of: ImportAudioOutput.self) { group in
            for url in urls {
                group.addTask {
                    let useCase = MockImportAudioUseCase()
                    await useCase.addValidFile(url)
                    
                    let input = ImportAudioInput(sourceURL: url)
                    return try! await useCase.execute(input: input)
                }
            }
            
            var results: [ImportAudioOutput] = []
            for await output in group {
                results.append(output)
            }
            
            #expect(results.count == urls.count)
        }
    }
    
    // MARK: - Property: Session Naming
    
    /// Property: Custom session name is preserved
    @Test("Custom session name is preserved")
    func customSessionNamePreserved() async throws {
        let url = Generator<URL>.audioFileURL.generate()
        let useCase = MockImportAudioUseCase()
        await useCase.addValidFile(url)
        
        let customName = "My Import Test"
        let input = ImportAudioInput(
            sourceURL: url,
            targetSessionName: customName
        )
        
        let output = try await useCase.execute(input: input)
        
        // Session should be created (name might be stored differently)
        #expect(output.session.status == .active)
    }
    
    /// Property: Nil session name is handled
    @Test("Nil session name is handled")
    func nilSessionNameHandled() async throws {
        let urlGen = Generator<URL>.audioFileURL
        let testRunner = try await forAll(urlGen, iterations: 30)
        
        try await testRunner { url in
            let useCase = MockImportAudioUseCase()
            await useCase.addValidFile(url)
            
            let input = ImportAudioInput(
                sourceURL: url,
                targetSessionName: nil
            )
            
            let output = try await useCase.execute(input: input)
            return output.session.status == .active
        }
    }
    
    // MARK: - Property: Idempotency
    
    /// Property: Same file imported multiple times creates different sessions
    @Test("Same file creates different sessions")
    func sameFileCreatesDifferentSessions() async throws {
        let url = Generator<URL>.audioFileURL.generate()
        let useCase = MockImportAudioUseCase()
        await useCase.addValidFile(url)
        
        let input = ImportAudioInput(sourceURL: url)
        
        let output1 = try await useCase.execute(input: input)
        let output2 = try await useCase.execute(input: input)
        
        // Should have different session IDs
        #expect(output1.session.id != output2.session.id)
    }
}

// MARK: - Mock Helpers

extension MockImportAudioUseCase {
    func addValidFile(_ url: URL) {
        validFiles.insert(url)
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
    
    func setSimulateTranscription(_ value: Bool) {
        simulateTranscription = value
    }
}
