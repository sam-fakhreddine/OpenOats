# ADR-001: Swift 6 Strict Concurrency Adoption

## Status

Proposed (Pending wfc-pm Gate Decision)

## Context

The OpenOats codebase currently has 1,406 Swift 6 strict concurrency errors across 50 files. The errors fall into 5 categories:
- Actor-Protocol Conformance: 400 errors
- Sendable Violations: 300 errors
- Visibility Mismatches: 150 errors
- Async-Safe Locking: 250 errors
- Type Inference Failures: 200 errors
- Other: 106 errors

The codebase is a macOS transcription application with:
- Real-time audio processing requirements (<20ms latency)
- Multiple transcription backends (MLX, WhisperKit, AssemblyAI)
- Complex actor hierarchies for audio engine and transcription services
- Heavy use of protocol-oriented programming for dependency injection

## Decision

We will adopt Swift 6 strict concurrency with `-strict-concurrency=complete` flag. We will NOT downgrade to `minimal` or `targeted` modes.

### Rationale

1. **Compile-Time Safety**: Swift 6 eliminates data race bugs at compile time, which is critical for a real-time audio application where race conditions could cause audio dropouts or crashes.

2. **Future-Proofing**: Apple is making strict concurrency the default in Xcode 16+. Adopting now prevents future migration work.

3. **Professional Standards**: Swift 6 adoption is becoming table stakes for professional macOS applications.

4. **Ecosystem Alignment**: The Swift community has established migration patterns for audio apps that we can leverage.

### Migration Strategy

We will use a 4-phase approach with intermediate validation:

```
Phase 1: Mock Infrastructure (500 errors) → Parallelizable
Phase 2: Protocol Layer (550 errors) → Sequential dependencies
Phase 3: Actor Core (250 errors) → Partial parallelization
Phase 4: Tests/CI (106 errors) → Parallelizable
```

Each phase has a checkpoint: build must pass with error count reduced by phase target before proceeding.

## Consequences

### Positive

- Data race bugs eliminated at compile time
- Clear ownership boundaries for mutable state
- Improved code maintainability through explicit isolation
- Better documentation of thread-safety assumptions
- Foundation for Swift 6.2 approachable concurrency migration

### Negative

- Initial migration cost: ~91 engineering hours
- Learning curve for team on actor isolation patterns
- Potential performance overhead from actor context switches
- Risk of breaking API changes if not carefully managed

### Mitigations

- Phased approach limits blast radius
- Property-based testing validates concurrent behavior
- Performance benchmarks ensure <5% regression
- @unchecked Sendable with SAFETY comments preserves API where needed

## Alternatives Considered

### Alternative 1: Downgrade to `-strict-concurrency=targeted`
- **Rejected**: Only solves ~30% of errors, leaves data race risks, requires future migration anyway

### Alternative 2: Downgrade to `-strict-concurrency=minimal`
- **Rejected**: Same issues as targeted mode, minimal safety guarantees

### Alternative 3: Partial adoption (only new code)
- **Rejected**: Creates technical debt, inconsistent patterns, harder to maintain

### Alternative 4: Gradual file-by-file migration
- **Partially Accepted**: Implemented within phases, but full strict mode enabled at each checkpoint

## References

- [Swift 6 Language Guide - Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [SE-0302: Sendable](https://github.com/apple/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md)
- [OpenOats AGENTS.md - Swift 6 Concurrency Section](../../../../../AGENTS.md)
- TASKS.md Phase Definitions (.wfc/epics/swift6-compliance/TASKS.md)

---
*Decision Record ID: ADR-001*  
*Epic: Swift 6 Strict Concurrency Compliance*  
*Date: 2026-05-02*
