---
source_review: .wfc/reviews/REVIEW-feat-3tier-clean-architecture-002-swift.md
review_verdict: BLOCKED
plan_type: remediation
swift_specialized: true
---

# Swift 6 Compliance & Performance Remediation Plan

**Derived from**: Swift-Specialized Review (REVIEW-feat-3tier-clean-architecture-002-swift.md)  
**Goal**: Fix all P0 Swift 6 concurrency blockers and P1 performance issues  
**Estimated Effort**: 4-6 hours  
**Risk**: Medium (touches core transcription and concurrency paths)

---

## Execution Wave Summary

| Wave | Focus | Tasks | Est. Time |
|------|-------|-------|-----------|
| **Wave 1** | Swift 6 Critical Fixes (P0) | 12 tasks | 2-3 hours |
| **Wave 2** | Performance Hot Paths (P1) | 10 tasks | 1.5-2 hours |
| **Wave 3** | Swift Idiomatic Cleanup (P2) | 8 tasks | 1 hour |
| **Wave 4** | Complexity Reduction (EEDOM P2) | 6 tasks | 2-3 hours |

---

## Wave 1: Swift 6 Critical Fixes (P0)

### TASK-001: Fix [weak self] Anti-Pattern in ImportAudioUseCase
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: []
- **Canary**: true
- **Files**: OpenOats/Sources/OpenOats/Business/UseCases/ImportAudioUseCase.swift
- **Finding**: ImportAudioUseCase.swift:181 - [weak self] in actor prevents progress updates
- **Acceptance Criteria**:
  - [ ] Remove `[weak self]` from progressHandler closure at line 181
  - [ ] Verify `await self.reportProgress()` is called correctly
  - [ ] Run tests: `swift test --filter ImportAudioUseCaseTests`
  - [ ] Verify no compiler warnings with `-strict-concurrency=complete`

**Exact Change**:
```swift
// Line 181: Replace this:
progressHandler: { [weak self] progress in
    let adjustedProgress = 0.6 + (progress.percentage * 0.3)
    await self?.reportProgress(adjustedProgress)
}

// With this:
progressHandler: { progress in
    let adjustedProgress = 0.6 + (progress.percentage * 0.3)
    await self.reportProgress(adjustedProgress)
}
```

---

### TASK-002: Document @unchecked Sendable in MLXTranscriptionService
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Services/MLX/MLXTranscriptionService.swift
- **Finding**: MLXTranscriptionService.swift:153 - @unchecked Sendable without safety docs
- **Acceptance Criteria**:
  - [ ] Add SAFETY comment above AnySendableMLXModel struct
  - [ ] Document why MLX model access is thread-safe
  - [ ] Verify no new warnings

**Exact Change**:
```swift
// Line 153: Add before struct:
/// Wrapper that ensures MLX model is only accessed from the actor's isolation context
/// SAFETY: This is safe because:
/// 1. The model is only accessed from within MLXTranscriptionService (an actor)
/// 2. MLX models are thread-safe for inference by design
/// 3. The generate closure captures the model strongly within the actor
private struct AnySendableMLXModel: @unchecked Sendable {
```

---

### TASK-003: Remove Redundant @unchecked Sendable from WhisperKit Actor
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Services/WhisperKit/WhisperKitTranscriptionService.swift
- **Finding**: WhisperKitTranscriptionService.swift:59 - @unchecked Sendable on actor
- **Acceptance Criteria**:
  - [ ] Remove `@unchecked Sendable` from actor declaration
  - [ ] Verify actors are implicitly Sendable
  - [ ] Run tests: `swift test --filter WhisperKit`

**Exact Change**:
```swift
// Line 59: Replace this:
@preconcurrency public actor WhisperKitTranscriptionService: TranscriptionService, StreamingTranscriptionService, BatchTranscriptionService, @unchecked Sendable {

// With this:
@preconcurrency public actor WhisperKitTranscriptionService: TranscriptionService, StreamingTranscriptionService, BatchTranscriptionService {
```

---

### TASK-004: Fix Error? Not Sendable in TranscriptionResult
- **Complexity**: M
- **Wave**: 1
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Performance/NonBlockingProtocols.swift
- **Finding**: NonBlockingProtocols.swift:49 - Error? not Sendable
- **Acceptance Criteria**:
  - [ ] Create TranscriptionErrorInfo struct with Sendable conformance
  - [ ] Replace `Error?` with `TranscriptionErrorInfo?` in TranscriptionResult
  - [ ] Update all call sites to convert Error to TranscriptionErrorInfo
  - [ ] Run tests: `swift test --filter NonBlockingProtocols`

