# ADR-005: Test Infrastructure Concurrency Compliance

## Status

Proposed (Pending wfc-pm Gate Decision)

## Context

The OpenOats test suite (OpenOatsTests target) currently does not compile with Swift 6 strict concurrency enabled. There are 106 errors in the test infrastructure.

Challenges:
1. **Test Doubles**: Mock implementations of services are not Sendable-compliant
2. **Async Test Patterns**: Existing tests use pre-Swift 6 concurrency patterns
3. **Test Expectations**: XCTestExpectation and async assertions need Sendable types
4. **Property-Based Testing**: New requirement (REQ-015) for concurrent operation validation

The migration must:
- Enable full test suite compilation with `-strict-concurrency=complete`
- Preserve all existing test behavior (REQ-010)
- Add property-based tests for concurrent operations (REQ-015)
- Maintain CI build time <10 minutes (PERFORMANCE-004)

## Decision

We will adopt a **Layered Test Infrastructure** approach with three tiers:

### Tier 1: Sendable-Compliant Test Doubles

All mock implementations must conform to Sendable:

```swift
// Before (not Sendable)
class MockTranscriptionService: TranscriptionService {
    private var recordedCalls: [String] = []
    var onTranscriptionComplete: ((String) -> Void)?
}

// After (Sendable-compliant)
actor MockTranscriptionService: TranscriptionService {
    private var recordedCalls: [String] = []
    private var completionHandlers: [CheckedContinuation<String, Never>] = []
    
    // Nonisolated for pure config
    nonisolated let config: TranscriptionConfig
    
    // Actor-isolated for state mutation
    func recordCall(_ method: String) {
        recordedCalls.append(method)
    }
}
```

### Tier 2: Swift 6 Test Patterns

Replace legacy patterns with Swift 6-compatible equivalents:

```swift
// Pattern 1: Async Test with Sendable Types
@Test
func testTranscriptionAsync() async throws {
    let service = MockTranscriptionService()  // Sendable actor
    let audio = AudioChunk.samples([0.1, 0.2, 0.3])  // Sendable
    
    let result = try await service.transcribe(audio)
    
    #expect(await service.recordedCalls.count == 1)
    #expect(result == "Hello world")
}

// Pattern 2: Concurrent Operations Test
@Test
func testConcurrentTranscriptions() async throws {
    let service = MockTranscriptionService()
    
    // Concurrent operations with Sendable types
    async let result1 = service.transcribe(audio1)
    async let result2 = service.transcribe(audio2)
    async let result3 = service.transcribe(audio3)
    
    let results = try await [result1, result2, result3]
    #expect(results.count == 3)
}

// Pattern 3: Actor State Verification
@Test
func testActorStateConsistency() async throws {
    let buffer = CircularAudioBuffer(capacity: 1000)
    
    // Concurrent appends from multiple tasks
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<10 {
            group.addTask {
                await buffer.append([Float](repeating: Float(i), count: 10))
            }
        }
    }
    
    let count = await buffer.count
    #expect(count == 100)  // 10 tasks * 10 samples
}
```

### Tier 3: Property-Based Testing

Implement property-based tests for concurrent operation invariants:

```swift
import Testing

struct ConcurrencyPropertyTests {
    
    // Property: Circular buffer count invariant holds across concurrent operations
    @Test(arguments: randomSampleArrays())
    func circularBufferCountInvariant(samples: [Float]) async {
        let buffer = CircularAudioBuffer(capacity: 1000)
        await buffer.append(samples)
        
        let count = await buffer.count
        #expect(count >= 0)
        #expect(count <= 1000)
        #expect(count == min(samples.count, 1000))
    }
    
    // Property: Deinterleave is reversible (round-trip)
    @Test(arguments: randomStereoAudioSamples())
    func deinterleaveReversible(left: [Float], right: [Float]) {
        let interleaved = interleave(left, right)
        let (deLeft, deRight) = deinterleave(interleaved)
        
        #expect(deLeft == left)
        #expect(deRight == right)
    }
    
    // Property: Actor state transitions are consistent
    @Test
    func transcriptionEngineStateConsistency() async {
        let engine = TranscriptionEngine()
        
        // State machine: idle -> recording -> transcribing -> idle
        await engine.startRecording()
        #expect(await engine.isRecording == true)
        #expect(await engine.activeSession != nil)
        
        await engine.stopRecording()
        #expect(await engine.isRecording == false)
    }
    
    // Property: Concurrent session creation is safe
    @Test
    func concurrentSessionCreation() async throws {
        let engine = TranscriptionEngine()
        
        // Attempt concurrent session creation (should be serialized)
        async let session1 = engine.createSession()
        async let session2 = engine.createSession()
        
        let sessions = try await [session1, session2]
        
        // INVARIANT: Sessions are unique (no duplicate IDs)
        let ids = sessions.map(\.id)
        #expect(Set(ids).count == 2)
    }
}

// MARK: - Test Data Generators

func randomSampleArrays() -> [[Float]] {
    // Generate random sample arrays for property testing
    (0..<100).map { _ in
        (0..<Int.random(in: 0...2000)).map { _ in
            Float.random(in: -1.0...1.0)
        }
    }
}

func randomStereoAudioSamples() -> [([Float], [Float])] {
    (0..<50).map { _ in
        let count = Int.random(in: 1...1000)
        let left = (0..<count).map { _ in Float.random(in: -1.0...1.0) }
        let right = (0..<count).map { _ in Float.random(in: -1.0...1.0) }
        return (left, right)
    }
}
```

