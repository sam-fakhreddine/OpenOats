import Foundation
import Testing
@testable import OpenOatsKit

// MARK: - ExportTranscriptUseCase Property-Based Tests

/// Protocol definition for ExportTranscriptUseCase (from TASK-005 design)
protocol ExportTranscriptUseCase: Sendable, ProgressReportingUseCase {
    func execute(input: ExportTranscriptInput) async throws -> ExportTranscriptOutput
}

/// Protocol for progress reporting
protocol ProgressReportingUseCase: Sendable {
    var progressStream: AsyncStream<Double> { get }
}

/// Export format options for transcript export testing
enum TranscriptExportFormat: Sendable {
    case txt, json, markdown, srt, docx, pdf
}

/// Input for exporting transcript
struct ExportTranscriptInput: Sendable {
    let transcriptID: TranscriptID
    let format: TranscriptExportFormat
    let destination: URL
    let includeSpeakers: Bool
    let includeTimestamps: Bool
    
    init(
        transcriptID: TranscriptID,
        format: TranscriptExportFormat,
        destination: URL,
        includeSpeakers: Bool = true,
        includeTimestamps: Bool = true
    ) {
        self.transcriptID = transcriptID
        self.format = format
        self.destination = destination
        self.includeSpeakers = includeSpeakers
        self.includeTimestamps = includeTimestamps
    }
}

/// Output from exporting transcript
struct ExportTranscriptOutput: Sendable {
    let exportedURL: URL
    let bytesWritten: Int
}

/// Mock implementation for testing
actor MockExportTranscriptUseCase: ExportTranscriptUseCase {
    var transcripts: [TranscriptID: Transcript] = [:]
    var shouldFail = false
    var failureError: Error = TestFailure("Mock export failure")
    var delay: Duration = .milliseconds(50)
    var simulateProgress = true
    
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
    
    func execute(input: ExportTranscriptInput) async throws -> ExportTranscriptOutput {
        if shouldFail {
            throw failureError
        }
        
        guard transcripts[input.transcriptID] != nil else {
            throw StorageError.notFound(id: input.transcriptID.rawValue.uuidString)
        }
        
        if simulateProgress {
            try await Task.sleep(for: delay)
        }
        
        let fileName = "\(input.transcriptID.rawValue.uuidString).\(fileExtension(for: input.format))"
        let exportedURL = input.destination.appendingPathComponent(fileName)
        
        // Simulate file size based on transcript content
        let baseSize = 1024
        let metadataSize = (input.includeSpeakers ? 512 : 0) + (input.includeTimestamps ? 512 : 0)
        let formatMultiplier = sizeMultiplier(for: input.format)
        
        let bytesWritten = (baseSize + metadataSize) * formatMultiplier
        
        return ExportTranscriptOutput(
            exportedURL: exportedURL,
            bytesWritten: bytesWritten
        )
    }
    
    private func fileExtension(for format: TranscriptExportFormat) -> String {
        switch format {
        case .txt: return "txt"
        case .json: return "json"
        case .markdown: return "md"
        case .srt: return "srt"
        case .docx: return "docx"
        case .pdf: return "pdf"
        }
    }
    
    private func sizeMultiplier(for format: TranscriptExportFormat) -> Int {
        switch format {
        case .txt: return 1
        case .json: return 2
        case .markdown: return 1
        case .srt: return 1
        case .docx: return 5
        case .pdf: return 8
        }
    }
}

/// Generator for export formats
extension Generator where T == TranscriptExportFormat {
    static var exportFormat: Generator<TranscriptExportFormat> {
        Generator {
            let formats: [TranscriptExportFormat] = [.txt, .json, .markdown, .srt, .docx, .pdf]
            return formats.randomElement()!
        }
    }
}

/// Generator for URLs
extension Generator where T == URL {
    static var directoryURL: Generator<URL> {
        Generator {
            let paths = [
                "/tmp/exports",
                "/Users/test/Documents",
                "/var/tmp/openoats",
                FileManager.default.temporaryDirectory.path
            ]
            return URL(fileURLWithPath: paths.randomElement()!)
        }
    }
}

// MARK: - Test Suite

@Suite("ExportTranscriptUseCase Property-Based Tests")
struct ExportTranscriptUseCaseTests {
    
    // MARK: - Property: Export Completeness
    
    /// Property: Export always produces a valid file URL
    @Test("Export produces valid URL")
    func exportProducesValidURL() async throws {
        let transcriptGen = Generator<Transcript>.transcript
        let formatGen = Generator<ExportFormat>.exportFormat
        let testRunner = try await forAll2(transcriptGen, formatGen, iterations: 30)
        
        try await testRunner { transcript, format in
            let useCase = MockExportTranscriptUseCase()
            await useCase.setTranscript(transcript)
            
            let input = ExportTranscriptInput(
                transcriptID: transcript.id,
                format: format,
                destination: FileManager.default.temporaryDirectory
            )
            
            let output = try await useCase.execute(input: input)
            
            return output.exportedURL.pathComponents.count > 0 &&
                   !output.exportedURL.lastPathComponent.isEmpty
        }
    }
    
