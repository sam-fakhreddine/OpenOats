---
source_review: .wfc/reviews/REVIEW-feat-3tier-clean-architecture-002-swift.md
plan_type: remediation
---

# Test Plan: Swift 6 Compliance & Performance Remediation

## Testing Strategy

### Approach
- **Unit Tests**: Verify individual fixes work correctly
- **Integration Tests**: Verify components work together after changes
- **Compiler Verification**: Swift 6 strict concurrency compliance
- **Performance Benchmarks**: Measure before/after performance
- **Memory Leak Detection**: Verify resource cleanup

### Coverage Targets
- 100% of P0 (Swift 6) fixes have regression tests
- 80% of P1 (Performance) fixes have benchmark tests
- All compiler warnings eliminated

---

## Test Cases by Wave

### Wave 1: Swift 6 Critical Fixes (P0)

#### TC-001: ImportAudioUseCase Progress Updates
**Task**: TASK-001  
**Type**: Unit Test  
**Priority**: Critical

**Setup**:
```swift
let useCase = ImportAudioUseCaseImpl(...)
let progressValues: [Double] = []
```

**Steps**:
1. Call useCase.execute with progress handler
2. Verify progress handler is called multiple times
3. Verify progress values increase monotonically

**Expected**: Progress updates received; no weak self issues

**Verification**:
```bash
swift test --filter ImportAudioUseCaseTests
```

---

#### TC-002: TranscriptionResult Sendable Compliance
**Task**: TASK-004  
**Type**: Compiler Test  
**Priority**: Critical

**Setup**: Build with strict concurrency

**Steps**:
1. Build with `-strict-concurrency=complete`
2. Verify no errors in NonBlockingProtocols.swift

**Expected**: Clean compilation

**Verification**:
```bash
swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep -c "error"
# Expected: 0
```

---

#### TC-003: Buffer Release on Error Paths
**Task**: TASK-005  
**Type**: Unit Test  
**Priority**: Critical

**Setup**:
```swift
let pool = AudioBufferPool(capacity: 10, bufferSize: 1024)
let merger = StreamingAudioMerger(bufferPool: pool)
```

**Steps**:
1. Acquire buffers
2. Trigger error condition in mergeStreams
3. Verify buffers released back to pool

**Expected**: Pool.availableCount == 10 after error

**Verification**:
```bash
swift test --filter StreamingBufferProtocolsTests
```

---

#### TC-004: ExportTranscriptUseCase Progress Stream
**Task**: TASK-006, TASK-010  
**Type**: Unit Test  
**Priority**: High

**Setup**:
```swift
let useCase = ExportTranscriptUseCaseImpl(...)
```

**Steps**:
1. Start export operation
2. Collect progress stream values
3. Verify progress reaches 1.0

**Expected**: Progress stream completes without race conditions

---

#### TC-005: Actor Isolation Verification
**Task**: TASK-007, TASK-009  
**Type**: Compiler + Runtime Test  
**Priority**: Critical

**Setup**: Build and run with concurrency checking

**Steps**:
1. Build with strict concurrency
2. Run GenerateNotesUseCaseTests
3. Verify no data races detected

**Expected**: No compiler warnings; tests pass

---

#### TC-006: URL Construction Safety
**Task**: TASK-012  
**Type**: Security Test  
**Priority**: High

**Setup**:
```swift
let service = AssemblyAITranscriptionService(...)
let maliciousID = "../etc/passwd"
```

**Steps**:
1. Attempt to construct URL with malicious ID
2. Verify error thrown or ID properly encoded

**Expected**: No URL injection vulnerability

---

### Wave 2: Performance Hot Paths (P1)

#### TC-007: Streaming Buffer Memory Bounds
**Task**: TASK-013  
**Type**: Performance Test  
**Priority**: High

**Setup**:
```swift
let transcriber = StreamingTranscriber(...)
let longAudio = generateAudio(hours: 2)
```

**Steps**:
1. Stream 2 hours of audio
2. Measure memory usage
3. Verify memory stays bounded

**Expected**: Memory < 10MB (not 2.6GB)

**Verification**:
```bash
swift test --filter PerformanceTests
```

---

#### TC-008: VAD Loop Latency
**Task**: TASK-014, TASK-018  
**Type**: Performance Test  
**Priority**: High

**Setup**:
```swift
let transcriber = StreamingTranscriber(...)
```

**Steps**:
1. Process audio chunks in VAD loop
2. Measure time per chunk
3. Verify no O(n) operations

**Expected**: < 10ms per chunk

---

#### TC-009: vDSP Audio Processing
**Task**: TASK-015, TASK-016, TASK-017  
**Type**: Performance Benchmark  
**Priority**: High

**Setup**:
```swift
let processor = MLXAudioProcessor()
let stereoBuffer = generateStereoBuffer(samples: 48000)
```

**Steps**:
1. Measure scalar implementation time
2. Measure vDSP implementation time
3. Calculate speedup ratio

**Expected**: 2-8x speedup with vDSP

**Verification**:
```bash
swift test --filter DSPPerformanceTests
```

---

