# Remediation Plan: Review 001 Fixes

**Source Review**: `.wfc/reviews/REVIEW-feat-3tier-clean-architecture-001.md`  
**Status**: BLOCKED → Remediation  
**Goal**: Resolve all severity ≥ 6 findings to achieve PASSED verdict  
**Total Tasks**: 12  
**Estimated Effort**: 2-3 hours

---

## Execution Waves

| Wave | Focus | Tasks | Deliverables |
|------|-------|-------|--------------|
| Wave 1 | Critical Fixes | TASK-001 to TASK-004 | Compilation error, API security |
| Wave 2 | Performance | TASK-005 to TASK-007 | O(n²) fixes, actor reentrancy |
| Wave 3 | Reliability | TASK-008 to TASK-012 | Resource leaks, error handling |

---

## Wave 1: Critical Fixes (Must Fix First)

### TASK-001: Fix ChunkedSpeechBuffer Extension Name (Compilation Error)
**Complexity**: S  
**Dependencies**: []  
**Canary**: true  
**Wave**: 1  
**File**: `OpenOats/Sources/OpenOats/Infrastructure/Performance/ChunkedSpeechBuffer.swift`

**Description**:  
Line 573 declares `extension ChunkedSpeechBuffer` but the actual actor type is named `VDSPChunkedSpeechBuffer`. This causes a compilation error.

**Exact Change Required**:
```swift
// BEFORE (line 573):
extension ChunkedSpeechBuffer {

// AFTER:
extension VDSPChunkedSpeechBuffer {
```

**Acceptance Criteria**:
- [ ] Code compiles without "Cannot find type 'ChunkedSpeechBuffer' in scope" error
- [ ] grep -n "extension ChunkedSpeechBuffer" returns no results
- [ ] grep -n "extension VDSPChunkedSpeechBuffer" returns 1 result at line 573

**Related Finding**: Correctness-001 (severity 9, confidence 10)

---

### TASK-002: Secure API Key in TranscriptionEngine (Line 277)
**Complexity**: M  
**Dependencies**: []  
**Wave**: 1  
**File**: `OpenOats/Sources/OpenOats/Transcription/TranscriptionEngine.swift`

**Description**:  
Line 277 accesses `cloudASRApiKey` as plain String from settings. Must use SecureString.

**Exact Change Required**:
```swift
// BEFORE (around line 277):
let apiKey = settings.cloudASRApiKey

// AFTER:
let secureApiKey = SecureString(settings.cloudASRApiKey)
```

**Acceptance Criteria**:
- [ ] SecureString wrapper used for API key at line 277
- [ ] No plain String apiKey variable in scope
- [ ] grep -A2 "cloudASRApiKey" shows SecureString wrapping

**Related Finding**: Security-001 (severity 7, confidence 10)

---

### TASK-003: Secure API Key in Backend Factory (Line 475)
**Complexity**: M  
**Dependencies**: [TASK-002]  
**Wave**: 1  
**File**: `OpenOats/Sources/OpenOats/Transcription/TranscriptionEngine.swift`

**Description**:  
Line 475 passes API key to backend factory as plain String. Must pass SecureString.

**Exact Change Required**:
```swift
// BEFORE (around line 475):
backendFactory.makeBackend(apiKey: apiKey)

// AFTER:
backendFactory.makeBackend(apiKey: secureApiKey)
```

**Acceptance Criteria**:
- [ ] SecureString passed to backend factory
- [ ] Backend factory signature accepts SecureString
- [ ] grep -n "makeBackend.*apiKey" shows SecureString parameter

**Related Finding**: Security-002 (severity 7, confidence 10)

---

### TASK-004: Update Backend Factory to Accept SecureString
**Complexity**: M  
**Dependencies**: [TASK-002, TASK-003]  
**Wave**: 1  
**File**: `OpenOats/Sources/OpenOats/Transcription/TranscriptionModel.swift`

**Description**:  
Update `TranscriptionModel.makeBackend()` to accept `SecureString` instead of `String` for apiKey parameter.

**Exact Change Required**:
```swift
// BEFORE:
func makeBackend(apiKey: String) -> TranscriptionBackend

// AFTER:
func makeBackend(apiKey: SecureString) -> TranscriptionBackend
```

**Acceptance Criteria**:
- [ ] Function signature uses SecureString
- [ ] Implementation uses `apiKey.withSecureAccess { ... }` when making network calls
- [ ] grep -n "func makeBackend" shows SecureString parameter

**Related Finding**: Security-002 (severity 7, confidence 10)

---

## Wave 2: Performance & Concurrency

### TASK-005: Fix O(n²) Array Copy in ChunkedSpeechBuffer (Line 221)
**Complexity**: L  
**Dependencies**: [TASK-001]  
**Wave**: 2  
**File**: `OpenOats/Sources/OpenOats/Infrastructure/Performance/ChunkedSpeechBuffer.swift`