**Exact Change**:
```swift
// Line 49: Add before TranscriptionResult:
public struct TranscriptionErrorInfo: Sendable {
    public let errorDescription: String
    public let errorCode: Int?
    
    public init(error: Error) {
        self.errorDescription = error.localizedDescription
        self.errorCode = (error as NSError).code
    }
}

// Line 54: Replace:
public let error: Error?

// With:
public let error: TranscriptionErrorInfo?
```

---

### TASK-005: Fix defer with Async Calls in StreamingBufferProtocols
- **Complexity**: M
- **Wave**: 1
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Audio/StreamingBufferProtocols.swift
- **Finding**: StreamingBufferProtocols.swift:353 - defer with async calls doesn't work
- **Acceptance Criteria**:
  - [ ] Remove defer block with async calls
  - [ ] Add explicit cleanup in do/catch/finally pattern
  - [ ] Ensure buffers are released on both success and error paths
  - [ ] Run tests: `swift test --filter StreamingBufferProtocols`

**Exact Change**:
```swift
// Line 353: Replace defer block with explicit cleanup:
// Remove:
defer {
    Task {
        await bufferPool.release(&micBuffer)
        await bufferPool.release(&sysBuffer)
    }
}

// Add after do block and in catch block:
do {
    // ... processing ...
    await bufferPool.release(&micBuffer)
    await bufferPool.release(&sysBuffer)
} catch {
    await bufferPool.release(&micBuffer)
    await bufferPool.release(&sysBuffer)
    throw error
}
```

---

### TASK-006: Fix Nonisolated Accessing Actor State in ExportTranscriptUseCase
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Business/UseCases/ExportTranscriptUseCase.swift
- **Finding**: ExportTranscriptUseCase.swift:192 - nonisolated accessing actor state
- **Acceptance Criteria**:
  - [ ] Remove `nonisolated` from reportProgress method
  - [ ] Add `await` to all reportProgress calls
  - [ ] Verify no data races

**Exact Change**:
```swift
// Line 192: Replace:
nonisolated private func reportProgress(_ value: Double) {

// With:
private func reportProgress(_ value: Double) {
```

---

### TASK-007: Fix Actor-Isolated Computed Property in GenerateNotesUseCase
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Business/UseCases/GenerateNotesUseCase.swift
- **Finding**: GenerateNotesUseCase.swift:76 - isExecuting async property anti-pattern
- **Acceptance Criteria**:
  - [ ] Replace computed property with explicit method
  - [ ] Update all call sites

**Exact Change**:
```swift
// Line 76: Replace:
public var isExecuting: Bool {
    get async { currentTask != nil }
}

// With:
public func isExecuting() async -> Bool {
    currentTask != nil
}
```

---

### TASK-008: Document nonisolated(unsafe) in StreamingTranscriber
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Transcription/StreamingTranscriber.swift
- **Finding**: StreamingTranscriber.swift:579 - nonisolated(unsafe) without docs
- **Acceptance Criteria**:
  - [ ] Add SAFETY comment before nonisolated(unsafe) usage

**Exact Change**:
```swift
// Line 579: Add before:
// SAFETY: This is safe because:
// 1. The closure is synchronous (no suspension points between set and read)
// 2. The converter guarantees single-threaded access during convert()
// 3. The flag is reset for each new conversion operation
nonisolated(unsafe) var consumed = false
```

---

### TASK-009: Fix Cancellation Flag Not Synchronized in GenerateNotesUseCase
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: [TASK-007]
- **Files**: OpenOats/Sources/OpenOats/Business/UseCases/GenerateNotesUseCase.swift
- **Finding**: GenerateNotesUseCase.swift:72 - cancellation flag not synchronized
- **Acceptance Criteria**:
  - [ ] Use Task.isCancelled exclusively
  - [ ] Remove manual isCancelled flag

**Exact Change**:
```swift
// Line 72: Replace manual flag with Task.checkCancellation():
// Remove: private var isCancelled = false
// Remove: public func cancel() { isCancelled = true }
// Use: try Task.checkCancellation() in execute method
```

---

### TASK-010: Fix AsyncStream Continuation Race in ExportTranscriptUseCase
- **Complexity**: M
- **Wave**: 1
- **Dependencies**: [TASK-006]
- **Files**: OpenOats/Sources/OpenOats/Business/UseCases/ExportTranscriptUseCase.swift
- **Finding**: ExportTranscriptUseCase.swift:88 - AsyncStream continuation race
- **Acceptance Criteria**:
  - [ ] Use proper AsyncStream initialization pattern
  - [ ] Capture continuation immediately