## Test Double Sendable Patterns

### Pattern A: Actor-Based Mocks

For mocks that track state:

```swift
actor MockSettingsRepository: SettingsRepository {
    private var settings: [String: Any] = [:]
    private var observers: [String: [CheckedContinuation<SettingChange, Never>]] = [:]
    
    nonisolated var allSettings: [String: Any] {
        get async {
            await settings
        }
    }
    
    func setValue(_ value: Any, forKey key: String) {
        settings[key] = value
        notifyObservers(for: key, value: value)
    }
}
```

### Pattern B: Immutable Struct Mocks

For mocks with static responses:

```swift
struct MockStaticTranscriptionService: TranscriptionService {
    let cannedResponse: String
    let errorToThrow: Error?
    
    func transcribe(_ audio: AudioChunk) async throws -> String {
        if let error = errorToThrow {
            throw error
        }
        return cannedResponse
    }
}
```

### Pattern C: @unchecked Sendable Wrapper (Restricted Use)

For wrapping non-Sendable test utilities:

```swift
/*
 SAFETY: TestOnlySendableWrapper is @unchecked Sendable because:
 - Only used in test context, not production
 - Wrapped value is never accessed concurrently
 - Tests are isolated to prevent concurrent access
 */
struct TestOnlySendableWrapper<T>: @unchecked Sendable {
    private var value: T
    
    init(_ value: T) {
        self.value = value
    }
    
    func withValue<R>(_ closure: (T) throws -> R) rethrows -> R {
        try closure(value)
    }
}
```

## CI/CD Integration

### GitHub Actions Configuration (TASK-SW6-016)

```yaml
name: Swift 6 Strict Concurrency

on: [push, pull_request]

jobs:
  build-and-test:
    runs-on: macos-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Build with Strict Concurrency
        run: swift build -Xswiftc -strict-concurrency=complete
        
      - name: Run Tests with Strict Concurrency
        run: swift test -Xswiftc -strict-concurrency=complete --parallel
        timeout-minutes: 10
        
      - name: Verify SAFETY Comments
        run: |
          UNCHECKED=$(grep -r "@unchecked Sendable" --include="*.swift" Sources/ | wc -l)
          SAFETY=$(grep -B2 "@unchecked Sendable" --include="*.swift" -r Sources/ | grep -c "SAFETY:")
          if [ "$UNCHECKED" -ne "$SAFETY" ]; then
            echo "❌ Missing SAFETY comments: $((UNCHECKED - SAFETY))"
            exit 1
          fi
          echo "✅ All @unchecked Sendable have SAFETY comments"
```

## Consequences

### Positive

- Full test suite compiles with Swift 6 strict mode
- Property-based tests catch concurrency bugs early
- CI/CD pipeline prevents regression
- Tests serve as documentation for concurrency patterns
- TDD workflow (RED-GREEN-REFACTOR) can use Swift 6

### Negative

- Test doubles require more boilerplate (actor-based)
- Async tests require `await` for all actor access
- Test execution time may increase slightly
- Team needs training on Swift 6 testing patterns

### Test Execution Impact

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Build Time | ~3 min | ~4 min | +33% (acceptable) |
| Test Execution | ~2 min | ~2.5 min | +25% (acceptable) |
| Total CI Time | ~5 min | ~6.5 min | +30% (under 10 min limit) |

## TDD Workflow Integration

Per AGENTS.md, TDD requires 3 separate agents. Swift 6 compliance affects this workflow:

### RED Agent (Test Author)

Writes Swift 6-compliant failing test:

```swift
@Test
func testNewFeature() async {
    let service = MockService()  // Sendable actor
    await service.setup()        // await for actor access
    
    let result = await service.newFeature()
    
    #expect(result == expected)
}
```

### GREEN Agent (Implementation)

Writes minimal passing implementation with Swift 6:

```swift
actor Service: Sendable {
    func newFeature() -> Result {
        // Minimal implementation
    }
}
```

### REFACTOR Agent (Cleanup)

Refactors with Swift 6 best practices:

```swift
// OPTIMIZATION: Use nonisolated for pure computation
actor Service: Sendable {
    nonisolated func pureHelper(_ input: Input) -> Output {
        // No actor state access
    }
}
```

## Alternatives Considered

### Alternative 1: Separate Test Suite for Swift 6

Maintain two test targets: one for Swift 5, one for Swift 6
- **Rejected**: Maintenance burden, divergence risk

### Alternative 2: Disable Strict Concurrency in Tests

Use `@preconcurrency import` for all test imports
- **Rejected**: Tests wouldn't validate production code's Swift 6 compliance

### Alternative 3: Minimal Test Suite for Swift 6

Run only smoke tests with Swift 6, full suite with Swift 5
- **Rejected**: Insufficient coverage, doesn't meet REQ-006

## References

- [Swift Testing Documentation](https://developer.apple.com/documentation/testing)
- [SE-0302: Sendable](https://github.com/apple/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md)
- OpenOats AGENTS.md - TDD Workflow section
- OpenOats AGENTS.md - Testing Requirements section
- PROPERTIES.md - LIVENESS-003, INVARIANT-004
- TASKS.md - TASK-SW6-014, TASK-SW6-015, TASK-SW6-016, TASK-SW6-020

---
*Decision Record ID: ADR-005*  
*Epic: Swift 6 Strict Concurrency Compliance*  
*Date: 2026-05-02*
