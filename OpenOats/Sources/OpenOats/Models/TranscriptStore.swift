import Foundation
import Observation

@Observable
@MainActor
final class TranscriptStore {
    private let acousticEchoWindow: TimeInterval = 1.75
    private let acousticEchoSimilarityThreshold = 0.78
    private let acousticEchoMinimumWordCount = 4
    private let acousticEchoMinimumCharacterCount = 20

    private(set) var utterances: [Utterance] = []
    private(set) var conversationState: ConversationState = .empty
    var volatileYouText: String = ""
    var volatileThemText: String = ""

    /// Count of finalized them-utterances since last state update
    private var themUtterancesSinceStateUpdate: Int = 0

    @discardableResult
    func append(_ utterance: Utterance) -> Bool {
        guard !shouldSuppressAcousticEcho(utterance) else { return false }
        utterances.append(utterance)
        if utterance.speaker == .them {
            themUtterancesSinceStateUpdate += 1
        }
        return true
    }

    func clear() {
        utterances.removeAll()
        volatileYouText = ""
        volatileThemText = ""
        conversationState = .empty
        themUtterancesSinceStateUpdate = 0
    }

    func updateConversationState(_ state: ConversationState) {
        conversationState = state
        themUtterancesSinceStateUpdate = 0
    }

    /// Whether conversation state needs a refresh (every 2-3 finalized them-utterances)
    var needsStateUpdate: Bool {
        themUtterancesSinceStateUpdate >= 2
    }

    var lastThemUtterance: Utterance? {
        utterances.last(where: { $0.speaker == .them })
    }

    /// Last N utterances for prompt context
    var recentUtterances: [Utterance] {
        Array(utterances.suffix(10))
    }

    /// Recent 6 utterances for gate/generation prompts
    var recentExchange: [Utterance] {
        Array(utterances.suffix(6))
    }

    /// Recent them-only utterances for trigger analysis
    var recentThemUtterances: [Utterance] {
        utterances.suffix(10).filter { $0.speaker == .them }
    }

    private func shouldSuppressAcousticEcho(_ utterance: Utterance) -> Bool {
        guard utterance.speaker == .you else { return false }

        let normalizedYouText = TextSimilarity.normalizedText(utterance.text)
        guard isEligibleForEchoCheck(normalizedYouText) else { return false }

        for candidate in utterances.reversed() where candidate.speaker == .them {
            let timeDelta = utterance.timestamp.timeIntervalSince(candidate.timestamp)
            guard timeDelta >= 0 else { continue }
            guard timeDelta <= acousticEchoWindow else { break }

            let normalizedThemText = TextSimilarity.normalizedText(candidate.text)
            guard isEligibleForEchoCheck(normalizedThemText) else { continue }

            let similarity = TextSimilarity.jaccard(normalizedYouText, normalizedThemText)
            let containsOther =
                normalizedYouText.contains(normalizedThemText) ||
                normalizedThemText.contains(normalizedYouText)

            guard similarity >= acousticEchoSimilarityThreshold || containsOther else { continue }

            diagLog(
                "[TRANSCRIPT-ECHO] dropped mic utterance as system-audio echo " +
                "dt=\(String(format: "%.2f", timeDelta)) " +
                "similarity=\(String(format: "%.2f", similarity)) " +
                "you='\(utterance.text.prefix(80))' them='\(candidate.text.prefix(80))'"
            )
            return true
        }

        return false
    }

    private func isEligibleForEchoCheck(_ normalizedText: String) -> Bool {
        let wordCount = normalizedText.split(separator: " ").count
        return wordCount >= acousticEchoMinimumWordCount ||
            normalizedText.count >= acousticEchoMinimumCharacterCount
    }
}
