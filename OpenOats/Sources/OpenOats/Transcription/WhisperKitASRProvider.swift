import Foundation
import WhisperKit

// MARK: - WhisperKitASRProvider (experimental)

/// Wraps argmaxinc/WhisperKit. Marked experimental — not the default provider.
/// Download (~600 MB) is triggered lazily on first use.
final class WhisperKitASRProvider: ASRProvider, @unchecked Sendable {
    private var initTask: Task<WhisperKit, Error>?
    private let modelName: String
    private let lock = NSLock()

    init(modelName: String = "openai_whisper-large-v3-turbo") {
        self.modelName = modelName
    }

    /// Loads WhisperKit on first call (lazy download/init).
    /// Uses a Task-based gate with NSLock to avoid TOCTOU races when
    /// multiple audio segments arrive before init completes.
    private func loadIfNeeded() async throws -> WhisperKit {
        let task: Task<WhisperKit, Error> = lock.withLock {
            if let existing = initTask {
                return existing
            }
            let newTask = Task<WhisperKit, Error> {
                try await WhisperKit(model: self.modelName)
            }
            initTask = newTask
            return newTask
        }
        return try await task.value
    }

    func transcribe(_ samples: [Float], sampleRate: Int) async throws -> String {
        let kit = try await loadIfNeeded()
        let results = try await kit.transcribe(audioArray: samples)
        return results.map(\.text).joined(separator: " ")
    }

    var modelDisplayName: String { "Whisper large-v3-turbo (experimental)" }
}
