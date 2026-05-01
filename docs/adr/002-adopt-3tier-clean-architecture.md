# ADR 002: Adopt 3-Tier Clean Architecture

## Status

Accepted

## Context

OpenOats has grown to 36K lines with no discernible architecture. Key files have become unmanageable:
- NotesView: 3.7K lines
- SessionRepository: 2.1K lines

The codebase exhibits classic "Big Ball of Mud" symptoms:
- No layer separation
- Business logic in UI
- Direct framework dependencies throughout
- Difficult to test
- Cannot swap transcription backends without UI changes

We need a structured architecture that:
- Separates concerns
- Enables testing
- Supports multiple transcription backends (MLX, WhisperKit, AssemblyAI, Parakeet)
- Allows incremental migration
- Works with Swift 6.2 StrictConcurrency

## Decision

Adopt **Clean Architecture** with 4 layers:

1. **Domain** (Innermost): Entities, value objects, core protocols
   - Zero external dependencies
   - Immutable structs only
   - Sendable-safe for Swift 6.2

2. **Business Logic**: Use cases (interactors)
   - Stateless orchestration
   - Protocol-facaded for testability
   - Async/await for concurrency

3. **Infrastructure**: External concerns
   - Transcription backends (MLX, WhisperKit, AssemblyAI)
   - Audio capture
   - Persistence (CoreData/SwiftData)
   - AI services (LLM, embeddings)

4. **Presentation**: SwiftUI + MVVM
   - @MainActor for all ViewModels
   - Thin ViewModels (delegate to interactors)
   - @Environment for dependency injection

**Dependency Rule**: Dependencies flow inward only
```
Presentation → Business → Domain ← Infrastructure
```

## Consequences

### Positive
- Clear separation of concerns
- Domain logic is testable without UI or database
- Can swap transcription backends without UI changes
- Supports Swift 6.2 StrictConcurrency
- Incremental migration possible via Strangler Fig pattern

### Negative
- More abstractions to learn
- Potential performance overhead from indirection (budget: <5%)
- 9-week migration timeline for 36K lines
- Team needs training on Clean Architecture principles

### Risks
- Migration complexity (HIGH) - Mitigated by phased approach with feature flags
- Swift 6.2 concurrency violations (HIGH) - Mitigated by prototype validation first

## Alternatives Considered

### 1. MVVM Only (Rejected)
- Still mixes business logic with UI
- Doesn't solve backend abstraction
- Insufficient for 36K line codebase

### 2. VIPER (Rejected)
- Too complex for macOS app
- Over-engineered for OpenOats scope
- Steep learning curve

### 3. TCA (The Composable Architecture) (Rejected)
- Heavy dependency on external framework
- Too opinionated for our needs
- Learning curve for team

## References

- [Clean Architecture (Uncle Bob)](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [Clean Architecture for SwiftUI](https://github.com/nalexn/clean-architecture-swiftui)
- TASK-001 through TASK-014 in design plan
