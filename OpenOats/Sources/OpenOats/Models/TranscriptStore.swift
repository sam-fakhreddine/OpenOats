import Foundation
import Observation

@Observable
@MainActor
final class TranscriptStore {
    private(set) var utterances: [Utterance] = []
    private(set) var conversationState: ConversationState = .empty
    var volatileYouText: String = ""
    var volatileThemText: String = ""

    /// Count of finalized them-utterances since last state update
    private var themUtterancesSinceStateUpdate: Int = 0

    func append(_ utterance: Utterance) {
        utterances.append(utterance)
        switch utterance.speaker {
        case .them, .namedSpeaker:
            themUtterancesSinceStateUpdate += 1
        case .you:
            break
        }
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

    /// Re-labels a finalised utterance with a diarization-derived speaker.
    /// No-op if the utterance ID is not found (already persisted or not present).
    func relabelUtterance(id: UUID, speaker: Speaker) {
        guard let idx = utterances.firstIndex(where: { $0.id == id }) else { return }
        let old = utterances[idx]
        utterances[idx] = Utterance(id: old.id, text: old.text, speaker: speaker, timestamp: old.timestamp)
    }

    /// Whether conversation state needs a refresh (every 2-3 finalized them-utterances)
    var needsStateUpdate: Bool {
        themUtterancesSinceStateUpdate >= 2
    }

    var lastThemUtterance: Utterance? {
        utterances.last(where: {
            switch $0.speaker {
            case .them, .namedSpeaker: return true
            case .you: return false
            }
        })
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
        utterances.suffix(10).filter {
            switch $0.speaker {
            case .them, .namedSpeaker: return true
            case .you: return false
            }
        }
    }
}
