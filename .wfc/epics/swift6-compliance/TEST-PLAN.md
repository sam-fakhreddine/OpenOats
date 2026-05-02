# Swift 6 Strict Concurrency Compliance - TEST-PLAN.md

## Plan Overview

**Epic**: Swift 6 Strict Concurrency Compliance  
**Source**: `.wfc/epics/swift6-compliance/ba-output.json`  
**Total Errors**: 1,406 errors across 50 files  
**Testing Strategy**: Multi-layer verification with property-based testing

---

## Testing Pyramid

```
                    ┌─────────────────┐
                    │   E2E Tests     │  UI automation, integration
                    │   (~5 tests)    │  REQ-010 validation
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Property Tests │  Invariant verification
                    │  (~20 tests)    │  REQ-015
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ Integration Tests │  Actor interaction
                    │  (~30 tests)    │  REQ-006
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │   Unit Tests    │  Component isolation
                    │  (~100 tests)   │  REQ-004, REQ-007
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ Compiler Checks │  SAFETY verification
                    │  (1,406 errors) │  REQ-001, REQ-002
                    └─────────────────┘
```

---

## Test Categories

| Category | Count | Purpose | Automation |
|----------|-------|---------|------------|
| Compiler Verification | 1 | Zero Swift 6 errors | CI mandatory |
| Property-Based Tests | 20 | Invariant verification | CI mandatory |
| Actor Isolation Tests | 15 | Concurrency safety | CI mandatory |
| Protocol Conformance Tests | 10 | REQ-001 validation | CI mandatory |
| Sendable Compliance Tests | 15 | REQ-002 validation | CI mandatory |
| Performance Benchmarks | 5 | REQ-013 validation | CI nightly |
| Integration Tests | 30 | REQ-006 validation | CI mandatory |
| E2E Tests | 5 | REQ-010 validation | CI nightly |
| **Total** | **101** | **Full coverage** | **Full CI** |

---

## Phase-Specific Test Strategy

### Phase 1: Mock Services (Tasks TASK-SW6-001 to TASK-SW6-004)

**Focus**: Sendable compliance in test infrastructure

#### Test Cases

**TEST-SW6-P1-001: MockService Sendable Compilation**
- **Type**: Compiler verification
- **Trigger**: After TASK-SW6-001
- **Command**: `swift build --target OpenOats -Xswiftc -strict-concurrency=complete`
- **Expected**: Zero errors in MockServiceFactory.swift, MockRepositories.swift
- **Related Property**: SAFETY-001

**TEST-SW6-P1-002: Test Double Sendable Verification**
- **Type**: Static analysis
- **Trigger**: After TASK-SW6-002
- **Command**: `grep -n "Sendable" OpenOats/Sources/OpenOats/Infrastructure/Services/Mock*.swift`
- **Expected**: All types conform to Sendable or @unchecked Sendable with SAFETY comment
- **Related Property**: SAFETY-004

**TEST-SW6-P1-003: Type Inference in Async Mocks**
- **Type**: Compiler verification
- **Trigger**: After TASK-SW6-004
- **Command**: `swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep -c "type inference"`
- **Expected**: 0 type inference errors in mock files
- **Related Requirement**: REQ-005

#### Phase 1 Exit Criteria
- [ ] MockServiceFactory compiles with zero Sendable errors
- [ ] All mock types explicitly typed in async contexts
- [ ] Phase 1 error count reduced by 500

---

### Phase 2: Protocol Redesign (Tasks TASK-SW6-005 to TASK-SW6-009)

**Focus**: Actor-protocol conformance and visibility

#### Test Cases

**TEST-SW6-P2-001: Protocol @MainActor Audit**
- **Type**: Static analysis + manual review
- **Trigger**: After TASK-SW6-005
- **Command**: `grep -r "protocol.*UseCase\|protocol.*Service" --include="*.swift" OpenOats/Sources/`
- **Expected**: All protocol methods have isolation annotations documented
- **Related Property**: SAFETY-002

**TEST-SW6-P2-002: TranscriptionService Protocol Compliance**
- **Type**: Compiler verification
- **Trigger**: After TASK-SW6-006
- **Command**: `swift build --target OpenOats -Xswiftc -strict-concurrency=complete 2>&1 | grep -c "Actor-isolated.*cannot satisfy"`
- **Expected**: 0 actor-protocol conformance errors in transcription services
- **Related Requirement**: REQ-001

**TEST-SW6-P2-003: Visibility Mismatch Detection**
- **Type**: Compiler verification
- **Trigger**: After TASK-SW6-008
- **Command**: `swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep -c "visibility"`
- **Expected**: 0 visibility mismatch errors
- **Related Requirement**: REQ-003

