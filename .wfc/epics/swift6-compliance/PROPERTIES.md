# Swift 6 Strict Concurrency Compliance - PROPERTIES.md

## Plan Overview

**Epic**: Swift 6 Strict Concurrency Compliance  
**Source**: `.wfc/epics/swift6-compliance/ba-output.json`  
**Total Errors**: 1,406 errors across 50 files  
**Compiler Flag**: `-strict-concurrency=complete`

This document defines formal properties for Swift 6 strict concurrency compliance. These properties are used for verification, testing, and as acceptance criteria for implementation tasks.

---

## Property Categories

| Category | Count | Verification Method |
|----------|-------|---------------------|
| SAFETY | 8 | Compiler + Static Analysis |
| LIVENESS | 3 | Runtime Testing |
| INVARIANT | 6 | Property-Based Testing |
| PERFORMANCE | 4 | Benchmarking |
| **Total** | **21** | **Mixed** |

---

## SAFETY Properties

### SAFETY-001: No Data Races at Compile Time

**Type**: SAFETY  
**Priority**: Critical  
**Related Tasks**: TASK-SW6-001 through TASK-SW6-020  
**Related Requirements**: REQ-001, REQ-002, REQ-004

**Formal Statement**:
```
FORALL type T crossing actor boundary A -> B:
    T conforms to Sendable
    OR
    T is @unchecked Sendable with documented SAFETY rationale
```

**Rationale**: Swift 6 strict concurrency guarantees data race safety at compile time. All types that cross actor boundaries must either conform to Sendable (compiler-verified) or be explicitly marked @unchecked Sendable with a documented safety rationale.

**Observable**:
- `swift build -Xswiftc -strict-concurrency=complete` produces zero Sendable violations
- No `@unchecked Sendable` without accompanying SAFETY comment

**Verification**:
```bash
swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep -c "Sendable"
# Expected: 0
```

---

### SAFETY-002: Actor-Protocol Conformance Consistency

**Type**: SAFETY  
**Priority**: Critical  
**Related Tasks**: TASK-SW6-005, TASK-SW6-006, TASK-SW6-007  
**Related Requirements**: REQ-001

**Formal Statement**:
```
FORALL actor A conforming to protocol P:
    FORALL methods m in P:
        isolation(m in A) == isolation(m in P)
        WHERE isolation = { @MainActor, nonisolated, actor-isolated }
```

**Rationale**: Actor-isolated methods cannot satisfy nonisolated protocol requirements. All protocol methods must have matching isolation annotations between the protocol definition and actor implementation.

**Observable**:
- Zero "Actor-isolated method cannot satisfy protocol requirement" errors
- Protocol methods explicitly annotated with `@MainActor`, `nonisolated`, or left actor-isolated

**Verification**:
```bash
swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep -c "cannot satisfy"
# Expected: 0
```

---

### SAFETY-003: No Unsafe Locking in Async Contexts

**Type**: SAFETY  
**Priority**: Critical  
**Related Tasks**: TASK-SW6-010, TASK-SW6-011  
**Related Requirements**: REQ-004

**Formal Statement**:
```
FORALL locking primitive L in codebase:
    L is NOT { NSLock, NSRecursiveLock }
    OR
    L is wrapped in actor-isolated type with proper safety documentation
```

**Rationale**: NSLock and NSRecursiveLock are not Sendable and cannot be used across async boundaries. They must be replaced with actor isolation or wrapped in Sendable-safe containers.

**Observable**:
- Zero NSLock usage in files with async functions
- All synchronization through actors or checked continuations

**Verification**:
```bash
grep -r "NSLock\|NSRecursiveLock" --include="*.swift" OpenOats/Sources/
# Expected: Empty or only in properly isolated wrappers with SAFETY comments
```

---

### SAFETY-004: @unchecked Sendable Documentation

**Type**: SAFETY  
**Priority**: High  
**Related Tasks**: TASK-SW6-013  
**Related Requirements**: REQ-007

**Formal Statement**:
```
FORALL type T with @unchecked Sendable conformance:
    EXISTS comment C immediately preceding T:
        C contains "SAFETY:" marker
        AND
        C explains thread-safety rationale for T
```

