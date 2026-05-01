# ADR 003: Protocol-Based Dependency Injection

## Status

Accepted

## Context

OpenOats needs to support multiple transcription backends:
- MLX (local, Apple Silicon optimized)
- WhisperKit (local, CoreML)
- AssemblyAI (cloud)
- Parakeet (local, MLX-based)

Current code has hardcoded dependencies making it impossible to:
- Switch backends at runtime
- Test with mocks
- Add new backends without UI changes

We need a DI strategy that:
- Enables backend swapping
- Supports testing
- Works with SwiftUI
- Doesn't require external DI frameworks

## Decision

Use **Protocol-Based Dependency Injection** with constructor injection:

**Pattern**: Inner layers declare protocols, outer layers implement

```swift
// Domain layer declares
protocol TranscriptionService: Sendable {
    func transcribe(audio: AudioData) async throws -> Transcription
}

// Infrastructure layer implements
struct MLXTranscriptionService: TranscriptionService {
    func transcribe(audio: AudioData) async throws -> Transcription {
        // MLX implementation
    }
}
```

**DI Container**: Composition root at app startup
```swift
struct AppContainer {
    let transcriptionService: TranscriptionService
    let sessionRepository: SessionRepository
    
    static func production() -> AppContainer {
        AppContainer(
            transcriptionService: MLXTranscriptionService(),
            sessionRepository: CoreDataSessionRepository()
        )
    }
    
    static func testing() -> AppContainer {
        AppContainer(
            transcriptionService: MockTranscriptionService(),
            sessionRepository: MockSessionRepository()
        )
    }
}
```

**SwiftUI Integration**: @Environment
```swift
@main
struct OpenOatsApp: App {
    let container = AppContainer.production()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.container, container)
        }
    }
}
```

## Consequences

### Positive
- No external DI framework needed
- Compile-time safety
- Easy to test with mocks
- Backend swapping at composition root
- Works with SwiftUI lifecycle

### Negative
- More boilerplate than runtime DI
- Manual protocol definition
- Container can grow large

### Risks
- DI complexity (MEDIUM) - Mitigated by simplifying to 2 factories (ServiceFactory + CompositionRoot)

## Alternatives Considered

### 1. Swinject (Rejected)
- External dependency
- Runtime resolution (less safe)
- Additional learning curve

### 2. Factory Library (Rejected)
- External dependency
- Overkill for our needs
- Protocol-based DI is native Swift

### 3. Singleton Pattern (Rejected)
- Hard to test
- Global mutable state
- Violates dependency inversion

## References

- [Dependency Inversion Principle](https://en.wikipedia.org/wiki/Dependency_inversion_principle)
- [Clean Architecture for SwiftUI - DI](https://nalexn.github.io/clean-architecture-swiftui/)
- TASK-007 in design plan