**Exact Change**:
```swift
// Line 88: Replace with:
nonisolated public var progressStream: AsyncStream<Double> {
    AsyncStream { continuation in
        Task {
            await self.registerContinuation(continuation)
        }
    }
}

private func registerContinuation(_ continuation: AsyncStream<Double>.Continuation) {
    self.progressContinuation = continuation
}
```

---

### TASK-011: Fix DIContainer Task Race Condition
- **Complexity**: M
- **Wave**: 1
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/DI/DIContainer.swift
- **Finding**: DIContainer.swift:97 - Task-based initialization race
- **Acceptance Criteria**:
  - [ ] Make init @MainActor or use proper async initialization
  - [ ] Remove fire-and-forget Task

**Exact Change**:
```swift
// Line 97: Replace Task-based init with:
@MainActor
init(mode: DIContainerRuntimeMode) {
    self.mode = mode
    self.cachedViewModelFactory = DIContainerViewModelFactoryImpl()
}
```

---

### TASK-012: Fix URL Injection in AssemblyAITranscriptionService
- **Complexity**: S
- **Wave**: 1
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Services/Cloud/AssemblyAITranscriptionService.swift
- **Finding**: AssemblyAITranscriptionService.swift:434 - URL injection via interpolation
- **Acceptance Criteria**:
  - [ ] Use URLComponents instead of string interpolation
  - [ ] Add percent encoding

**Exact Change**:
```swift
// Line 434: Replace:
let pollURL = URL(string: "https://api.assemblyai.com/v2/transcript/\(id)")!

// With:
var components = URLComponents(string: "https://api.assemblyai.com/v2/transcript")
components?.path.append("/\(id)")
guard let pollURL = components?.url else {
    throw TranscriptionError.invalidTranscriptID
}
```

---

## Wave 2: Performance Hot Paths (P1)

### TASK-013: Fix Unbounded Streaming Buffer Growth
- **Complexity**: L
- **Wave**: 2
- **Dependencies**: [TASK-008]
- **Files**: OpenOats/Sources/OpenOats/Transcription/StreamingTranscriber.swift
- **Finding**: StreamingTranscriber.swift:528 - unbounded array growth
- **Acceptance Criteria**:
  - [ ] Implement chunked accumulation with fixed-size buffers
  - [ ] Flush at 30-second threshold
  - [ ] Maintain overlap context between chunks

---

### TASK-014: Replace Array.removeFirst with Circular Buffer
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Transcription/StreamingTranscriber.swift
- **Finding**: StreamingTranscriber.swift:186 - O(n) array shift
- **Acceptance Criteria**:
  - [ ] Use CircularAudioBuffer instead of Array.removeFirst
  - [ ] Verify no quadratic behavior

---

### TASK-015: Use vDSP for Audio Deinterleave
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Services/MLX/MLXAudioProcessor.swift
- **Finding**: MLXAudioProcessor.swift:171 - scalar deinterleave
- **Acceptance Criteria**:
  - [ ] Replace scalar loop with vDSP_deqinter
  - [ ] Verify 2-4x speedup

---

### TASK-016: Use vDSP for Audio Resampling
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Services/MLX/MLXAudioProcessor.swift
- **Finding**: MLXAudioProcessor.swift:216 - scalar resampling
- **Acceptance Criteria**:
  - [ ] Replace scalar loop with vDSP_vlint
  - [ ] Verify performance improvement

---

### TASK-017: Use vDSP for WhisperKit mixToMono
- **Complexity**: S
- **Wave**: 2
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Services/WhisperKit/WhisperKitAudioProcessor.swift
- **Finding**: WhisperKitAudioProcessor.swift:277 - scalar mixToMono
- **Acceptance Criteria**:
  - [ ] Replace with vDSP_vadd + vDSP_vsmul
  - [ ] Verify 4-8x speedup

---

### TASK-018: Fix Array Slicing Copy in VAD Loop
- **Complexity**: S
- **Wave**: 2
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Transcription/StreamingTranscriber.swift
- **Finding**: StreamingTranscriber.swift:181 - array slicing creates copy
- **Acceptance Criteria**:
  - [ ] Use withUnsafeBufferPointer to avoid copy

---

### TASK-019: Optimize Buffer Zeroing with vDSP_vclr
- **Complexity**: S
- **Wave**: 2
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Audio/StreamingBufferProtocols.swift
- **Finding**: StreamingBufferProtocols.swift:129 - scalar zeroing
- **Acceptance Criteria**:
  - [ ] Replace scalar loop with vDSP_vclr