#### TC-010: Buffer Pool Efficiency
**Task**: TASK-019, TASK-021  
**Type**: Performance Test  
**Priority**: Medium

**Setup**:
```swift
let pool = AudioBufferPool(capacity: 100, bufferSize: 8192)
```

**Steps**:
1. Acquire and release buffers 1000 times
2. Measure total time
3. Verify no memory growth

**Expected**: Linear time complexity; no leaks

---

### Wave 3: Swift Idiomatic Cleanup (P2)

#### TC-011: @preconcurrency Import Compilation
**Task**: TASK-023  
**Type**: Compiler Test  
**Priority**: Medium

**Steps**:
1. Add @preconcurrency imports
2. Build with strict concurrency
3. Verify reduced warnings

**Expected**: Fewer warnings from external modules

---

#### TC-012: Factory Protocol Access Levels
**Task**: TASK-028  
**Type**: Compiler Test  
**Priority**: Low

**Steps**:
1. Build project
2. Verify no access level warnings
3. Test external module can use factories

---

### Wave 4: Complexity Reduction (EEDOM)

#### TC-013: finalizeCurrentSession Complexity Reduction
**Task**: TASK-031  
**Type**: Static Analysis + Unit Test  
**Priority**: Medium

**Setup**: Run EEDOM complexity scan before and after

**Steps**:
1. Run EEDOM scan: `eedom scan --complexity`
2. Record CCN for finalizeCurrentSession (baseline: 32)
3. Apply refactoring
4. Re-run EEDOM scan
5. Verify CCN < 15

**Expected**: CCN reduced from 32 to <15

**Verification**:
```bash
# Before
CCN: 32

# After  
CCN: <15
```

---

#### TC-014: StreamingTranscriber.run Complexity Reduction
**Task**: TASK-032  
**Type**: Static Analysis + Integration Test  
**Priority**: Medium

**Setup**: Streaming transcription test environment

**Steps**:
1. Measure baseline CCN (29)
2. Apply refactoring
3. Verify CCN < 15
4. Run streaming transcription tests
5. Verify no functional regression

**Expected**: CCN < 15, all tests pass

---

#### TC-015: TranscriptionEngine.start Complexity Reduction
**Task**: TASK-033  
**Type**: Static Analysis + Unit Test  
**Priority**: Medium

**Steps**:
1. Measure baseline CCN (26)
2. Refactor into smaller methods
3. Verify CCN < 15
4. Test engine startup scenarios

**Expected**: CCN < 15, startup works correctly

---

#### TC-016: EEDOM Maintainability Grade Preservation
**Task**: All Wave 4  
**Type**: Static Analysis  
**Priority**: Medium

**Setup**: Full EEDOM scan

**Steps**:
1. Run full EEDOM scan before refactoring
2. Record maintainability grade (baseline: 94/100 A)
3. Apply all Wave 4 refactors
4. Re-run EEDOM scan
5. Verify maintainability grade remains A (90+)

**Expected**: Maintainability grade A preserved

**Verification**:
```bash
# Before
Maintainability: 94/100 (A)

# After
Maintainability: >=90/100 (A)
```

---

## Regression Test Suite

### Full Test Run
```bash
# All tests
swift test

# Specific test targets
swift test --filter DomainTests
swift test --filter BusinessLogicTests
swift test --filter InfrastructureTests
swift test --filter PresentationTests
swift test --filter ConcurrencySafetyTests
swift test --filter MemoryManagementTests
swift test --filter PerformanceTests
```

### Compiler Verification
```bash
# Strict concurrency check
swift build -Xswiftc -strict-concurrency=complete

# Release build
swift build -c release

# With warnings as errors
swift build -Xswiftc -warnings-as-errors
```

---

## Test Execution Order

### Phase 1: Canary Task Verification
1. Run TASK-001 tests first
2. Verify no regressions
3. Proceed to parallel execution

### Phase 2: Wave 1 (P0) Verification
1. Run all Wave 1 task tests
2. Verify strict concurrency compilation
3. Run integration tests

### Phase 3: Wave 2 (P1) Verification
1. Run performance benchmarks
2. Compare before/after metrics
3. Verify no regressions

### Phase 4: Wave 3 (P2) Verification
1. Run final compiler checks
2. Full test suite
3. Security audit

---

## Success Criteria

| Criterion | Target | Verification |
|-----------|--------|------------|
| Compiler Errors | 0 | `swift build` |
| Strict Concurrency Warnings | 0 | `swift build -Xswiftc -strict-concurrency=complete` |
| Unit Test Pass Rate | 100% | `swift test` |
| Performance Regression | < 5% | Benchmark comparison |
| Memory Leaks | 0 | MemoryManagementTests |
| Data Races | 0 | ConcurrencySafetyTests |

---

## Test Artifacts

- Test results: `.wfc/plans/plan_review002-swift-fixes_*/test-results/`
- Performance benchmarks: `.wfc/plans/plan_review002-swift-fixes_*/benchmarks/`
- Compiler logs: `.wfc/plans/plan_review002-swift-fixes_*/compiler-logs/`
