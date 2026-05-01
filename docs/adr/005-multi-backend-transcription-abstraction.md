# ADR 005: Multi-Backend Transcription Abstraction

## Status

Accepted

## Context

OpenOats needs to support multiple transcription backends:
1. **MLX** - Local, Apple Silicon optimized, fastest
2. **WhisperKit** - Local, CoreML, good accuracy
3. **AssemblyAI** - Cloud, high accuracy, requires network
4. **Parakeet** - Local, MLX-based, specialized models

Current code has hardcoded MLX dependencies throughout, making it impossible to:
- Switch backends based on availability
- Fallback from local to cloud
- A/B test different backends
- Support user preferences

## Decision

Use **Repository Pattern** with protocol abstraction:

**Protocol Hierarchy** (simplified per architect recommendation):
```swift
protocol TranscriptionService: Sendable {
    var capabilities: TranscriptionCapabilities { get }
    func transcribe(audio: AudioData) async throws -> Transcription
    func transcribeStreaming(audioStream: AsyncStream<AudioBuffer>) -> AsyncThrowingStream<TranscriptionSegment, Error>
}

struct TranscriptionCapabilities {
    let supportsStreaming: Bool
    let supportsBatch: Bool
    let requiresNetwork: Bool
    let recommendedFor: [UseCase]
}
```

**Implementations**:
```swift
struct MLXTranscriptionService: TranscriptionService {
    let capabilities = TranscriptionCapabilities(
        supportsStreaming: true,
        supportsBatch: true,
        requiresNetwork: false,
        recommendedFor: [.realTime, .highPerformance]
    )
    
    func transcribe(audio: AudioData) async throws -> Transcription {
        // MLX implementation
    }
}

struct AssemblyAITranscriptionService: TranscriptionService {
    let capabilities = TranscriptionCapabilities(
        supportsStreaming: true,
        supportsBatch: true,
        requiresNetwork: true,
        recommendedFor: [.maximumAccuracy, .cloudOnly]
    )
    
    func transcribe(audio: AudioData) async throws -> Transcription {
        // HTTP API implementation
    }
}
```

**Backend Selection Strategy**:
```swift
struct TranscriptionServiceSelector {
    func selectService(for useCase: UseCase, availableServices: [TranscriptionService]) -> TranscriptionService {
        // Priority: User preference > Use case match > Availability > Fallback
        availableServices
            .filter { $0.capabilities.recommendedFor.contains(useCase) }
            .first { isAvailable($0) }
            ?? availableServices.first { isAvailable($0) }
            ?? availableServices.first! // Cloud fallback always available
    }
}
```

**Error Mapping**:
```swift
enum TranscriptionError: Error {
    case backendFailed(backend: String, reason: String, recoverable: Bool)
    case noBackendAvailable
    case networkRequiredButOffline
}
```

## Consequences

### Positive
- Easy to add new backends
- Runtime backend switching
- Fallback chains for reliability
- A/B testing capability
- User preference support

### Negative
- Protocol overhead (minimal)
- Need to map errors from each backend
- Configuration complexity per backend

### Risks
- Multi-provider complexity (MEDIUM) - Mitigated by adapter pattern and comprehensive error mapping

## Alternatives Considered

### 1. Enum-Based Backend (Rejected)
- Not extensible without code changes
- Violates Open/Closed principle
- Harder to test

### 2. Strategy Pattern with Classes (Rejected)
- Reference types harder to make Sendable
- Protocols are more Swift-idiomatic
- Better for DI

### 3. Single Backend Only (Rejected)
- Doesn't meet requirements
- No fallback capability
- Vendor lock-in

## References

- [Repository Pattern](https://martinfowler.com/eaaCatalog/repository.html)
- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)
- [MLX Swift](https://github.com/ml-explore/mlx-swift)
- TASK-010 in design plan