---

### TASK-020: Fix Per-Frame Allocation in AudioCaptureTask
- **Complexity**: M
- **Wave**: 2
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Performance/AudioCaptureTask.swift
- **Finding**: AudioCaptureTask.swift:262 - per-frame allocation
- **Acceptance Criteria**:
  - [ ] Process frames in chunks
  - [ ] Reduce allocations

---

### TASK-021: Optimize Circular Buffer Write
- **Complexity**: S
- **Wave**: 2
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Audio/StreamingBufferProtocols.swift
- **Finding**: StreamingBufferProtocols.swift:208 - scalar write loop
- **Acceptance Criteria**:
  - [ ] Use bulk copy with wrapping

---

### TASK-022: Fix flatMap Intermediate Arrays
- **Complexity**: S
- **Wave**: 2
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Transcription/StreamingTranscriber.swift
- **Finding**: StreamingTranscriber.swift:209 - flatMap creates intermediates
- **Acceptance Criteria**:
  - [ ] Pre-allocate result array
  - [ ] Copy manually

---

## Wave 3: Swift Idiomatic Cleanup (P2)

### TASK-023: Add @preconcurrency Imports for External Modules
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: []
- **Files**: Multiple files importing WhisperKit, MLX, FluidAudio
- **Finding**: Missing @preconcurrency for non-Sendable external imports
- **Acceptance Criteria**:
  - [ ] Add @preconcurrency import WhisperKit
  - [ ] Add @preconcurrency import MLX
  - [ ] Add @preconcurrency import FluidAudio

---

### TASK-024: Move Test Factories Out of Production Files
- **Complexity**: M
- **Wave**: 3
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Presentation/ViewModels/DefaultSessionViewModel.swift
- **Finding**: DefaultSessionViewModel.swift:125 - 18 factory functions in production
- **Acceptance Criteria**:
  - [ ] Move factories to Tests/OpenOatsTests/Helpers/

---

### TASK-025: Standardize Protocol Naming
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Protocols/RepositoryProtocols.swift
- **Finding**: Inconsistent "Protocol" suffix
- **Acceptance Criteria**:
  - [ ] Remove "Protocol" suffix from SessionRepositoryProtocol

---

### TASK-026: Split Package.swift into Layered Targets
- **Complexity**: L
- **Wave**: 3
- **Dependencies**: []
- **Files**: OpenOats/Package.swift
- **Finding**: Single target combines all layers
- **Acceptance Criteria**:
  - [ ] Create OpenOatsDomain target
  - [ ] Create OpenOatsBusiness target
  - [ ] Create OpenOatsInfrastructure target
  - [ ] Create OpenOatsPresentation target

---

### TASK-027: Fix PresentationError Error Not Sendable
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Presentation/ViewModels/ViewModelProtocols.swift
- **Finding**: ViewModelProtocols.swift:7 - Error not Sendable
- **Acceptance Criteria**:
  - [ ] Store error description instead of Error

---

### TASK-028: Add Explicit Access Levels to Factory Protocols
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/DI/FactoryProtocols.swift
- **Finding**: FactoryProtocols.swift:7 - implicit internal access
- **Acceptance Criteria**:
  - [ ] Add public to UseCaseFactory
  - [ ] Add public to ViewModelFactory

---

### TASK-029: Fix CheckedContinuation Multiple Resume Risk
- **Complexity**: M
- **Wave**: 3
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Infrastructure/Performance/NonBlockingProtocols.swift
- **Finding**: NonBlockingProtocols.swift:140 - continuation resume risk
- **Acceptance Criteria**:
  - [ ] Add guard to ensure single resume

---

### TASK-030: Remove [weak self] from Timer in ViewModel
- **Complexity**: S
- **Wave**: 3
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Presentation/ViewModels/DefaultSessionViewModel.swift
- **Finding**: DefaultSessionViewModel.swift:409 - unnecessary [weak self]
- **Acceptance Criteria**:
  - [ ] Use strong capture since Timer fires on main run loop

---

## Wave 4: Complexity Reduction (EEDOM P2)

### TASK-031: Refactor finalizeCurrentSession (CCN 32 → <15)
- **Complexity**: L
- **Wave**: 4
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/App/LiveSessionController.swift
- **Finding**: EEDOM - CCN 32, highest complexity function
- **Acceptance Criteria**:
  - [ ] Extract session finalization into smaller methods
  - [ ] Reduce CCN from 32 to <15
  - [ ] Maintain all existing functionality
  - [ ] Add unit tests for extracted methods