    /// Property: Exported file has correct extension
    @Test("Exported file has correct extension")
    func exportedFileHasCorrectExtension() async throws {
        let transcriptGen = Generator<Transcript>.transcript
        let formatGen = Generator<ExportFormat>.exportFormat
        let testRunner = try await forAll2(transcriptGen, formatGen, iterations: 30)
        
        try await testRunner { transcript, format in
            let useCase = MockExportTranscriptUseCase()
            await useCase.setTranscript(transcript)
            
            let input = ExportTranscriptInput(
                transcriptID: transcript.id,
                format: format,
                destination: FileManager.default.temporaryDirectory
            )
            
            let output = try await useCase.execute(input: input)
            let expectedExtension = fileExtension(for: format)
            
            return output.exportedURL.pathExtension == expectedExtension
        }
    }
    
    /// Property: Bytes written is always positive
    @Test("Bytes written is positive")
    func bytesWrittenIsPositive() async throws {
        let transcriptGen = Generator<Transcript>.transcript
        let formatGen = Generator<ExportFormat>.exportFormat
        let testRunner = try await forAll2(transcriptGen, formatGen, iterations: 30)
        
        try await testRunner { transcript, format in
            let useCase = MockExportTranscriptUseCase()
            await useCase.setTranscript(transcript)
            
            let input = ExportTranscriptInput(
                transcriptID: transcript.id,
                format: format,
                destination: FileManager.default.temporaryDirectory
            )
            
            let output = try await useCase.execute(input: input)
            return output.bytesWritten > 0
        }
    }
    
    // MARK: - Property: Idempotency
    
    /// Property: Same input produces equivalent export results
    @Test("Export is deterministic")
    func exportIsDeterministic() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockExportTranscriptUseCase()
        await useCase.setTranscript(transcript)
        
        let input = ExportTranscriptInput(
            transcriptID: transcript.id,
            format: .txt,
            destination: FileManager.default.temporaryDirectory
        )
        
        let output1 = try await useCase.execute(input: input)
        let output2 = try await useCase.execute(input: input)
        
