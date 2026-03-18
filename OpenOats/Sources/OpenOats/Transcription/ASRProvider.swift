import Foundation
import FluidAudio

// MARK: - ASRProvider protocol

/// Abstracts a speech-recognition backend so TranscriptionEngine can swap
/// between Parakeet and WhisperKit (or future providers) without changing
/// calling code.
protocol ASRProvider {
    /// Transcribe a buffer of mono PCM samples at the given sample rate.
    func transcribe(_ samples: [Float], sampleRate: Int) async throws -> String
    /// Human-readable name shown in the UI and status bar.
    var modelDisplayName: String { get }
}

// MARK: - ParakeetASRProvider (default)

/// Wraps FluidAudio's AsrManager. This is the production default.
final class ParakeetASRProvider: ASRProvider, @unchecked Sendable {
    private let asrManager: AsrManager

    init(asrManager: AsrManager) {
        self.asrManager = asrManager
    }

    func transcribe(_ samples: [Float], sampleRate: Int) async throws -> String {
        let result = try await asrManager.transcribe(samples)
        return result.text
    }

    var modelDisplayName: String { "Parakeet TDT v3" }
}