**Rationale**: @unchecked Sendable bypasses compiler verification. Each instance must have documented proof of thread-safety for code review and maintenance.

**Observable**:
- Every @unchecked Sendable has SAFETY comment above it
- Comments explain why the type is thread-safe (immutable, locked, etc.)

**Verification**:
```bash
grep -B2 "@unchecked Sendable" --include="*.swift" -r OpenOats/Sources/ | grep -c "SAFETY:"
# Should match count of @unchecked Sendable occurrences
```

---

### SAFETY-005: Nonisolated Member Immutability

**Type**: SAFETY  
**Priority**: High  
**Related Tasks**: TASK-SW6-009  
**Related Requirements**: REQ-001

**Formal Statement**:
```
FORALL member M in actor A:
    IF M is marked nonisolated:
        M is either:
            - Immutable property (let)
            - Pure function (no side effects, no mutable state access)
            - Computed property depending only on immutable state
```

**Rationale**: nonisolated members can be called from outside the actor without await. They must not access mutable actor state to prevent data races.

**Observable**:
- nonisolated only used on let properties or pure functions
- No nonisolated var properties
- SAFETY comments on non-obvious nonisolated declarations

**Verification**:
```bash
grep -n "nonisolated var" --include="*.swift" -r OpenOats/Sources/
# Expected: Empty (nonisolated should only be on let or func)
```

---

### SAFETY-006: Visibility Consistency Across Actor Boundaries

**Type**: SAFETY  
**Priority**: Medium  
**Related Tasks**: TASK-SW6-008  
**Related Requirements**: REQ-003

**Formal Statement**:
```
FORALL protocol P:
    FORALL implementations I of P:
        visibility(I) >= visibility(P)
        AND
        visibility matches across all implementations
```

**Rationale**: Access control must be consistent across actor boundaries to maintain ABI compatibility and prevent accidental visibility escalations.

**Observable**:
- Zero "access control mismatch" errors
- All protocol implementations have equal or greater visibility than protocol

**Verification**:
```bash
swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep -c "access control"
# Expected: 0
```

---

### SAFETY-007: [weak self] in Actor Tasks

**Type**: SAFETY  
**Priority**: High  
**Related Tasks**: TASK-SW6-007, TASK-SW6-012  
**Related Requirements**: REQ-001

**Formal Statement**:
```
FORALL Task creation T in actor A:
    T does NOT use [weak self]
    OR
    T has explicit justification for weak capture
```

**Rationale**: Actors already capture self strongly. Using [weak self] in actor Task closures is unnecessary and can lead to premature deallocation.

**Observable**:
- No [weak self] in actor-isolated Task closures
- Direct self capture in actor Task { } blocks

**Verification**:
```bash
grep -n "Task.*\[weak self\]" --include="*.swift" -r OpenOats/Sources/
# Expected: Empty or only in non-actor contexts
```

---

### SAFETY-008: No defer with Async Calls

**Type**: SAFETY  
**Priority**: Medium  
**Related Tasks**: All tasks (general pattern)  
**Related Requirements**: REQ-001

**Formal Statement**:
```
FORALL defer statement D:
    D does NOT contain await expression
```

**Rationale**: defer statements execute synchronously and cannot contain async calls. Such patterns must be restructured.

**Observable**:
- Zero compiler errors about defer containing async calls
- Cleanup code uses explicit do/catch instead of defer for async cleanup

**Verification**:
```bash
swift build 2>&1 | grep -c "defer.*await"
# Expected: 0
```

---

## LIVENESS Properties

### LIVENESS-001: Actor State Progress

**Type**: LIVENESS  
**Priority**: Critical  
**Related Tasks**: TASK-SW6-012  
**Related Requirements**: REQ-004

**Formal Statement**:
```
FORALL actor A with state S:
    FORALL operations O on S:
        O eventually completes
        AND
        O does not permanently block A's executor
```

**Rationale**: Actor-isolated operations must not deadlock or permanently block the actor. All state transitions must complete.

**Observable**:
- Audio processing continues without hangs
- State transitions complete in bounded time

**Verification**:
- Property-based tests with timeout constraints
- Stress tests with concurrent operations

---

### LIVENESS-002: Streaming Transcription Continuity