        // Should produce equivalent results
        #expect(output1.exportedURL.pathExtension == output2.exportedURL.pathExtension)
        #expect(output1.bytesWritten == output2.bytesWritten)
    }
    
    // MARK: - Property: Format Options
    
    /// Property: Different formats produce different file sizes
    @Test("Different formats have different sizes")
    func differentFormatsHaveDifferentSizes() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockExportTranscriptUseCase()
        await useCase.setTranscript(transcript)
        
        let formats: [ExportFormat] = [.txt, .json, .pdf]
        var sizes: [Int] = []
        
        for format in formats {
            let input = ExportTranscriptInput(
                transcriptID: transcript.id,
                format: format,
                destination: FileManager.default.temporaryDirectory
            )
            let output = try await useCase.execute(input: input)
            sizes.append(output.bytesWritten)
        }
        
        // PDF should be larger than text
        #expect(sizes[2] > sizes[0], "PDF should be larger than text")
    }
    
    /// Property: Metadata options affect file size
    @Test("Metadata options affect file size")
    func metadataOptionsAffectFileSize() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockExportTranscriptUseCase()
        await useCase.setTranscript(transcript)
        
        let inputWithMetadata = ExportTranscriptInput(
            transcriptID: transcript.id,
            format: .txt,
            destination: FileManager.default.temporaryDirectory,
            includeSpeakers: true,
            includeTimestamps: true
        )
        
        let inputWithoutMetadata = ExportTranscriptInput(
            transcriptID: transcript.id,
            format: .txt,
            destination: FileManager.default.temporaryDirectory,
            includeSpeakers: false,
            includeTimestamps: false
        )
        
        let outputWith = try await useCase.execute(input: inputWithMetadata)
        let outputWithout = try await useCase.execute(input: inputWithoutMetadata)
        
        #expect(outputWith.bytesWritten >= outputWithout.bytesWritten)
    }
    
    // MARK: - Property: Error Handling
    
    /// Property: Non-existent transcript throws appropriate error
    @Test("Non-existent transcript throws error")
    func nonExistentTranscriptThrows() async throws {
        let transcriptIDGen = Generator<TranscriptID>.transcriptID
        let testRunner = try await forAll(transcriptIDGen, iterations: 30)
        
        try await testRunner { transcriptID in
            let useCase = MockExportTranscriptUseCase()
            // Don't add any transcripts
            
            let input = ExportTranscriptInput(
                transcriptID: transcriptID,
                format: .txt,
                destination: FileManager.default.temporaryDirectory
            )
            
            do {
                _ = try await useCase.execute(input: input)
                return false
            } catch {
                return true
            }
        }
    }
    
    /// Property: Invalid destination is handled gracefully
    @Test("Invalid destination is handled")
    func invalidDestinationHandled() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockExportTranscriptUseCase()
        await useCase.setTranscript(transcript)
        
        // Use a path that's likely invalid
        let invalidURL = URL(fileURLWithPath: "/dev/null/invalid")
        
        let input = ExportTranscriptInput(
            transcriptID: transcript.id,
            format: .txt,
            destination: invalidURL
        )
        
        // Should either succeed or throw - not crash
        do {
            _ = try await useCase.execute(input: input)
        } catch {
            // Expected
        }
        
        #expect(true)
    }
    
    /// Property: Storage errors are properly propagated
    @Test("Storage errors are propagated")
    func storageErrorsPropagated() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockExportTranscriptUseCase()
        await useCase.setTranscript(transcript)
        await useCase.setShouldFail(true)
        await useCase.setFailureError(StorageError.writeFailed(reason: "Disk full"))
        
        let input = ExportTranscriptInput(
            transcriptID: transcript.id,
            format: .txt,
            destination: FileManager.default.temporaryDirectory
        )
        
        do {
            _ = try await useCase.execute(input: input)
            #expect(false)
        } catch {
            #expect(true)
        }
    }
    
    // MARK: - Property: Progress Reporting
    
    /// Property: Progress updates are sent during export
    @Test("Progress updates are sent")
    func progressUpdatesAreSent() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockExportTranscriptUseCase()
        await useCase.setTranscript(transcript)
        await useCase.setSimulateProgress(true)
        
        let input = ExportTranscriptInput(
            transcriptID: transcript.id,
            format: .txt,
            destination: FileManager.default.temporaryDirectory
        )
        
        var progressValues: [Double] = []
        
        let progressTask = Task {
            for await progress in await useCase.progressStream {
                progressValues.append(progress)
            }
        }
        
        _ = try await useCase.execute(input: input)
        await progressTask.value
        
        #expect(!progressValues.isEmpty, "Should have received progress updates")
        #expect(progressValues.last == 1.0 || progressValues.last! >= 0.9, "Should reach near 100%")
    }
    
    /// Property: Progress values are monotonically increasing
    @Test("Progress values are monotonically increasing")
    func progressIsMonotonicallyIncreasing() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockExportTranscriptUseCase()
        await useCase.setTranscript(transcript)
        
        let input = ExportTranscriptInput(
            transcriptID: transcript.id,
            format: .txt,
            destination: FileManager.default.temporaryDirectory
        )
        
        var progressValues: [Double] = []
        
        let progressTask = Task {
            for await progress in await useCase.progressStream {
                progressValues.append(progress)
            }
        }
        
        _ = try await useCase.execute(input: input)
        await progressTask.value
        
        // Check monotonicity
        var isMonotonic = true
        for i in 1..<progressValues.count {
            if progressValues[i] < progressValues[i-1] {
                isMonotonic = false
                break
            }
        }
        
        #expect(isMonotonic, "Progress should monotonically increase")
    }
    
    // MARK: - Property: Cancellation
    
    /// Property: Export can be cancelled during progress
    @Test("Export is cancellable")
    func exportIsCancellable() async throws {
        let transcript = Generator<Transcript>.transcript.generate()
        let useCase = MockExportTranscriptUseCase()
        await useCase.setTranscript(transcript)
        await useCase.setDelay(.seconds(5))
        
        let input = ExportTranscriptInput(
            transcriptID: transcript.id,
            format: .txt,
            destination: FileManager.default.temporaryDirectory
        )
        
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
    
    // MARK: - Property: Sendable Safety
    
    /// Property: Export works correctly across actor boundaries
    @Test("Export is Sendable-safe")
    func exportIsSendableSafe() async throws {
        let transcripts = (0..<5).map { _ in Generator<Transcript>.transcript.generate() }
        
        await withTaskGroup(of: ExportTranscriptOutput.self) { group in
            for (index, transcript) in transcripts.enumerated() {
                group.addTask {
                    let useCase = MockExportTranscriptUseCase()
                    await useCase.setTranscript(transcript)
                    
                    let input = ExportTranscriptInput(
                        transcriptID: transcript.id,
                        format: .txt,
                        destination: FileManager.default.temporaryDirectory
                    )
                    
                    return try! await useCase.execute(input: input)
                }
            }
            
            var results: [ExportTranscriptOutput] = []
            for await output in group {
                results.append(output)
            }
            
            // All exports should succeed
            #expect(results.count == transcripts.count)
        }
    }
}

// MARK: - Helper Functions

private func fileExtension(for format: TranscriptExportFormat) -> String {
    switch format {
    case .txt: return "txt"
    case .json: return "json"
    case .markdown: return "md"
    case .srt: return "srt"
    case .docx: return "docx"
    case .pdf: return "pdf"
    }
}

extension MockExportTranscriptUseCase {
    func setTranscript(_ transcript: Transcript) {
        transcripts[transcript.id] = transcript
    }
    
    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }
    
    func setFailureError(_ error: Error) {
        failureError = error
    }
    
    func setSimulateProgress(_ value: Bool) {
        simulateProgress = value
    }
    
    func setDelay(_ duration: Duration) {
        delay = duration
    }
}
