# ADR-003: @unchecked Sendable Safety Policy

## Status

Proposed (Pending wfc-pm Gate Decision)

## Context

The codebase requires `@unchecked Sendable` conformance for some types that cannot automatically satisfy the compiler's Sendable checks, but are provably thread-safe.

Common scenarios:
1. **MLX Model Wrappers**: MLX models are not Sendable, but are only accessed within actor isolation
2. **Legacy Types**: Existing types with complex state that would require breaking API changes to make fully Sendable
3. **Performance-Critical Paths**: Types where actor isolation would introduce unacceptable overhead

The risk: `@unchecked Sendable` bypasses compiler verification. Without proper documentation, future maintainers may introduce data races.

## Decision

We establish a **Strict @unchecked Sendable Policy** with three levels:

### Level 1: Preferred - Proper Sendable

Use compiler-verified Sendable wherever possible:

```swift
// Automatic Sendable (struct with Sendable properties)
public struct TranscriptionConfig: Sendable {
    let modelSize: ModelSize
    let language: Language
}

// Explicit Sendable with proper isolation
public actor TranscriptionService: Sendable {
    // Actor isolation provides Sendable conformance
}
```

### Level 2: Conditional - @preconcurrency Import

For external libraries that are thread-safe but not marked Sendable:

```swift
// Import with @preconcurrency to suppress warnings
@preconcurrency import MLX

// Use types normally - compiler trusts they are Sendable
// Only if library is actually thread-safe!
```

**@preconcurrency is preferred over @unchecked Sendable** when:
- The type comes from an external library
- The library is demonstrably thread-safe (immutable, actor-protected)
- We expect the library to add Sendable conformance in future versions

### Level 3: Restricted - @unchecked Sendable

Only use @unchecked Sendable when:

1. The type manages non-Sendable external state (e.g., MLX models)
2. The type is accessed ONLY within actor isolation
3. Proper Sendable would require breaking API changes
4. Performance requirements prevent actor isolation
5. Documented with SAFETY comment (REQUIRED)

## SAFETY Comment Format

Every @unchecked Sendable MUST have a SAFETY comment directly above the conformance:

```swift
/*
 SAFETY: This type is @unchecked Sendable because:
 - All mutable state is protected by actor isolation
 - The wrapped MLX model is accessed only within actor context
 - No direct mutable state escapes the actor boundary
 - Thread-safety verified through property-based testing (REQ-015)
 */
private struct AnySendableMLXModel: @unchecked Sendable {
    let model: MLXModel  // Immutable reference, actual mutation in actor
}
```

### Required SAFETY Elements

1. **SAFETY:** marker (mandatory for tooling detection)
2. **Thread-safety rationale**: Why is this type actually thread-safe?
3. **Access pattern**: Where/how is the type accessed?
4. **Verification method**: How was thread-safety validated?

## Decision Tree

```
Need Sendable conformance?
├── Can use proper Sendable (struct with Sendable properties)?
│   └── YES → Use compiler-verified Sendable (Level 1)
│
├── External library type that's thread-safe?
│   └── YES → Use @preconcurrency import (Level 2)
│
├── Internal type with non-Sendable state?
│   ├── Can refactor to proper actor isolation?
│   │   └── YES → Refactor and use proper Sendable (Level 1)
│   │
│   └── NO → @unchecked Sendable with SAFETY comment (Level 3)
│       ├── Add SAFETY comment
│       ├── Document access patterns
│       └── Add property-based tests
```

## Consequences

### Positive

- All @unchecked Sendable types have documented thread-safety rationale
- Code review can verify SAFETY comments match implementation
- Future maintainers understand thread-safety assumptions
- Tooling can detect undocumented @unchecked Sendable
- Clear path to proper Sendable when APIs can change

### Negative

- Additional documentation burden
- SAFETY comments must be maintained with code changes
- Some legitimate cases may be blocked by strict policy
- Requires code review discipline

## Enforcement

### Compiler Verification (TASK-SW6-013)

Script to verify all @unchecked Sendable have SAFETY comments:

```bash
#!/bin/bash
# verify_safety_comments.sh

UNCHECKED_COUNT=$(grep -r "@unchecked Sendable" --include="*.swift" OpenOats/Sources/ | wc -l)
SAFETY_COUNT=$(grep -B2 "@unchecked Sendable" --include="*.swift" -r OpenOats/Sources/ | grep -c "SAFETY:")

echo "@unchecked Sendable occurrences: $UNCHECKED_COUNT"
echo "SAFETY comments found: $SAFETY_COUNT"

if [ "$UNCHECKED_COUNT" -eq "$SAFETY_COUNT" ]; then
    echo "✅ All @unchecked Sendable have SAFETY comments"
    exit 0
else
    echo "❌ Missing SAFETY comments: $((UNCHECKED_COUNT - SAFETY_COUNT))"
    # List offenders
    grep -B2 "@unchecked Sendable" --include="*.swift" -r OpenOats/Sources/ | grep -v "SAFETY:" | grep -v "@unchecked"
    exit 1
fi
```

### Code Review Checklist

- [ ] Every @unchecked Sendable has SAFETY comment directly above it
- [ ] SAFETY comment explains thread-safety rationale
- [ ] Access patterns are documented
- [ ] Verification method is specified

## Alternatives Considered

### Alternative 1: Ban @unchecked Sendable Entirely
- Force all types to be properly Sendable
- **Rejected**: Would require breaking API changes, some external types cannot be made Sendable

### Alternative 2: Allow @unchecked Sendable Without Documentation
- Trust developers to use correctly
- **Rejected**: Future maintainers won't understand thread-safety assumptions

### Alternative 3: Use @preconcurrency for Everything
- Import all external libraries with @preconcurrency
- **Rejected**: Hides real safety issues, @preconcurrency should be targeted

## References

- [SE-0302: Sendable](https://github.com/apple/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md)
- [Apple Concurrency Documentation](https://developer.apple.com/documentation/swift/sendable)
- OpenOats AGENTS.md - Critical Rules: Security (DPS-8)
- PROPERTIES.md - SAFETY-004
- TASKS.md - TASK-SW6-013

---
*Decision Record ID: ADR-003*  
*Epic: Swift 6 Strict Concurrency Compliance*  
*Date: 2026-05-02*
