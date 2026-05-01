import Foundation
import SwiftUI

// MARK: - DefaultTranscriptViewModel

/// Default implementation of TranscriptViewModel for transcript display and editing
@MainActor
@Observable
final class DefaultTranscriptViewModel: TranscriptViewModel {
    let id: UUID
    
    var isLoading: Bool = false
    var error: PresentationError? = nil
    var transcript: Transcript? = nil
    var utterances: [UtteranceViewModel] = []
    var isTranscribing: Bool = false
    var searchQuery: String = "" {
        didSet {
            updateFilteredUtterances()
        }
    }
    var filteredUtterances: [UtteranceViewModel] = []
    var selectedSpeaker: SpeakerID? = nil {
        didSet {
            updateFilteredUtterances()
        }
    }
    var speakers: [SpeakerViewModel] = []
    var currentSearchIndex: Int? = nil
    var searchResultCount: Int {
        filteredUtterances.count
    }
    
    // Private state
    private var speakerColorMap: [SpeakerID: SpeakerColor] = [:]
    private var speakerNames: [SpeakerID: String] = [:]
    private var domainUtterances: [UtteranceEntity] = []
    private var shouldFailLoad: Bool
    
    init(shouldFailLoad: Bool = false) {
        self.id = UUID()
        self.shouldFailLoad = shouldFailLoad
    }
    
    func clearError() {
        error = nil
    }
    
    func loadTranscript(id: TranscriptID) async throws {
        guard !isLoading else {
            throw PresentationError.transcriptLoadFailed(id: id, reason: "Load already in progress")
        }
        
        isLoading = true
        isTranscribing = true
        defer { 
            isLoading = false
            isTranscribing = false
        }
        
        // Simulate failure if configured
        if shouldFailLoad {
            let failError = PresentationError.transcriptLoadFailed(id: id, reason: "Transcript not found")
            error = failError
            throw failError
        }
        
        // Create sample transcript with multiple utterances
        let sessionID = SessionID()
        
        // Create speakers
        let speaker1 = SpeakerEntity(id: SpeakerID(), name: "Alice", voiceSignature: nil)
        let speaker2 = SpeakerEntity(id: SpeakerID(), name: "Bob", voiceSignature: nil)
        let speaker3 = SpeakerEntity(id: SpeakerID(), name: "Carol", voiceSignature: nil)
        
        // Assign colors
        speakerColorMap[speaker1.id] = .blue
        speakerColorMap[speaker2.id] = .green
        speakerColorMap[speaker3.id] = .orange
        speakerNames[speaker1.id] = speaker1.name
        speakerNames[speaker2.id] = speaker2.name
        speakerNames[speaker3.id] = speaker3.name
        
        // Create utterances
        domainUtterances = [
            UtteranceEntity(
                id: UtteranceID(),
                transcriptID: id,
                speakerID: speaker1.id,
                text: "Welcome to the meeting everyone. Let's discuss the quarterly results.",
                startTime: .seconds(0),
                endTime: .seconds(5),
                confidence: 0.95
            ),
            UtteranceEntity(
                id: UtteranceID(),
                transcriptID: id,
                speakerID: speaker2.id,
                text: "Thanks Alice. I've prepared a summary of our revenue growth.",
                startTime: .seconds(6),
                endTime: .seconds(10),
                confidence: 0.92
            ),
            UtteranceEntity(
                id: UtteranceID(),
                transcriptID: id,
                speakerID: speaker3.id,
                text: "Great, I have some specific questions about the profit margins.",
                startTime: .seconds(11),
                endTime: .seconds(16),
                confidence: 0.88
            ),
            UtteranceEntity(
                id: UtteranceID(),
                transcriptID: id,
                speakerID: speaker1.id,
                text: "Let's address those after we review the overall numbers.",
                startTime: .seconds(17),
                endTime: .seconds(22),
                confidence: 0.94
            ),
            UtteranceEntity(
                id: UtteranceID(),
                transcriptID: id,
                speakerID: speaker2.id,
                text: "Revenue is up 15% quarter over quarter, which is specific word excellent growth.",
                startTime: .seconds(23),
                endTime: .seconds(29),
                confidence: 0.90
            ),
            UtteranceEntity(
                id: UtteranceID(),
                transcriptID: id,
                speakerID: speaker3.id,
                text: "That's impressive. What about our customer acquisition costs?",
                startTime: .seconds(30),
                endTime: .seconds(35),
                confidence: 0.93
            ),
            UtteranceEntity(
                id: UtteranceID(),
                transcriptID: id,
                speakerID: speaker1.id,
                text: "Good word question. Bob, can you address that?",
                startTime: .seconds(36),
                endTime: .seconds(40),
                confidence: 0.91
            ),
            UtteranceEntity(
                id: UtteranceID(),
                transcriptID: id,
                speakerID: speaker2.id,
                text: "CAC is down 8%, showing word improved efficiency in our marketing spend.",
                startTime: .seconds(41),
                endTime: .seconds(47),
                confidence: 0.89
            )
        ]
        
        // Create transcript
        transcript = Transcript(
            id: id,
            sessionID: sessionID,
            language: "en",
            utteranceIDs: domainUtterances.map { $0.id },
            isComplete: true
        )
        
        // Build speakers
        let speakerUtteranceCounts = Dictionary(grouping: domainUtterances) { $0.speakerID }
            .mapValues { $0.count }
        
        speakers = [
            SpeakerViewModel(
                id: speaker1.id,
                name: speaker1.name,
                color: speakerColorMap[speaker1.id] ?? .blue,
                utteranceCount: speakerUtteranceCounts[speaker1.id] ?? 0
            ),
            SpeakerViewModel(
                id: speaker2.id,
                name: speaker2.name,
                color: speakerColorMap[speaker2.id] ?? .green,
                utteranceCount: speakerUtteranceCounts[speaker2.id] ?? 0
            ),
            SpeakerViewModel(
                id: speaker3.id,
                name: speaker3.name,
                color: speakerColorMap[speaker3.id] ?? .orange,
                utteranceCount: speakerUtteranceCounts[speaker3.id] ?? 0
            )
        ]
        
        // Build utterance view models
        utterances = domainUtterances.map { entity in
            UtteranceViewModel(
                id: entity.id,
                speakerName: speakerNames[entity.speakerID] ?? "Unknown",
                speakerColor: speakerColorMap[entity.speakerID] ?? .blue,
                text: entity.text,
                startTime: entity.startTime,
                endTime: entity.endTime,
                confidence: entity.confidence
            )
        }
        
        // Initialize filtered utterances
        updateFilteredUtterances()
        
        // Simulate async loading
        try await Task.sleep(for: .milliseconds(50))
    }
    