**Type**: LIVENESS  
**Priority**: Critical  
**Related Tasks**: TASK-SW6-006, TASK-SW6-012  
**Related Requirements**: REQ-010

**Formal Statement**:
```
FORALL streaming transcription session T:
    IF audio input A is provided:
        THEN transcription output O is eventually produced
        AND
        latency(A -> O) < 20ms
```

**Rationale**: Streaming transcription must not deadlock or hang. Audio input must eventually produce transcription output with acceptable latency.

**Observable**:
- Streaming transcriptions continue without interruption
- Latency remains below 20ms threshold

**Verification**:
- Performance benchmarks (TASK-SW6-018)
- Continuous streaming tests

---

### LIVENESS-003: Test Suite Completion

**Type**: LIVENESS  
**Priority**: High  
**Related Tasks**: TASK-SW6-014, TASK-SW6-015  
**Related Requirements**: REQ-006

**Formal Statement**:
```
FORALL test cases T in OpenOatsTests:
    T compiles with -strict-concurrency=complete
    AND
    T executes without deadlock
    AND
    T eventually terminates (pass or fail)
```

**Rationale**: All tests must compile and execute. No tests should hang indefinitely due to concurrency issues.

**Observable**:
- Full test suite completes in bounded time
- No test hangs or deadlocks

**Verification**:
```bash
timeout 300 swift test -Xswiftc -strict-concurrency=complete
# Should complete within 5 minutes
```

---

## INVARIANT Properties

### INVARIANT-001: Circular Buffer Capacity

**Type**: INVARIANT  
**Priority**: Critical  
**Related Tasks**: TASK-SW6-011  
**Related Requirements**: REQ-004, REQ-015

**Formal Statement**:
```
FORALL CircularAudioBuffer B:
    AT ALL TIMES:
        B.count >= 0
        AND
        B.count <= B.capacity
        AND
        B.head >= 0 AND B.head < B.capacity
        AND
        B.tail >= 0 AND B.tail < B.capacity
```

**Rationale**: Circular buffer must maintain structural invariants regardless of concurrent access patterns.

**Observable**:
- Buffer never overflows or underflows
- Head/tail pointers always within valid range

**Verification**:
```swift
@Test(arguments: randomSampleArrays())
func circularBufferCountInvariant(samples: [Float]) async {
    let buffer = CircularAudioBuffer(capacity: 1000)
    await buffer.append(samples)
    
    let count = await buffer.count
    #expect(count >= 0)
    #expect(count <= 1000)
}
```

---

### INVARIANT-002: Actor State Consistency

**Type**: INVARIANT  
**Priority**: Critical  
**Related Tasks**: TASK-SW6-012  
**Related Requirements**: REQ-004

**Formal Statement**:
```
FORALL actor A with state S:
    AT ALL TIMES:
        S satisfies consistency constraints C(S)
        WHERE C depends on specific actor type
```

**Examples**:
- `TranscriptionEngine`: `isRecording` implies `activeSession != nil`
- `StreamingTranscriber`: `isStreaming` implies `tapInstalled == true`

**Rationale**: Actor state must maintain consistency invariants across all operations.

**Verification**:
- State machine property tests
- Invariant assertions in debug builds

---

### INVARIANT-003: Transcription Session Uniqueness

**Type**: INVARIANT  
**Priority**: High  
**Related Tasks**: TASK-SW6-012  
**Related Requirements**: REQ-004

**Formal Statement**:
```
FORALL TranscriptionEngine E:
    AT ALL TIMES:
        E.activeSessions.count <= 1 per audio source
        OR
        E.activeSessions has non-overlapping audio sources
```

**Rationale**: Only one transcription session should be active per audio source to prevent resource conflicts.

**Verification**:
- Unit tests for session lifecycle
- Concurrent session creation tests

---

### INVARIANT-004: Sendable Conformance Preservation

**Type**: INVARIANT  
**Priority**: High  
**Related Tasks**: All tasks  
**Related Requirements**: REQ-002

**Formal Statement**:
```
FORALL type T:
    IF T conforms to Sendable:
        THEN all stored properties of T are Sendable
        AND
        T does not introduce new non-Sendable state
```

