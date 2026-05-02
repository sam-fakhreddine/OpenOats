import Foundation
import Accelerate

// MARK: - FluidVadManager
/// Actor-based VAD (Voice Activity Detection) protocol implementation.
/// Provides thread-safe voice activity detection using actor isolation.
///
/// This implementation uses vDSP for efficient audio processing and follows
/// Swift 6 strict concurrency guidelines with complete actor isolation.
@available(macOS 15.0, *)
public actor FluidVadManager: VadManager {
    
    // MARK: - Types
    
    /// VAD processing configuration
    public struct Configuration: Sendable {
        /// Sample rate for processing (default: 16000 Hz)
        let sampleRate: Double
        
        /// Frame size in samples (default: 480 = 30ms at 16kHz)
        let frameSize: Int
        
        /// Voice detection threshold (default: 0.5)
        let threshold: Float
        
        /// Minimum speech duration in seconds (default: 0.25)
        let minSpeechDuration: Double
        
        /// Maximum silence duration before speech end in seconds (default: 0.5)
        let maxSilenceDuration: Double
        
        public init(
            sampleRate: Double = 16000.0,
            frameSize: Int = 480,
            threshold: Float = 0.5,
            minSpeechDuration: Double = 0.25,
            maxSilenceDuration: Double = 0.5
        ) {
            self.sampleRate = sampleRate
            self.frameSize = frameSize
            self.threshold = threshold
            self.minSpeechDuration = minSpeechDuration
            self.maxSilenceDuration = maxSilenceDuration
        }
        
        /// Default configuration optimized for speech detection
        public static let `default` = Configuration()
        
        /// Configuration optimized for real-time streaming
        public static let streaming = Configuration(
            sampleRate: 16000.0,
            frameSize: 320,  // 20ms frames for lower latency
            threshold: 0.4,
            minSpeechDuration: 0.2,
            maxSilenceDuration: 0.3
        )
    }
    
    /// VAD state machine states
    private enum State: Sendable {
        case idle
        case speechStart
        case inSpeech(startTime: Double)
        case speechEnd
    }
    
    // MARK: - Properties
    
    /// Current configuration
    private var configuration: Configuration
    
    /// Current VAD state
    private var state: State = .idle
    
    /// Ring buffer for audio samples (O(1) circular buffer)
    private var sampleBuffer: VDSPCircularAudioBuffer
    
    /// Energy history for noise floor estimation (ring buffer for O(1) operations)
    private var energyHistory: [Float]
    private var energyHistoryHead = 0
    private var energyHistoryCount = 0
    private let maxEnergyHistory = 30  // ~1 second of history

    /// Speech timing tracking
    private var currentSpeechStart: Double?
    private var lastSpeechTime: Double = 0
    private var silenceStartTime: Double?

    /// Total processed samples (for timestamp calculation)
    private var totalProcessedSamples: Int64 = 0

    /// Voice probability smoothing buffer (ring buffer for O(1) operations)
    private var probabilityBuffer: [Float]
    private var probabilityHead = 0
    private var probabilityCount = 0
    private let maxProbabilityBuffer = 5
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.sampleBuffer = VDSPCircularAudioBuffer(
            capacity: Int(configuration.sampleRate * 2.0)  // 2 seconds buffer
        )
        // Pre-allocate ring buffers with fixed capacity
        self.energyHistory = Array(repeating: 0.0, count: maxEnergyHistory)
        self.probabilityBuffer = Array(repeating: 0.0, count: maxProbabilityBuffer)
    }
    
    public init() {
        self.configuration = .default
        self.sampleBuffer = VDSPCircularAudioBuffer(
            capacity: Int(Configuration.default.sampleRate * 2.0)
        )
        self.energyHistory = Array(repeating: 0.0, count: maxEnergyHistory)
        self.probabilityBuffer = Array(repeating: 0.0, count: maxProbabilityBuffer)
    }
    
    // MARK: - VadManager Protocol
    
    func makeStreamState() async -> VadStreamState {
        VadStreamState()
    }
    
    func processStreamingChunk(
        _ samples: [Float],
        state: VadStreamState,
        config: VadConfig,
        returnSeconds: Bool,
        timeResolution: Int
    ) async throws -> VadResult {
        // Calculate current timestamp
        let currentTime = Double(totalProcessedSamples) / configuration.sampleRate
        
        // Process samples using vDSP for efficiency
        let voiceProbability = await detectVoiceProbability(samples)
        
        // Update total processed samples
        totalProcessedSamples += Int64(samples.count)
        
        // Update probability smoothing buffer using ring buffer (O(1) operation)
        probabilityBuffer[probabilityHead] = voiceProbability
        probabilityHead = (probabilityHead + 1) % maxProbabilityBuffer
        if probabilityCount < maxProbabilityBuffer {
            probabilityCount += 1
        }
        
        // Calculate smoothed probability using vDSP mean
        let smoothedProbability = calculateSmoothedProbability()
        
        // State machine transition
        let (newState, event, seconds) = await updateStateMachine(
            voiceProbability: smoothedProbability,
            currentTime: currentTime,
            samples: samples
        )
        
        return VadResult(
            state: state,
            event: event,
            seconds: seconds
        )
    }
    
    // MARK: - Voice Detection
    
    /// Detect voice probability in audio samples using energy-based detection
    private func detectVoiceProbability(_ samples: [Float]) async -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        // Write samples to circular buffer
        await sampleBuffer.write(samples)
        
        // Calculate RMS energy using vDSP
        let energy = calculateRMSEnergy(samples)
        
        // Update energy history using ring buffer (O(1) operation)
        energyHistory[energyHistoryHead] = energy
        energyHistoryHead = (energyHistoryHead + 1) % maxEnergyHistory
        if energyHistoryCount < maxEnergyHistory {
            energyHistoryCount += 1
        }
        
        // Calculate noise floor using vDSP
        let noiseFloor = calculateNoiseFloor()
        
        // Calculate signal-to-noise ratio
        let snr = energy / max(noiseFloor, 1e-10)
        
        // Convert SNR to probability using sigmoid
        let probability = sigmoid(snr - configuration.threshold)
        
        return probability
    }
    
    /// Calculate RMS energy using vDSP
    private func calculateRMSEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        var meanSquare: Float = 0
        
        // vDSP_measqv: Mean of squares (vector)
        // Calculates sum(samples[i]^2) / count
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        
        // Return RMS (square root of mean square)
        return sqrt(meanSquare)
    }
    
    /// Calculate noise floor using percentile-based estimation
    private func calculateNoiseFloor() -> Float {
        guard energyHistoryCount > 0 else { return 0.01 }

        // Collect valid elements from ring buffer
        let validHistory = Array(energyHistory.prefix(energyHistoryCount))

        // Sort energy history to find percentile
        let sorted = validHistory.sorted()
        let percentileIndex = Int(Float(sorted.count) * 0.1)  // 10th percentile
        let noiseFloor = sorted[max(0, min(percentileIndex, sorted.count - 1))]

        return max(noiseFloor, 0.001)  // Minimum noise floor
    }
    
    /// Calculate smoothed probability using vDSP mean
    private func calculateSmoothedProbability() -> Float {
        guard probabilityCount > 0 else { return 0.0 }

        // Collect valid elements from ring buffer for vDSP calculation
        let validBuffer = Array(probabilityBuffer.prefix(probabilityCount))

        var mean: Float = 0
        vDSP_meanv(validBuffer, 1, &mean, vDSP_Length(validBuffer.count))

        return mean
    }
    
    /// Sigmoid function for probability conversion
    private func sigmoid(_ x: Float) -> Float {
        return 1.0 / (1.0 + exp(-x))
    }
    
    // MARK: - State Machine
    
    /// Update the VAD state machine based on voice detection
    private func updateStateMachine(
        voiceProbability: Float,
        currentTime: Double,
        samples: [Float]
    ) async -> (State, VadEvent?, Double?) {
        let isSpeech = voiceProbability > configuration.threshold
        var event: VadEvent? = nil
        var seconds: Double? = nil
        
        switch self.state {
        case .idle:
            if isSpeech {
                currentSpeechStart = currentTime
                event = VadEvent(kind: .speechStart)
                self.state = .inSpeech(startTime: currentTime)
            }
            
        case .speechStart:
            // Should not occur - transitioned immediately to inSpeech
            // This is a fallback for any race conditions
            self.state = .idle
            
        case .inSpeech(let startTime):
            lastSpeechTime = currentTime
            
            if !isSpeech {
                // Check if silence duration exceeds threshold
                if silenceStartTime == nil {
                    silenceStartTime = currentTime
                } else if (currentTime - silenceStartTime!) >= configuration.maxSilenceDuration {
                    // Speech ended
                    seconds = currentTime - startTime
                    event = VadEvent(kind: .speechEnd)
                    currentSpeechStart = nil
                    silenceStartTime = nil
                    self.state = .idle
                }
            } else {
                // Reset silence timer
                silenceStartTime = nil
            }
            
        case .speechEnd:
            // Should not occur - transitioned immediately to idle
            // This is a fallback for any race conditions
            self.state = .idle
        }
        
        return (self.state, event, seconds)
    }
    
    // MARK: - Public API
    
    /// Get current VAD state as readable string
    public func currentStateDescription() async -> String {
        switch state {
        case .idle: return "idle"
        case .speechStart: return "speechStart"
        case .inSpeech: return "inSpeech"
        case .speechEnd: return "speechEnd"
        }
    }
    
    /// Reset the VAD state machine
    public func reset() async {
        state = .idle
        currentSpeechStart = nil
        lastSpeechTime = 0
        silenceStartTime = nil
        totalProcessedSamples = 0
        // Reset ring buffer indices (O(1) - no array reallocation needed)
        energyHistoryHead = 0
        energyHistoryCount = 0
        probabilityHead = 0
        probabilityCount = 0
        await sampleBuffer.clear()
    }
    
    /// Get current processing configuration
    public func getConfiguration() async -> Configuration {
        configuration
    }
    
    /// Update processing configuration
    public func setConfiguration(_ newConfig: Configuration) async {
        configuration = newConfig
        // Reinitialize buffer with new capacity if needed
        // Cache values before await to prevent reentrancy race
        let requiredCapacity = Int(newConfig.sampleRate * 2.0)
        let currentBuffer = sampleBuffer
        let currentCapacity = await currentBuffer.capacity
        if currentCapacity != requiredCapacity {
            sampleBuffer = VDSPCircularAudioBuffer(capacity: requiredCapacity)
        }
    }
    
    /// Get processing statistics
    public func getStatistics() async -> Statistics {
        Statistics(
            totalProcessedSamples: totalProcessedSamples,
            totalProcessedSeconds: Double(totalProcessedSamples) / configuration.sampleRate,
            currentBufferFillLevel: await sampleBuffer.fillLevel()
        )
    }
    
    /// Statistics for monitoring
    public struct Statistics: Sendable {
        public let totalProcessedSamples: Int64
        public let totalProcessedSeconds: Double
        public let currentBufferFillLevel: Double
    }
}