**Refactoring Strategy**:
```swift
// Extract state-specific finalization
private func finalizeActiveSession(_ session: Session) async throws
private func finalizePausedSession(_ session: Session) async throws
private func cleanupSessionResources(_ session: Session) async
private func persistSessionState(_ session: Session) async throws
```

---

### TASK-032: Refactor StreamingTranscriber.run (CCN 29 → <15)
- **Complexity**: L
- **Wave**: 4
- **Dependencies**: [TASK-013, TASK-014]
- **Files**: OpenOats/Sources/OpenOats/Transcription/StreamingTranscriber.swift
- **Finding**: EEDOM - CCN 29, core transcription loop too complex
- **Acceptance Criteria**:
  - [ ] Extract VAD processing into separate method
  - [ ] Extract transcription submission into separate method
  - [ ] Reduce CCN from 29 to <15
  - [ ] Verify streaming still works correctly

**Refactoring Strategy**:
```swift
// Extract processing phases
private func processVADChunk(_ buffer: AudioBuffer) async throws -> VADResult
private func submitForTranscription(_ segment: AudioSegment) async throws
private func handleTranscriptionResult(_ result: TranscriptionResult) async
```

---

### TASK-033: Refactor TranscriptionEngine.start (CCN 26 → <15)
- **Complexity**: L
-- **Wave**: 4
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Transcription/TranscriptionEngine.swift
- **Finding**: EEDOM - CCN 26, engine startup too complex
- **Acceptance Criteria**:
  - [ ] Extract backend initialization
  - [ ] Extract audio capture setup
  - [ ] Reduce CCN from 26 to <15

---

### TASK-034: Refactor extractSamples (CCN 22 → <15)
- **Complexity**: M
- **Wave**: 4
- **Dependencies**: [TASK-032]
- **Files**: OpenOats/Sources/OpenOats/Transcription/StreamingTranscriber.swift
- **Finding**: EEDOM - CCN 22, sample extraction too complex
- **Acceptance Criteria**:
  - [ ] Extract format conversion logic
  - [ ] Extract buffer management logic
  - [ ] Reduce CCN from 22 to <15

---

### TASK-035: Refactor writeMicBuffer (CCN 21 → <15)
- **Complexity**: M
- **Wave**: 4
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Audio/AudioRecorder.swift
- **Finding**: EEDOM - CCN 21, buffer writing too complex
- **Acceptance Criteria**:
  - [ ] Extract buffer allocation logic
  - [ ] Extract file I/O logic
  - [ ] Reduce CCN from 21 to <15

---

### TASK-036: Refactor mergeAndEncode (CCN 20 → <15)
- **Complexity**: M
- **Wave**: 4
- **Dependencies**: []
- **Files**: OpenOats/Sources/OpenOats/Audio/AudioRecorder.swift
- **Finding**: EEDOM - CCN 20, merge logic too complex
- **Acceptance Criteria**:
  - [ ] Extract encoding logic
  - [ ] Extract merging logic
  - [ ] Reduce CCN from 20 to <15

---

## Dependency Graph

```
Wave 1 (P0 - Swift 6 Critical):
  TASK-001 (canary) -> TASK-009
  TASK-002, TASK-003, TASK-004, TASK-005, TASK-006
  TASK-007 -> TASK-009
  TASK-008, TASK-010, TASK-011, TASK-012

Wave 2 (P1 - Performance):
  TASK-008 -> TASK-013
  TASK-014, TASK-015, TASK-016, TASK-017, TASK-018
  TASK-019, TASK-020, TASK-021, TASK-022

Wave 3 (P2 - Cleanup):
  All tasks independent

Wave 4 (P2 - Complexity Reduction):
  TASK-013, TASK-014 -> TASK-032
  TASK-032 -> TASK-034
  TASK-031, TASK-033, TASK-035, TASK-036 independent
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Swift 6 breaking changes | Test with `-strict-concurrency=complete` flag |
| Performance regressions | Benchmark before/after with PerformanceTests |
| Actor isolation issues | Run ConcurrencySafetyTests after each change |
| Memory leaks | Run MemoryManagementTests after buffer changes |

---

## Success Criteria

- [ ] All P0 tasks complete (Swift 6 compliance)
- [ ] Zero compiler warnings with strict concurrency
- [ ] All existing tests pass
- [ ] Performance tests show improvement or no regression
- [ ] Re-run wfc-review shows PASSED or reduced findings
- [ ] EEDOM complexity: All CCN >20 functions reduced to <15
- [ ] EEDOM maintainability: Maintain A grade (90+/100)
