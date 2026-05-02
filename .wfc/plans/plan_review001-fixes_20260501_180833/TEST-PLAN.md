# Test Plan: Review 001 Remediation

## Testing Approach

**Primary**: Unit tests for individual fixes  
**Secondary**: Integration tests for API key flow and actor interactions  
**Tertiary**: Performance benchmarks for O(n²) fixes

## Coverage Targets

- **Line Coverage**: 80% for modified files
- **Branch Coverage**: 70% for error handling paths
- **Property Coverage**: 100% of formal properties must have verification tests

## Test Cases by Task

### TASK-001: Extension Name Fix
**Test**: CompilationTest.testChunkedSpeechBufferExtension  
**Type**: Unit  
**Steps**:
1. Run `swift build`
2. Verify no "Cannot find type" errors
**Expected**: Build succeeds

### TASK-002 & TASK-003: API Key Security
**Test**: SecurityTests.testSecureStringWrapping  
**Type**: Unit  
**Steps**:
1. Initialize TranscriptionEngine
2. Call start() with cloud ASR enabled
3. Verify SecureString used for API key
**Expected**: No plain String apiKey in memory

**Test**: SecurityTests.testBackendFactorySecureString  
**Type**: Integration  
**Steps**:
1. Create SecureString with test API key
2. Pass to backend factory
3. Verify factory unwraps securely
**Expected**: API key accessible only within withSecureAccess block

### TASK-005: O(n²) Array Copy Fix
**Test**: PerformanceTests.testChunkedSpeechBufferLinearTime  
**Type**: Performance  
**Steps**:
1. Write 1000 chunks of 1024 samples each
2. Measure total time
3. Write 2000 chunks
4. Measure total time
**Expected**: Time approximately doubles (linear), not quadruples

**Test**: PerformanceTests.testNoArrayCopying  
**Type**: Unit  
**Steps**:
1. Mock Array initialization
2. Call write() multiple times
3. Verify no Array(dropFirst()) calls
**Expected**: Zero Array copies from dropFirst

### TASK-006 & TASK-007: Actor Reentrancy
**Test**: ConcurrencyTests.testSetConfigurationAtomicity  
**Type**: Unit (async)  
**Steps**:
1. Create CircularAudioBuffer actor
2. Call setConfiguration from two tasks concurrently
3. Verify no race conditions
**Expected**: Buffer state consistent, no crashes

**Test**: ConcurrencyTests.testAddMethodConsistency  
**Type**: Unit (async)  
**Steps**:
1. Create two CircularAudioBuffer actors
2. Call add() concurrently from multiple tasks
3. Verify sample counts match actual data
**Expected**: No inconsistent state

### TASK-008: Resource Cleanup
**Test**: ReliabilityTests.testResourceCleanupOnError  
**Type**: Unit  
**Steps**:
1. Initialize TranscriptionEngine with mock backend
2. Trigger error before vadManager initialization
3. Verify backend.shutdown() called
**Expected**: No resource leaks, backend properly cleaned up

### TASK-009: Task Cancellation
**Test**: ReliabilityTests.testDiarizationTaskCancellation  
**Type**: Unit (async)  
**Steps**:
1. Start transcription with diarization
2. Verify diarizationTask stored
3. Call stop()
4. Verify task cancelled
**Expected**: Task.isCancelled true, no dangling tasks

### TASK-010: O(n) to O(1) Fix
**Test**: PerformanceTests.testVadManagerO1Operations  
**Type**: Performance  
**Steps**:
1. Process 10000 audio chunks through VAD
2. Measure time per chunk
3. Verify constant time regardless of history size
**Expected**: Time per chunk constant, not growing with buffer size

### TASK-011: Error Handling
**Test**: ReliabilityTests.testVadErrorTracking  
**Type**: Unit  
**Steps**:
1. Mock VAD to throw errors
2. Process multiple chunks
3. Verify consecutive error counter increments
4. Verify delegate notified after threshold
**Expected**: Errors tracked, delegate notified

### TASK-012: Safe Pointer Access
**Test**: SafetyTests.testNoForceUnwrapBaseAddress  
**Type**: Static Analysis  
**Steps**:
1. Run `grep -n "baseAddress!"` on CircularAudioBuffer.swift
**Expected**: No matches found

**Test**: SafetyTests.testGuardLetBaseAddress  
**Type**: Unit  
**Steps**:
1. Create CircularAudioBuffer with invalid configuration
2. Call method that accesses baseAddress
3. Verify graceful error handling
**Expected**: Error thrown, no crash

## Verification Commands

### Pre-Implementation
```bash
# Verify review findings exist
grep -n "extension ChunkedSpeechBuffer" OpenOats/Sources/OpenOats/Infrastructure/Performance/ChunkedSpeechBuffer.swift
grep -n "apiKey: String" OpenOats/Sources/OpenOats/Transcription/TranscriptionEngine.swift
grep -n "Array.*dropFirst" OpenOats/Sources/OpenOats/Infrastructure/Performance/ChunkedSpeechBuffer.swift
```

### Post-Implementation
```bash
# Verify fixes
swift build
grep -n "extension VDSPChunkedSpeechBuffer" OpenOats/Sources/OpenOats/Infrastructure/Performance/ChunkedSpeechBuffer.swift
grep -n "apiKey: SecureString" OpenOats/Sources/OpenOats/Transcription/TranscriptionEngine.swift
swift test --filter PerformanceTests
grep -n "baseAddress!" OpenOats/Sources/OpenOats/Infrastructure/Performance/CircularAudioBuffer.swift || echo "PASS: No force unwraps"
```

## Test Execution Order

1. **Static Analysis Tests** (fast, no build needed)
2. **Unit Tests** (isolated, fast feedback)
3. **Integration Tests** (verify component interactions)
4. **Performance Tests** (verify O(n) behavior)

## Success Criteria

- [ ] All 12 tasks have corresponding test coverage
- [ ] swift test passes with 100% success rate
- [ ] Performance tests show linear (not quadratic) scaling
- [ ] Security scan shows no plain String API keys
- [ ] Static analysis shows no force unwraps on unsafe pointers
- [ ] Actor reentrancy tests pass under concurrent load

## Regression Prevention

Add these checks to CI/CD:

```yaml
# .github/workflows/security.yml
- name: Check for plain String API keys
  run: |
    if grep -r "apiKey: String" OpenOats/Sources/; then
      echo "ERROR: Found plain String API key usage"
      exit 1
    fi

# .github/workflows/performance.yml
- name: Run performance benchmarks
  run: swift test --filter PerformanceTests
```