**Description**:  
Line 221 uses `Array(samplesRemaining.dropFirst(written))` which creates O(n) copy on every chunk write, causing O(n²) total behavior.

**Exact Change Required**:
```swift
// BEFORE (line 221):
let remaining = Array(samplesRemaining.dropFirst(written))

// AFTER:
// Use ArraySlice instead of copying
let remaining = samplesRemaining[written...]
// Or maintain index offset instead of copying array
```

**Acceptance Criteria**:
- [ ] No Array(dropFirst()) pattern in write() method
- [ ] Uses ArraySlice or index tracking instead
- [ ] Performance test shows linear time complexity

**Related Finding**: Performance-001 (severity 9, confidence 9)

---

### TASK-006: Fix Actor Reentrancy in CircularAudioBuffer setConfiguration (Line 310)
**Complexity**: M  
**Dependencies**: []  
**Wave**: 2  
**File**: `OpenOats/Sources/OpenOats/Infrastructure/Performance/CircularAudioBuffer.swift`

**Description**:  
Line 310 has actor reentrancy vulnerability: `await sampleBuffer.capacity` suspends, then state could change before buffer recreation.

**Exact Change Required**:
```swift
// BEFORE (around line 310):
let currentCapacity = await sampleBuffer.capacity
if currentCapacity != requiredCapacity {
    sampleBuffer = VDSPCircularAudioBuffer(capacity: requiredCapacity)
}

// AFTER:
// Cache values before any await, or use synchronous check
let requiredCapacity = Int(newConfig.sampleRate * 2.0)
let currentBuffer = sampleBuffer
let currentCapacity = await currentBuffer.capacity
if currentCapacity != requiredCapacity {
    sampleBuffer = VDSPCircularAudioBuffer(capacity: requiredCapacity)
}
```

**Acceptance Criteria**:
- [ ] No state check after await that could be stale
- [ ] All values cached before first await in method
- [ ] Actor reentrancy test passes

**Related Finding**: Correctness-002 (severity 8, confidence 9)

---

### TASK-007: Fix Actor Reentrancy in CircularAudioBuffer add() (Line 294)
**Complexity**: M  
**Dependencies**: [TASK-006]  
**Wave**: 2  
**File**: `OpenOats/Sources/OpenOats/Infrastructure/Performance/CircularAudioBuffer.swift`

**Description**:  
Line 294 has two suspension points (`await other.sampleCount` and `await other.peek()`) with potential state change between them.

**Exact Change Required**:
```swift
// BEFORE:
let count = await other.sampleCount
let samples = await other.peek()

// AFTER:
// Single async call to get both values atomically
let (count, samples) = await other.getCountAndSamples()
// Or validate consistency after second await
```

**Acceptance Criteria**:
- [ ] Single suspension point for related data
- [ ] State consistency validated after each await
- [ ] No split read of related values across awaits

**Related Finding**: Correctness-003 (severity 7, confidence 8)

---

## Wave 3: Reliability Improvements

### TASK-008: Fix Resource Leak in TranscriptionEngine (Line 415)
**Complexity**: M  
**Dependencies**: []  
**Wave**: 3  
**File**: `OpenOats/Sources/OpenOats/Transcription/TranscriptionEngine.swift`

**Description**:  
Line 415 checks `guard vadManager != nil` but doesn't clean up already-initialized backends if the guard fails.

**Exact Change Required**:
```swift
// BEFORE:
guard vadManager != nil else {
    throw TranscriptionError.vadManagerNotInitialized
}

// AFTER:
guard vadManager != nil else {
    // Clean up already initialized resources
    await backend?.shutdown()
    throw TranscriptionError.vadManagerNotInitialized
}
```

**Acceptance Criteria**:
- [ ] All initialized resources cleaned up on early exit
- [ ] No resource leaks in error paths
- [ ] grep -A5 "guard vadManager" shows cleanup code

**Related Finding**: Reliability-001 (severity 7, confidence 8)

---

### TASK-009: Store Diarization Task for Cancellation (Line 1006)
**Complexity**: M  
**Dependencies**: []  
**Wave**: 3  
**File**: `OpenOats/Sources/OpenOats/Transcription/TranscriptionEngine.swift`

**Description**:  
Line 1006 creates a Task but doesn't store the reference, so it can't be cancelled during stop/finalize.

**Exact Change Required**:
```swift
// BEFORE (line 1006):
Task {
    // diarization work
}

// AFTER:
self.diarizationTask = Task {
    // diarization work
}

// In stop() or finalize():
self.diarizationTask?.cancel()
self.diarizationTask = nil
```

**Acceptance Criteria**:
- [ ] Diarization Task stored in property
- [ ] Task cancelled in stop()/finalize()
- [ ] Property cleared after cancellation

**Related Finding**: Reliability-002 (severity 7, confidence 8)

---

### TASK-010: Fix O(n) Operations in FluidVadManager Hot Loops (Lines 130, 166)
**Complexity**: M  
**Dependencies**: []  
**Wave**: 3  
**File**: `OpenOats/Sources/OpenOats/Infrastructure/Actors/FluidVadManager.swift`

