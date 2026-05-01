# ADR 004: Swift 6.2 StrictConcurrency Strategy

## Status

Accepted

## Context

Swift 6.2 introduces StrictConcurrency which:
- Requires Sendable conformance for cross-actor types
- Prevents data races at compile time
- Will break existing code with concurrency violations

OpenOats has 36K lines of legacy code likely containing:
- Non-Sendable shared state
- Data races between transcription and UI
- Main thread blocking operations

We need a strategy that:
- Migrates to Swift 6.2 safely
- Maintains performance
- Prevents regressions

## Decision

Adopt **Swift 6.2 StrictConcurrency** with actor isolation:

**Sendable Requirements**:
- All domain entities must be Sendable
- All value types automatically Sendable (structs)
- Reference types need explicit @Sendable or actor isolation

**Actor Strategy**:
```swift
// UI layer - MainActor
@MainActor
class SessionViewModel: ObservableObject {
    @Published var transcription: String = ""
}

// Infrastructure - Custom actors
@globalActor
struct TranscriptionActor {
    static let shared = TranscriptionActor()
}

@TranscriptionActor
class MLXTranscriptionService {
    // Runs on dedicated transcription queue
}
```

**Cross-Actor Communication**:
```swift
// Domain entities are Sendable-safe
struct Transcription: Sendable {
    let text: String
    let confidence: Double
}

// Service returns Sendable data
func transcribe() async throws -> Transcription
```

**Compilation Strategy**:
- Enable `-strict-concurrency=complete` in prototype first
- Fix all warnings before migration
- Use `@preconcurrency` for legacy imports temporarily

## Consequences

### Positive
- Data race safety at compile time
- Clear concurrency boundaries
- Better performance with structured concurrency
- Future-proof for Swift 6

### Negative
- Significant migration effort for 36K lines
- Learning curve for team
- May require refactoring shared state

### Risks
- Swift 6.2 violations (HIGH) - Mitigated by prototype validation before migration
- MainActor blocking (MEDIUM) - Mitigated by background actors for heavy work

## Alternatives Considered

### 1. Stay on Swift 5.x (Rejected)
- Technical debt accumulates
- Missing concurrency safety
- Eventually forced to migrate

### 2. Partial Concurrency (Rejected)
- Mixed mode is confusing
- Doesn't provide full safety
- Harder to reason about

### 3. Actor-per-Feature (Rejected)
- Too granular
- Actor hopping overhead
- Unnecessary complexity

## References

- [Swift Concurrency Documentation](https://www.hackingwithswift.com/quick-start/concurrency)
- [Sendable Types](https://developer.apple.com/documentation/swift/sendable)
- [MainActor](https://developer.apple.com/documentation/swift/mainactor)
- TASK-011 in design plan