**TEST-SW6-P2-004: Nonisolated Member Verification**
- **Type**: Static analysis + unit tests
- **Trigger**: After TASK-SW6-009
- **Command**: `grep -B1 "nonisolated var" --include="*.swift" -r OpenOats/Sources/`
- **Expected**: Empty (no nonisolated var properties)
- **Related Property**: SAFETY-005

#### Phase 2 Exit Criteria
- [ ] Zero actor-protocol conformance errors
- [ ] Zero visibility mismatch errors
- [ ] All nonisolated members verified for immutability
- [ ] Phase 2 error count reduced by 550

---

### Phase 3: Actor Implementations (Tasks TASK-SW6-010 to TASK-SW6-013)

**Focus**: Async-safe locking and actor safety

#### Test Cases

**TEST-SW6-P3-001: NSLock Elimination**
- **Type**: Static analysis
- **Trigger**: After TASK-SW6-010
- **Command**: `grep -r "NSLock\|NSRecursiveLock" --include="*.swift" OpenOats/Sources/ | grep -v "SAFETY:"`
- **Expected**: Empty (all locks eliminated or documented)
- **Related Property**: SAFETY-003

**TEST-SW6-P3-002: Circular Buffer Invariants**
- **Type**: Property-based test
- **Trigger**: After TASK-SW6-011
- **Location**: `OpenOats/Tests/OpenOatsTests/Infrastructure/InfrastructureProtocolPropertyTests.swift`
- **Test**:
```swift
@Test(arguments: randomSampleArrays())
func circularBufferMaintainsInvariants(samples: [Float]) async {
    let buffer = CircularAudioBuffer(capacity: 1000)
    await buffer.append(samples)
    
    let count = await buffer.count
    let capacity = await buffer.capacity
    
    #expect(count >= 0)
    #expect(count <= capacity)
    #expect(count == min(samples.count, capacity))
}
```
- **Related Property**: INVARIANT-001

**TEST-SW6-P3-003: AudioEngine State Consistency**
- **Type**: Unit test
- **Trigger**: After TASK-SW6-012
- **Location**: `OpenOats/Tests/OpenOatsTests/LiveSessionControllerTests.swift`
- **Test**: Verify `isRecording` implies `activeSession != nil`
- **Related Property**: INVARIANT-002

**TEST-SW6-P3-004: @unchecked Sendable Documentation**
- **Type**: Static analysis
- **Trigger**: After TASK-SW6-013
- **Command**:
```bash
unchecked_count=$(grep -r "@unchecked Sendable" --include="*.swift" OpenOats/Sources/ | wc -l)
safety_count=$(grep -B1 "@unchecked Sendable" --include="*.swift" -r OpenOats/Sources/ | grep -c "SAFETY:")
[ "$unchecked_count" -eq "$safety_count" ] && echo "PASS" || echo "FAIL"
```
- **Expected**: PASS (every @unchecked Sendable has SAFETY comment)
- **Related Property**: SAFETY-004

#### Phase 3 Exit Criteria
- [ ] Zero NSLock usage (except documented wrappers)
- [ ] Circular buffer invariants verified
- [ ] All @unchecked Sendable documented
- [ ] Phase 3 error count reduced by 250

---

### Phase 4: Test Suite & CI/CD (Tasks TASK-SW6-014 to TASK-SW6-020)

**Focus**: Full test compilation and CI/CD integration

#### Test Cases

**TEST-SW6-P4-001: OpenOatsTests Compilation**
- **Type**: Compiler verification
- **Trigger**: After TASK-SW6-014
- **Command**: `swift test --target OpenOatsTests -Xswiftc -strict-concurrency=complete 2>&1 | tail -20`
- **Expected**: Build successful with zero errors
- **Related Requirement**: REQ-006

**TEST-SW6-P4-002: Test Double Swift 6 Update**
- **Type**: Compiler verification
- **Trigger**: After TASK-SW6-015
- **Command**: `swift build --target OpenOatsTests -Xswiftc -strict-concurrency=complete 2>&1 | grep -c "Sendable"`
- **Expected**: 0 Sendable errors in test files
- **Related Requirement**: REQ-006

**TEST-SW6-P4-003: CI Pipeline Swift 6 Configuration**
- **Type**: Integration test
- **Trigger**: After TASK-SW6-016
- **Command**: `gh workflow run "Swift 6 Checks" --ref integration`
- **Expected**: Workflow passes with strict concurrency enabled
- **Related Requirement**: REQ-011

**TEST-SW6-P4-004: Audio Latency Benchmark**
- **Type**: Performance benchmark
- **Trigger**: After TASK-SW6-018
- **Command**: `swift test --filter VDSPSpeedupBenchmarkTests`
- **Expected**: Latency < 20ms, no regression > 5%
- **Related Property**: PERFORMANCE-001