    func search(_ query: String) {
        searchQuery = query
    }
    
    func nextSearchResult() {
        guard !filteredUtterances.isEmpty else {
            currentSearchIndex = nil
            return
        }
        
        if let current = currentSearchIndex {
            currentSearchIndex = (current + 1) % filteredUtterances.count
        } else {
            currentSearchIndex = 0
        }
    }
    
    func previousSearchResult() {
        guard !filteredUtterances.isEmpty else {
            currentSearchIndex = nil
            return
        }
        
        if let current = currentSearchIndex {
            if current == 0 {
                currentSearchIndex = filteredUtterances.count - 1
            } else {
                currentSearchIndex = current - 1
            }
        } else {
            currentSearchIndex = filteredUtterances.count - 1
        }
    }
    
    func export(to format: ExportFormat, at url: URL) async throws {
        guard transcript != nil else {
            let failError = PresentationError.exportFailed(format: format, reason: "No transcript loaded")
            error = failError
            throw failError
        }
        
        // Simulate export
        let content = utterances.map { "\($0.speakerName): \($0.text)" }.joined(separator: "\n\n")
        
        let data: Data
        switch format {
        case .plainText:
            data = content.data(using: .utf8) ?? Data()
        case .subtitles:
            data = generateSRT().data(using: .utf8) ?? Data()
        case .webVTT:
            data = generateWebVTT().data(using: .utf8) ?? Data()
        case .json:
            let json = try? JSONEncoder().encode(utterances)
            data = json ?? Data()
        case .markdown:
            let md = "# Transcript\n\n" + content
            data = md.data(using: .utf8) ?? Data()
        case .pdf:
            // PDF generation would require PDFKit, use plain text as fallback
            data = content.data(using: .utf8) ?? Data()
        }
        
        try data.write(to: url)
    }
    