**Rationale**: Sendable conformance must be preserved through all mutations and extensions.

**Verification**:
- Compiler enforcement via -strict-concurrency=complete
- Protocol extension audit

---

### INVARIANT-005: Audio Buffer Non-Negativity

**Type**: INVARIANT  
**Priority**: Medium  
**Related Tasks**: TASK-SW6-011  
**Related Requirements**: REQ-015

**Formal Statement**:
```
FORALL audio buffer B:
    AT ALL TIMES:
        FORALL samples s in B:
            s >= -1.0 AND s <= 1.0 (normalized)
            OR
            s is finite (not NaN, not Infinity)
```

**Rationale**: Audio samples must remain in valid range regardless of processing.

**Verification**:
- Property-based tests for sample bounds
- Fuzz testing with edge case inputs

---

### INVARIANT-006: Error State Recovery

**Type**: INVARIANT  
**Priority**: Medium  
**Related Tasks**: All tasks  
**Related Requirements**: REQ-010

**Formal Statement**:
```
FORALL actor A:
    IF error E occurs in A:
        THEN A eventually reaches valid error state
        AND
        A can recover to normal state
        AND
        A resources are properly released
```

**Rationale**: Error conditions must not leave actors in undefined states.

**Verification**:
- Error injection tests
- Resource leak detection

---

## PERFORMANCE Properties

### PERFORMANCE-001: Audio Processing Latency

**Type**: PERFORMANCE  
**Priority**: Critical  
**Related Tasks**: TASK-SW6-011, TASK-SW6-012, TASK-SW6-018  
**Related Requirements**: REQ-010, REQ-013

**Formal Statement**:
```
FORALL audio processing operation O:
    latency(O) < 20ms
    WHERE latency = time(audio input -> processed output)
```

**Rationale**: Real-time audio processing requires low latency for acceptable user experience.

**Observable**:
- Performance benchmarks show <20ms latency
- No audio dropouts or glitches

**Verification**:
```bash
swift test --filter VDSPSpeedupBenchmarkTests
# Verify latency benchmarks pass
```

---

### PERFORMANCE-002: Actor Context Switch Overhead

**Type**: PERFORMANCE  
**Priority**: High  
**Related Tasks**: TASK-SW6-006, TASK-SW6-012  
**Related Requirements**: REQ-010, REQ-013

**Formal Statement**:
```
FORALL cross-actor call C:
    overhead(C) < 5% of baseline (pre-Swift6)
    WHERE overhead = additional time due to isolation
```

**Rationale**: Swift 6 concurrency should not significantly degrade performance compared to pre-migration baseline.

**Observable**:
- Performance regression < 5% in benchmarks
- No significant increase in context switches

**Verification**:
- Compare benchmarks before/after migration
- CPU profiling for hot paths

---

### PERFORMANCE-003: Memory Stability

**Type**: PERFORMANCE  
**Priority**: Medium  
**Related Tasks**: All tasks  
**Related Requirements**: REQ-010

**Formal Statement**:
```
FORALL long-running transcription T:
    memory_usage(T) is bounded
    AND
    memory_growth_rate(T) < 1MB/minute
```

**Rationale**: Long-running sessions must not leak memory.

**Verification**:
- Memory profiling during extended tests
- Heap analysis for actor allocations

---

### PERFORMANCE-004: CI Build Time

**Type**: PERFORMANCE  
**Priority**: Medium  
**Related Tasks**: TASK-SW6-016  
**Related Requirements**: REQ-011

**Formal Statement**:
```
CI build time < 10 minutes
WHERE build = clean build + test execution
```

**Rationale**: Developer productivity requires fast feedback loops.

**Verification**:
- CI pipeline timing metrics
- Build time monitoring

---

## Property Verification Matrix