**TEST-SW6-P4-005: Remaining Error Resolution**
- **Type**: Compiler verification
- **Trigger**: After TASK-SW6-019
- **Command**: `swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep -c "error:"`
- **Expected**: 0 errors (all 1,406 resolved)
- **Related Requirement**: REQ-014

**TEST-SW6-P4-006: Property-Based Concurrency Tests**
- **Type**: Property-based test
- **Trigger**: After TASK-SW6-020
- **Location**: `OpenOats/Tests/OpenOatsTests/Infrastructure/InfrastructureProtocolPropertyTests.swift`
- **Tests**:
  - Round-trip audio processing
  - Actor state invariants
  - Concurrent buffer operations
- **Related Requirement**: REQ-015

#### Phase 4 Exit Criteria
- [ ] OpenOatsTests target compiles with zero errors
- [ ] All test doubles updated for Swift 6
- [ ] CI pipeline configured and passing
- [ ] Performance benchmarks pass (no regression)
- [ ] All 1,406 errors resolved
- [ ] Property-based tests added

---

## Test Execution Schedule

| Phase | Tests | Run Command | Expected Duration |
|-------|-------|-------------|-------------------|
| Phase 1 | 3 | `swift build -Xswiftc -strict-concurrency=complete` | 2 min |
| Phase 2 | 4 | `swift build -Xswiftc -strict-concurrency=complete` | 2 min |
| Phase 3 | 4 | `swift test --filter "*Actor*"` | 5 min |
| Phase 4 | 6 | `swift test -Xswiftc -strict-concurrency=complete` | 10 min |
| **Full Suite** | **17** | **Full build + test** | **20 min** |

---

## Property-Based Test Specifications

### Audio Processing Properties

```swift
import Testing

struct Swift6AudioPropertyTests {
    
    // INVARIANT-001: Circular buffer maintains count invariant
    @Test(arguments: randomSampleArrays())
    func circularBufferCountInvariant(samples: [Float]) async {
        let buffer = CircularAudioBuffer(capacity: 1000)
        await buffer.append(samples)
        
        let count = await buffer.count
        let capacity = await buffer.capacity
        
        #expect(count >= 0, "Count must be non-negative")
        #expect(count <= capacity, "Count must not exceed capacity")
        #expect(count == min(samples.count, capacity), "Count must equal appended samples or capacity")
    }
    
    // INVARIANT-005: Audio samples remain in valid range
    @Test(arguments: randomSampleArrays())
    func audioSamplesValidRange(samples: [Float]) async {
        let processor = AudioProcessor()
        let processed = await processor.process(samples)
        
        for sample in processed {
            #expect(sample.isFinite, "Sample must be finite (not NaN/Inf)")
            #expect(sample >= -1.0 && sample <= 1.0, "Sample must be normalized")
        }
    }
    
    // Round-trip: Deinterleave is reversible
    @Test(arguments: randomStereoAudioSamples())
    func deinterleaveReversible(left: [Float], right: [Float]) async {
        let interleaved = interleave(left, right)
        let (deLeft, deRight) = deinterleave(interleaved)
        
        #expect(deLeft == left, "Left channel should match after round-trip")
        #expect(deRight == right, "Right channel should match after round-trip")
    }
}
```

### Actor State Properties

```swift
struct Swift6ActorPropertyTests {
    
    // INVARIANT-002: Actor state consistency
    @Test
    func transcriptionEngineStateConsistency() async {
        let engine = TranscriptionEngine()
        
        // Initially not recording
        #expect(await engine.isRecording == false)
        #expect(await engine.activeSession == nil)
        
        // After start: isRecording implies activeSession != nil
        try? await engine.startRecording()
        if await engine.isRecording {
            #expect(await engine.activeSession != nil, "Recording implies active session")
        }
        
        // After stop: not recording implies activeSession == nil
        await engine.stopRecording()
        #expect(await engine.isRecording == false)
        #expect(await engine.activeSession == nil, "Not recording implies no active session")
    }
    
    // LIVENESS-001: Actor operations complete
    @Test
    func actorOperationsDoNotDeadlock() async throws {
        let service = MockTranscriptionService()
        
        // Should complete within timeout
        let result = try await withTimeout(seconds: 5) {
            await service.transcribe(audioData: [0.0, 0.1, 0.2])
        }
        
        #expect(result != nil)
    }
}
```

---

## CI/CD Test Configuration

### GitHub Actions Workflow

