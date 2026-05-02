# ADR-002: Actor-Protocol Conformance Strategy

## Status

Proposed (Pending wfc-pm Gate Decision)

## Context

OpenOats uses protocol-oriented programming extensively for dependency injection and service abstractions. The codebase has 400 errors related to actor-protocol conformance.

Common error patterns:
```swift
// Error: Actor-isolated method 'startStreaming' cannot satisfy 
// nonisolated protocol requirement
public actor StreamingTranscriber: StreamingTranscriptionService {
    func startStreaming() { } // Actor-isolated, but protocol expects nonisolated
}
```

Key protocols affected:
- `TranscriptionService` (multiple implementations: MLX, WhisperKit, AssemblyAI)
- `StreamingTranscriptionService` (actor-based streaming)
- `GenerateNotesUseCase` (business layer protocol)
- `TranscriptionTaskManager` (performance-critical)

## Decision

We will use a **Protocol-First Isolation Annotation** strategy:

### Rule 1: Protocols Define Isolation

Protocol methods must explicitly declare their isolation requirements:

```swift
// Protocol defines where it can be called from
public protocol TranscriptionService: Sendable {
    // MainActor for UI-facing operations
    @MainActor func startTranscription()
    
    // Nonisolated for pure queries
    nonisolated var isAvailable: Bool { get }
    
    // Actor-isolated (default) for internal state mutations
    func processChunk(_ audio: AudioChunk) async
}
```

### Rule 2: Implementations Match Protocol Isolation

Actor implementations must match the protocol's isolation annotations:

```swift
public actor MLXTranscriptionService: TranscriptionService {
    // Matches @MainActor protocol requirement
    @MainActor public func startTranscription() { }
    
    // Matches nonisolated protocol requirement
    nonisolated public var isAvailable: Bool { 
        // Pure computation, no actor state access
        MLXEngine.isLoaded 
    }
    
    // Actor-isolated by default, matches protocol
    public func processChunk(_ audio: AudioChunk) async { }
}
```

### Rule 3: Migration Path for Existing Protocols

For protocols that cannot change immediately (API compatibility):

```swift
// Step 1: Mark protocol with @preconcurrency to suppress warnings
@preconcurrency public protocol LegacyTranscriptionService {
    func transcribe() async throws -> String
}

// Step 2: Actor implementation uses nonisolated where needed
public actor NewTranscriptionService: LegacyTranscriptionService {
    // Temporarily nonisolated to satisfy protocol
    nonisolated public func transcribe() async throws -> String {
        // Bridge to actor-isolated implementation
        await internalTranscribe()
    }
    
    private func internalTranscribe() async throws -> String {
        // Actual actor-isolated implementation
    }
}

// Step 3: In next major version, update protocol isolation
```

## Consequences

### Positive

- Clear isolation semantics at protocol boundary
- Protocol implementations cannot accidentally break isolation contracts
- Compiler enforces consistency between protocol and implementation
- Gradual migration possible with @preconcurrency

### Negative

- Protocol changes may require cascade of updates
- @preconcurrency is temporary measure, creates technical debt
- Some protocols may need breaking changes eventually
- Additional annotation burden

## Decision Criteria Applied

| Criteria | Weight | Score (1-5) | Weighted |
|----------|--------|-------------|------------|
| Type Safety | High | 5 | 5.0 |
| API Compatibility | High | 4 | 4.0 |
| Performance | Medium | 4 | 2.0 |
| Maintainability | High | 5 | 5.0 |
| Migration Effort | Medium | 3 | 1.5 |
| **Total** | | | **17.5** |

Score interpretation: Higher is better (max 5 per criterion, max weighted varies by priority)

## Alternatives Considered

### Alternative 1: @preconcurrency Everywhere
- Use @preconcurrency on all protocols to suppress errors
- **Rejected**: Defeats purpose of Swift 6, creates permanent technical debt

### Alternative 2: Nonisolated Default
- Make all protocol methods nonisolated by default
- **Rejected**: Loses actor isolation benefits, allows data races

### Alternative 3: Remove Protocols
- Replace protocols with concrete actor types
- **Rejected**: Loses dependency injection benefits, breaks existing architecture

### Alternative 4: Wrapper Pattern
- Create Sendable wrappers for non-Sendable protocol implementations
- **Accepted Partially**: Used for legacy integration, but not as primary strategy

## Implementation Notes

### TASK-SW6-005: Protocol @MainActor Audit
Audit matrix for protocol isolation decisions:

| Protocol | Current State | Required Change | Justification |
|----------|---------------|-----------------|---------------|
| `GenerateNotesUseCase` | No isolation | Add `@MainActor` | UI-facing business logic |
| `TranscriptionService` | Partial | Full audit | Multiple implementations need consistency |
| `StreamingTranscriptionService` | Actor | Verify conformance | Check existing actor isolation |

### Critical Success Factor
All protocol method implementations must have isolation matching the protocol definition. This is enforced by compiler with `-strict-concurrency=complete`.

## References

- [SE-0302: Sendable](https://github.com/apple/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md)
- [SE-0338: @preconcurrency](https://github.com/apple/swift-evolution/blob/main/proposals/0338-clause-preconcurrency.md)
- TASKS.md TASK-SW6-005, TASK-SW6-006, TASK-SW6-007
- OpenOats AGENTS.md - Prohibited Patterns (no [weak self] in actors)

---
*Decision Record ID: ADR-002*  
*Epic: Swift 6 Strict Concurrency Compliance*  
*Date: 2026-05-02*