| Property | Compiler | Static Analysis | Unit Tests | Property Tests | Benchmarks |
|----------|----------|-----------------|------------|----------------|------------|
| SAFETY-001 | ✓ | ✓ | | | |
| SAFETY-002 | ✓ | ✓ | | | |
| SAFETY-003 | ✓ | ✓ | | | |
| SAFETY-004 | | ✓ | | | |
| SAFETY-005 | ✓ | ✓ | | | |
| SAFETY-006 | ✓ | | | | |
| SAFETY-007 | | ✓ | | | |
| SAFETY-008 | ✓ | | | | |
| LIVENESS-001 | | | ✓ | ✓ | |
| LIVENESS-002 | | | ✓ | | ✓ |
| LIVENESS-003 | ✓ | | ✓ | | |
| INVARIANT-001 | | | ✓ | ✓ | |
| INVARIANT-002 | | | ✓ | ✓ | |
| INVARIANT-003 | | | ✓ | | |
| INVARIANT-004 | ✓ | | | | |
| INVARIANT-005 | | | ✓ | ✓ | |
| INVARIANT-006 | | | ✓ | | |
| PERFORMANCE-001 | | | | | ✓ |
| PERFORMANCE-002 | | | | | ✓ |
| PERFORMANCE-003 | | | ✓ | | ✓ |
| PERFORMANCE-004 | | | | | ✓ |

---

## Property to Task Mapping

| Property | Primary Tasks | Verification Tasks |
|----------|---------------|-------------------|
| SAFETY-001 | TASK-SW6-001, TASK-SW6-002 | All tasks (final validation) |
| SAFETY-002 | TASK-SW6-005, TASK-SW6-006, TASK-SW6-007 | TASK-SW6-014 |
| SAFETY-003 | TASK-SW6-010 | TASK-SW6-011 |
| SAFETY-004 | TASK-SW6-013 | All tasks (code review) |
| SAFETY-005 | TASK-SW6-009 | TASK-SW6-014 |
| SAFETY-006 | TASK-SW6-008 | TASK-SW6-014 |
| SAFETY-007 | TASK-SW6-007, TASK-SW6-012 | TASK-SW6-014 |
| SAFETY-008 | All tasks | TASK-SW6-014 |
| LIVENESS-001 | TASK-SW6-012 | TASK-SW6-020 |
| LIVENESS-002 | TASK-SW6-006, TASK-SW6-012 | TASK-SW6-018 |
| LIVENESS-003 | TASK-SW6-014, TASK-SW6-015 | TASK-SW6-016 |
| INVARIANT-001 | TASK-SW6-011 | TASK-SW6-020 |
| INVARIANT-002 | TASK-SW6-012 | TASK-SW6-020 |
| INVARIANT-003 | TASK-SW6-012 | TASK-SW6-020 |
| INVARIANT-004 | All tasks | TASK-SW6-014 |
| INVARIANT-005 | TASK-SW6-011 | TASK-SW6-020 |
| INVARIANT-006 | All tasks | TASK-SW6-015 |
| PERFORMANCE-001 | TASK-SW6-011, TASK-SW6-012 | TASK-SW6-018 |
| PERFORMANCE-002 | TASK-SW6-006, TASK-SW6-012 | TASK-SW6-018 |
| PERFORMANCE-003 | All tasks | TASK-SW6-018 |
| PERFORMANCE-004 | TASK-SW6-016 | TASK-SW6-016 |

---

## Property Violation Escalation

| Property Category | Violation Severity | Escalation Path |
|-------------------|-------------------|-----------------|
| SAFETY | Critical | Block PR, immediate fix required |
| LIVENESS | High | Block PR, fix within 24 hours |
| INVARIANT | High | Block merge, fix before release |
| PERFORMANCE | Medium | Flag for optimization sprint |

---

## Formal Property Syntax Reference

### Swift 6 Property Patterns

```swift
// SAFETY: Actor isolation guarantees
public actor SecureService: Sendable {
    // INVARIANT: state is only mutated within actor isolation
    private var state: ServiceState
    
    // SAFETY: nonisolated only for pure computation
    nonisolated func computeHash(_ input: String) -> Int {
        input.hashValue
    }
}

// SAFETY: @unchecked Sendable with documentation
/*
 SAFETY: This struct is @unchecked Sendable because:
 - All properties are immutable (let)
 - No shared mutable state
 - All methods are pure functions
 */
struct ImmutableConfig: @unchecked Sendable {
    let value: String
    let number: Int
}
```

---

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2026-05-02 | 1.0 | Initial property definitions from BA requirements |

---

*Generated by wfc-plan from BA requirements synthesis*
*Timestamp: 2026-05-02*