    func editUtterance(_ utteranceId: UtteranceID, newText: String) async throws {
        guard let index = utterances.firstIndex(where: { $0.id == utteranceId }) else {
            let failError = PresentationError.validationFailed(field: "utterance", reason: "Utterance not found")
            error = failError
            throw failError
        }
        
        // Update the utterance
        let oldUtterance = utterances[index]
        utterances[index] = UtteranceViewModel(
            id: oldUtterance.id,
            speakerName: oldUtterance.speakerName,
            speakerColor: oldUtterance.speakerColor,
            text: newText,
            startTime: oldUtterance.startTime,
            endTime: oldUtterance.endTime,
            confidence: oldUtterance.confidence
        )
        
        // Update filtered utterances
        updateFilteredUtterances()
    }
    
    func jumpTo(_ timestamp: Duration) {
        // Implementation would scroll to the utterance at the given timestamp
        // For now, find the closest utterance
        guard !utterances.isEmpty else { return }
        
        let closestIndex = utterances.enumerated().min { a, b in
            abs(a.element.startTime.components.seconds - timestamp.components.seconds) <
            abs(b.element.startTime.components.seconds - timestamp.components.seconds)
        }?.offset
        
        if let index = closestIndex {
            // In a real implementation, this would trigger a scroll action
            print("Jump to utterance at index: \(index)")
        }
    }
    
    // MARK: - Private Methods
    
    private func updateFilteredUtterances() {
        var filtered = utterances
        
        // Apply speaker filter
        if let speakerId = selectedSpeaker {
            filtered = filtered.filter { utterance in
                // Find speaker by name since UtteranceViewModel doesn't have speakerID
                if let speaker = speakers.first(where: { $0.id == speakerId }) {
                    return utterance.speakerName == speaker.name
                }
                return false
            }
        }
        
        // Apply search filter
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            filtered = filtered.filter { utterance in
                utterance.text.lowercased().contains(query)
            }
            
            // Mark matching utterances as highlighted
            filtered = filtered.map { utterance in
                UtteranceViewModel(
                    id: utterance.id,
                    speakerName: utterance.speakerName,
                    speakerColor: utterance.speakerColor,
                    text: utterance.text,
                    startTime: utterance.startTime,
                    endTime: utterance.endTime,
                    confidence: utterance.confidence,
                    isHighlighted: true
                )
            }
        }
        
        filteredUtterances = filtered
        
        // Reset search index if it no longer applies
        if let current = currentSearchIndex, current >= filtered.count {
            currentSearchIndex = filtered.isEmpty ? nil : 0
        }
    }
    
    private func generateSRT() -> String {
        var srt = ""
        for (index, utterance) in utterances.enumerated() {
            let start = formatTimeForSRT(utterance.startTime)
            let end = formatTimeForSRT(utterance.endTime)
            srt += "\(index + 1)\n"
            srt += "\(start) --> \(end)\n"
            srt += "\(utterance.speakerName): \(utterance.text)\n\n"
        }
        return srt
    }
    
    private func generateWebVTT() -> String {
        var vtt = "WEBVTT\n\n"
        for utterance in utterances {
            let start = formatTimeForWebVTT(utterance.startTime)
            let end = formatTimeForWebVTT(utterance.endTime)
            vtt += "\(start) --> \(end)\n"
            vtt += "\(utterance.speakerName): \(utterance.text)\n\n"
        }
        return vtt
    }
    
    private func formatTimeForSRT(_ duration: Duration) -> String {
        let totalSeconds = duration.components.seconds
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let milliseconds = Int(duration.components.attoseconds / 1_000_000_000_000_000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
    
    private func formatTimeForWebVTT(_ duration: Duration) -> String {
        let totalSeconds = duration.components.seconds
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let milliseconds = Int(duration.components.attoseconds / 1_000_000_000_000_000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }
}
