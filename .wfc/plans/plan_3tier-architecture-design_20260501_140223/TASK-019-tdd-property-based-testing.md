# TASK-019: TDD + Property-Based Testing Strategy

## Overview

Define the Test-Driven Development (TDD) workflow with property-based testing for the OpenOats 3-tier architecture implementation.

## TDD Workflow (Agent Handoff)

### Phase 1: Test Agent (RED Phase)
**Agent A - Test Writer**
- Writes comprehensive property-based tests
- Defines invariants and properties
- Creates example-based tests for edge cases
- **Constraint**: Cannot see implementation
- **Output**: Test file with all tests failing (RED)

### Phase 2: Implementation Agent (GREEN Phase)
**Agent B - Implementer**
- Receives test specifications only (signatures, expected behavior)
- Implements minimum code to pass tests
- **Constraint**: No access to test implementation details
- **Output**: Implementation + passing tests (GREEN)

### Phase 3: Refactor Agent (Optional)
**Agent C - Refactorer**
- Improves code quality while maintaining passes
- Performance optimizations
- Documentation
- **Output**: Refactored code + still passing tests

## Property-Based Testing Strategy

### Framework: SwiftCheck (or similar)
```swift
import SwiftCheck

// Property: All IDs are unique
property("Generated IDs are unique") <- forAll { (id1: MeetingID, id2: MeetingID) in
    return id1 == id2 || id1 != id2 // Tautology for value types
}

// Property: Transcription confidence is always 0...1
property("Confidence in valid range") <- forAll { (transcription: Transcription) in
    return transcription.confidence >= 0.0 && transcription.confidence <= 1.0
}

// Property: Session duration is always positive
property("Duration is positive") <- forAll { (session: Session) in
    return session.duration >= Duration.zero
}
```

### Invariants by Layer

#### Domain Layer
- **ID Uniqueness**: All generated IDs are unique
- **Immutable Value Semantics**: Mutations create new instances
- **Valid Ranges**: Confidence 0...1, timestamps valid, etc.
- **Sendable Safety**: All types safe for concurrent access

#### Business Logic Layer
- **Use Case Idempotency**: Same input → same output
- **Error Propagation**: All errors map correctly
- **Cancellation**: Long-running operations cancellable

#### Infrastructure Layer
- **Resource Cleanup**: All resources released on deinit
- **Thread Safety**: No data races under concurrent access
- **Bounded Memory**: Memory usage stays within limits

### Generators (Arbitrary Instances)

```swift
extension MeetingID: Arbitrary {
    static var arbitrary: Gen<MeetingID> {
        Gen<UUID>.arbitrary.map { MeetingID($0) }
    }
}

extension Transcription: Arbitrary {
    static var arbitrary: Gen<Transcription> {
        Gen<(String, Double, Duration)>.arbitrary.map { text, confidence, duration in
            Transcription(
                id: TranscriptID.arbitrary.generate,
                text: text,
                confidence: max(0.0, min(1.0, confidence)),
                duration: duration
            )
        }
    }
}
```

## Test Organization

```
OpenOats/Tests/
├── PropertyBased/
│   ├── DomainProperties.swift
│   ├── BusinessLogicProperties.swift
│   └── InfrastructureProperties.swift
├── Unit/
│   ├── DomainTests/
│   ├── BusinessLogicTests/
│   └── InfrastructureTests/
└── Integration/
    └── EndToEndTests.swift
```

## Acceptance Criteria

- [ ] Property-based testing framework selected (SwiftCheck or alternative)
- [ ] Generators defined for all domain types
- [ ] Invariants documented for each layer
- [ ] TDD workflow defined (3-phase agent handoff)
- [ ] Context isolation protocol documented
- [ ] Example property tests for each layer
- [ ] Shrinking behavior verified
- [ ] CI integration for property tests

## Formal Properties

- **SAFETY**: Property tests catch edge cases human testers miss
- **LIVENESS**: Generative testing explores full input space
- **INVARIANT**: All invariants hold for arbitrary inputs

## Dependencies

- TASK-001 (Domain entities defined)
- TASK-002 (Error types defined)

## Notes

This task defines the testing strategy. Actual test implementation happens during the implementation phase for each slice.