```yaml
name: Swift 6 Concurrency Checks

on:
  pull_request:
    branches: [integration, main]
  push:
    branches: [integration]

jobs:
  strict-concurrency:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      
      - name: Build with Strict Concurrency
        run: |
          swift build -Xswiftc -strict-concurrency=complete 2>&1 | tee build.log
          error_count=$(grep -c "error:" build.log || echo "0")
          if [ "$error_count" -gt 0 ]; then
            echo "::error::Found $error_count Swift 6 errors"
            exit 1
          fi
      
      - name: Run Tests with Strict Concurrency
        run: |
          swift test -Xswiftc -strict-concurrency=complete --filter OpenOatsTests 2>&1 | tee test.log
          if grep -q "error:" test.log; then
            echo "::error::Tests failed with Swift 6 errors"
            exit 1
          fi
      
      - name: Verify Sendable Documentation
        run: |
          unchecked_count=$(grep -r "@unchecked Sendable" --include="*.swift" OpenOats/Sources/ | wc -l)
          safety_count=$(grep -B1 "@unchecked Sendable" --include="*.swift" -r OpenOats/Sources/ | grep -c "SAFETY:")
          if [ "$unchecked_count" -ne "$safety_count" ]; then
            echo "::error::Found $unchecked_count @unchecked Sendable but only $safety_count SAFETY comments"
            exit 1
          fi
          echo "✓ All @unchecked Sendable types have SAFETY documentation"
      
      - name: Performance Benchmarks
        run: |
          swift test --filter VDSPSpeedupBenchmarkTests 2>&1 | tee perf.log
          if grep -q "regression" perf.log; then
            echo "::warning::Performance regression detected"
          fi
```

---

## Manual Test Procedures

### Regression Testing (REQ-010)

**Procedure**: 
1. Record baseline metrics before migration (TASK-SW6-018)
2. Complete all migration phases
3. Re-run identical test scenarios
4. Compare metrics

**Acceptance**:
- All existing unit tests pass
- Performance regression < 5%
- Audio latency < 20ms

### Code Review Checklist

**For every PR in this epic**:
- [ ] No new `@unchecked Sendable` without SAFETY comment
- [ ] No `NSLock`/`NSRecursiveLock` introduced
- [ ] No `[weak self]` in actor Task closures
- [ ] No `defer { await ... }` patterns
- [ ] All protocol methods have isolation annotations
- [ ] Public API signatures unchanged

---

## Test Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Compiler errors | 0 | `swift build` output |
| Test failures | 0 | `swift test` output |
| @unchecked Sendable without SAFETY | 0 | Static analysis |
| NSLock usage | 0 | `grep` count |
| Audio latency | < 20ms | Benchmark |
| Performance regression | < 5% | Benchmark comparison |
| CI build time | < 10 min | GitHub Actions |

---

## Risk-Based Testing

| Risk ID | Mitigation Test | Frequency |
|---------|----------------|-----------|
| RISK-001 | Performance benchmarks | Every PR |
| RISK-002 | API compatibility tests | Phase 4 only |
| RISK-003 | Audio latency benchmarks | Nightly |
| RISK-004 | Full error count validation | Phase gates |
| RISK-005 | Dependency audit | Phase 1 |
| RISK-006 | Documentation review | Every PR |

---

## Final Validation Suite

**Command**:
```bash
#!/bin/bash
set -e

echo "=== Swift 6 Final Validation ==="

echo "1. Compiler Check..."
swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep "error:" | wc -l
echo "   Expected: 0"

echo "2. Test Compilation..."
swift test --target OpenOatsTests -Xswiftc -strict-concurrency=complete 2>&1 | tail -5

echo "3. Sendable Documentation..."
unchecked=$(grep -r "@unchecked Sendable" --include="*.swift" OpenOats/Sources/ | wc -l)
safety=$(grep -B1 "@unchecked Sendable" --include="*.swift" -r OpenOats/Sources/ | grep -c "SAFETY:")
echo "   @unchecked Sendable: $unchecked, SAFETY comments: $safety"

echo "4. NSLock Check..."
grep -r "NSLock\|NSRecursiveLock" --include="*.swift" OpenOats/Sources/ | grep -v "SAFETY:" | wc -l
echo "   Expected: 0"

echo "5. weak self in Actors..."
grep -r "Task.*\[weak self\]" --include="*.swift" OpenOats/Sources/ | wc -l
echo "   Expected: 0"

echo "6. Performance Benchmarks..."
swift test --filter VDSPSpeedupBenchmarkTests 2>&1 | grep -E "(passed|failed|latency)"

echo "=== Validation Complete ==="
```

---

## Test Artifact Locations

| Artifact | Location | Purpose |
|----------|----------|---------|
| Property Tests | `OpenOats/Tests/OpenOatsTests/Infrastructure/InfrastructureProtocolPropertyTests.swift` | Invariant verification |
| Unit Tests | `OpenOats/Tests/OpenOatsTests/**/*.swift` | Component testing |
| Performance Tests | `OpenOats/Tests/OpenOatsPerformanceTests/*.swift` | Benchmarks |
| CI Configuration | `.github/workflows/swift6-checks.yml` | Automation |
| Test Logs | CI artifacts | Audit trail |

---

*Generated by wfc-plan from BA requirements synthesis*
*Timestamp: 2026-05-02*