**Description**:  
Lines 130 and 166 use `Array.removeFirst()` which is O(n) in hot VAD processing loops.

**Exact Change Required**:
```swift
// BEFORE:
probabilityBuffer.removeFirst()
energyHistory.removeFirst()

// AFTER:
// Use ring buffer with head/tail indices instead
// Or use CircularAudioBuffer which has O(1) operations
```

**Acceptance Criteria**:
- [ ] No Array.removeFirst() in hot loops
- [ ] O(1) ring buffer operations used
- [ ] Performance test shows improvement

**Related Finding**: Performance-003, Performance-004 (severity 7, confidence 9)

---

### TASK-011: Add Error Handling for Silent Failures in StreamingTranscriber (Line 386)
**Complexity**: S  
**Dependencies**: []  
**Wave**: 3  
**File**: `OpenOats/Sources/OpenOats/Transcription/StreamingTranscriber.swift`

**Description**:  
Line 386 silently catches VAD errors with only logging, potentially masking issues.

**Exact Change Required**:
```swift
// BEFORE:
} catch {
    Log.streaming.error("VAD error: \(error)")
}

// AFTER:
} catch {
    Log.streaming.error("VAD error: \(error)")
    // Propagate or track consecutive errors
    self.consecutiveVadErrors += 1
    if self.consecutiveVadErrors > 3 {
        self.delegate?.transcriberDidEncounterError(error)
    }
}
```

**Acceptance Criteria**:
- [ ] Errors tracked (not just logged)
- [ ] Consecutive error threshold triggers notification
- [ ] Delegate notified of persistent failures

**Related Finding**: Reliability-010 (severity 6, confidence 8)

---

### TASK-012: Fix Force Unwrap in CircularAudioBuffer (Line 92)
**Complexity**: S  
**Dependencies**: []  
**Wave**: 3  
**File**: `OpenOats/Sources/OpenOats/Infrastructure/Performance/CircularAudioBuffer.swift`

**Description**:  
Line 92 force unwraps `buffer.baseAddress!` which could crash.

**Exact Change Required**:
```swift
// BEFORE:
let ptr = buffer.baseAddress!

// AFTER:
guard let ptr = buffer.baseAddress else {
    throw AudioBufferError.invalidBuffer
}
```

**Acceptance Criteria**:
- [ ] No force unwrap of baseAddress
- [ ] Proper error handling for nil case
- [ ] grep -n "baseAddress!" returns no results

**Related Finding**: Reliability-004 (severity 6, confidence 7)

---

## Dependency Graph

```
Wave 1:
  TASK-001 (canary)
  TASK-002 → TASK-003 → TASK-004

Wave 2:
  TASK-001 → TASK-005
  TASK-006 → TASK-007

Wave 3:
  TASK-008
  TASK-009
  TASK-010
  TASK-011
  TASK-012
```

---

## Formal Properties

### SAFETY-001: No Compilation Errors
**Statement**: The codebase must compile without errors.  
**Rationale**: BLOCKED review finding requires compilation fix.  
**Observable**: `swift build` exits 0.

### SAFETY-002: API Keys Protected
**Statement**: All API keys must use SecureString wrapper.  
**Rationale**: Security findings SEC-001, SEC-002.  
**Observable**: grep for "apiKey: String" returns no results in production code.

### PERFORMANCE-001: No O(n²) in Hot Paths
**Statement**: Audio processing must be O(n) or better.  
**Rationale**: Performance finding PERF-001 (severity 9).  
**Observable**: Benchmark shows linear scaling with input size.

### SAFETY-003: Actor Reentrancy Safe
**Statement**: No actor state checks after suspension points.  
**Rationale**: Correctness findings CORR-002, CORR-003.  
**Observable**: Static analysis shows no await between related state reads.

---

## Test Plan

### Unit Tests
- [ ] SecureString wrapping/unwrapping
- [ ] CircularAudioBuffer reentrancy scenarios
- [ ] ChunkedSpeechBuffer O(n) performance

### Integration Tests
- [ ] API key flow end-to-end
- [ ] Actor isolation stress test
- [ ] Resource cleanup on error paths

### Verification Commands
```bash
# Compilation
swift build

# Security check
grep -r "apiKey: String" OpenOats/Sources/ || echo "PASS: No plain String API keys"

# Performance check
swift test --filter PerformanceTests

# Actor reentrancy check
grep -n "await.*capacity" OpenOats/Sources/OpenOats/Infrastructure/Performance/CircularAudioBuffer.swift
```

---

## Exit Criteria

Before re-running wfc-review:
1. ✅ All 12 tasks completed
2. ✅ swift build succeeds (no compilation errors)
3. ✅ All severity ≥ 6 findings addressed
4. ✅ Tests pass
5. ✅ Security scan shows no API key issues

---

**Next Step**: Run `/wfc-implement` on this TASKS.md to execute remediation.
