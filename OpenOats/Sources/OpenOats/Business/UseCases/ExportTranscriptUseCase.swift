import Foundation

// MARK: - Progress Reporting Protocol

/// Protocol for progress reporting
public protocol ProgressReportingUseCase: Sendable {
    var progressStream: AsyncStream<Double> { get }
}

// MARK: - ExportTranscriptUseCase

/// Protocol definition for ExportTranscriptUseCase
public protocol ExportTranscriptUseCase: Sendable, ProgressReportingUseCase {
    func execute(input: ExportTranscriptInput) async throws -> ExportTranscriptOutput
}

/// Export format options for transcript export
public enum TranscriptExportFormatExtended: Sendable, Equatable, Hashable {
    case txt, json, markdown, srt, docx, pdf
}

/// Input for exporting transcript
public struct ExportTranscriptInput: Sendable {
    public let transcriptID: TranscriptID
    public let format: TranscriptExportFormatExtended
    public let destination: URL
    public let includeSpeakers: Bool
    public let includeTimestamps: Bool
    
    public init(
        transcriptID: TranscriptID,
        format: TranscriptExportFormatExtended,
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
public struct ExportTranscriptOutput: Sendable {
    public let exportedURL: URL
    public let bytesWritten: Int
    
    public init(
        exportedURL: URL,
        bytesWritten: Int
    ) {
        self.exportedURL = exportedURL
        self.bytesWritten = bytesWritten
    }
}

/// Exportable utterance info for transcript export
public struct ExportableUtterance: Sendable {
    public let text: String
    public let speakerName: String?
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    
    public init(
        text: String,
        speakerName: String? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) {
        self.text = text
        self.speakerName = speakerName
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - ExportTranscriptUseCase Implementation

/// Implementation of ExportTranscriptUseCase
public actor ExportTranscriptUseCaseImpl: ExportTranscriptUseCase {
    private let transcriptRepository: any TranscriptRepository
    private let fileExporter: any FileExportService
    private let utteranceRepository: (any ExportUtteranceRepository)?
    
    private var progressContinuation: AsyncStream<Double>.Continuation?
    
    nonisolated public var progressStream: AsyncStream<Double> {
        AsyncStream { continuation in
            Task {
                await self.setProgressContinuation(continuation)
            }
        }
    }
    
    public init(
        transcriptRepository: any TranscriptRepository,
        fileExporter: any FileExportService,
        utteranceRepository: (any ExportUtteranceRepository)? = nil
    ) {
        self.transcriptRepository = transcriptRepository
        self.fileExporter = fileExporter
        self.utteranceRepository = utteranceRepository
    }
    
    private func setProgressContinuation(_ continuation: AsyncStream<Double>.Continuation?) {
        self.progressContinuation = continuation
    }
    
    public func execute(input: ExportTranscriptInput) async throws -> ExportTranscriptOutput {
        // Report initial progress
        await reportProgress(0.0)
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Retrieve the transcript
        let transcriptResult = await transcriptRepository.get(by: input.transcriptID)
        let transcript: Transcript
        switch transcriptResult {
        case .success(let foundTranscript):
            transcript = foundTranscript
        case .failure(let error):
            throw error
        }
        
        await reportProgress(0.2)
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Fetch utterances if needed for speaker/timestamp info
        var utterances: [ExportableUtterance] = []
        if let utteranceRepo = utteranceRepository {
            for utteranceID in transcript.utteranceIDs {
                let result = await utteranceRepo.getExportable(by: utteranceID)
                if case .success(let utterance) = result {
                    utterances.append(utterance)
                }
            }
        }
        
        await reportProgress(0.5)
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Generate file content based on format
        let content = try await generateContent(
            transcript: transcript,
            utterances: utterances,
            format: input.format,
            includeSpeakers: input.includeSpeakers,
            includeTimestamps: input.includeTimestamps
        )
        
        await reportProgress(0.7)
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Determine file extension
        let fileExtension = fileExtension(for: input.format)
        let fileName = "\(input.transcriptID.rawValue.uuidString).\(fileExtension)"
        let exportedURL = input.destination.appendingPathComponent(fileName)
        
        // Export the file
        let exportResult = await fileExporter.export(
            content: content,
            to: exportedURL
        )
        
        await reportProgress(0.9)
        
        let bytesWritten: Int
        switch exportResult {
        case .success(let byteCount):
            bytesWritten = byteCount
        case .failure(let error):
            throw error
        }
        
        await reportProgress(1.0)
        
        return ExportTranscriptOutput(
            exportedURL: exportedURL,
            bytesWritten: bytesWritten
        )
    }
    
    private func reportProgress(_ value: Double) async {
        progressContinuation?.yield(value)
        if value >= 1.0 {
            progressContinuation?.finish()
        }
    }
    
    private func generateContent(
        transcript: Transcript,
        utterances: [ExportableUtterance],
        format: TranscriptExportFormatExtended,
        includeSpeakers: Bool,
        includeTimestamps: Bool
    ) async throws -> String {
        switch format {
        case .txt:
            return generateTXTContent(utterances: utterances, includeSpeakers: includeSpeakers, includeTimestamps: includeTimestamps)
        case .json:
            return generateJSONContent(transcript: transcript, utterances: utterances)
        case .markdown:
            return generateMarkdownContent(utterances: utterances, includeSpeakers: includeSpeakers, includeTimestamps: includeTimestamps)
        case .srt:
            return generateSRTContent(utterances: utterances)
        case .docx, .pdf:
            // These formats would require more complex handling
            // For now, export as plain text that can be converted
            return generateTXTContent(utterances: utterances, includeSpeakers: includeSpeakers, includeTimestamps: includeTimestamps)
        }
    }
    
    private func generateTXTContent(
        utterances: [ExportableUtterance],
        includeSpeakers: Bool,
        includeTimestamps: Bool
    ) -> String {
        var lines: [String] = []
        for utterance in utterances {
            var line = ""
            if includeTimestamps {
                line += "[\(formatTime(utterance.startTime))] "
            }
            if includeSpeakers, let speakerName = utterance.speakerName {
                line += "\(speakerName): "
            }
            line += utterance.text
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
    
    private func generateJSONContent(
        transcript: Transcript,
        utterances: [ExportableUtterance]
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        struct ExportData: Codable {
            let transcriptID: String
            let language: String
            let utterances: [UtteranceExport]
        }
        
        struct UtteranceExport: Codable {
            let text: String
            let speaker: String?
            let startTime: String
            let endTime: String
        }
        
        let exportData = ExportData(
            transcriptID: transcript.id.rawValue.uuidString,
            language: transcript.language,
            utterances: utterances.map { utterance in
                UtteranceExport(
                    text: utterance.text,
                    speaker: utterance.speakerName,
                    startTime: formatTime(utterance.startTime),
                    endTime: formatTime(utterance.endTime)
                )
            }
        )
        
        if let data = try? encoder.encode(exportData),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }
    
    private func generateMarkdownContent(
        utterances: [ExportableUtterance],
        includeSpeakers: Bool,
        includeTimestamps: Bool
    ) -> String {
        var content = "# Transcript\n\n"
        for utterance in utterances {
            if includeSpeakers, let speakerName = utterance.speakerName {
                content += "**\(speakerName)**"
                if includeTimestamps {
                    content += " _\(formatTime(utterance.startTime))_"
                }
                content += ":\n> \(utterance.text)\n\n"
            } else {
                if includeTimestamps {
                    content += "_\(formatTime(utterance.startTime))_: "
                }
                content += "\(utterance.text)\n\n"
            }
        }
        return content
    }
    
    private func generateSRTContent(utterances: [ExportableUtterance]) -> String {
        var lines: [String] = []
        for (index, utterance) in utterances.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(formatSRTTime(utterance.startTime)) --> \(formatSRTTime(utterance.endTime))")
            if let speakerName = utterance.speakerName {
                lines.append("\(speakerName): \(utterance.text)")
            } else {
                lines.append(utterance.text)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func formatSRTTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        let seconds = Int(timeInterval) % 60
        let milliseconds = Int((timeInterval - floor(timeInterval)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
    
    private func fileExtension(for format: TranscriptExportFormatExtended) -> String {
        switch format {
        case .txt: return "txt"
        case .json: return "json"
        case .markdown: return "md"
        case .srt: return "srt"
        case .docx: return "docx"
        case .pdf: return "pdf"
        }
    }
}

// MARK: - File Export Service Protocol

/// Protocol for file export operations
public protocol FileExportService: Sendable {
    func export(content: String, to url: URL) async -> Result<Int, StorageError>
}

// MARK: - Utterance Repository Protocol for Export

/// Protocol for utterance retrieval for export
public protocol ExportUtteranceRepository: Sendable {
    func getExportable(by id: UtteranceID) async -> Result<ExportableUtterance, StorageError>
    func getExportableUtterances(for sessionID: SessionID) async -> Result<[ExportableUtterance], StorageError>
}
