
## 2026-05-01 15:57:46 - Swift 6 Compliance Remediation Plan

**Source**: Swift-Specialized Review (REVIEW-feat-3tier-clean-architecture-002-swift.md)  
**Goal**: Fix all P0 Swift 6 concurrency blockers and P1 performance issues  
**Tasks**: 30 (Wave 1: 12, Wave 2: 10, Wave 3: 8)  
**Properties**: 12 (4 SAFETY, 3 LIVENESS, 4 INVARIANT, 5 TEST)  
**Test Cases**: 12  
**Status**: Ready for implementation  
**Location**: `.wfc/plans/plan_review002-swift-fixes_20260501_155746/`

### Key Deliverables
- TASKS.md: 30 ultra-granular tasks with exact code changes
- PROPERTIES.md: 12 formal properties for verification
- TEST-PLAN.md: 12 test cases with compiler verification

### Critical Issues Addressed
1. [weak self] in actors (ImportAudioUseCase.swift:181)
2. @unchecked Sendable without docs (MLXTranscriptionService.swift:153)
3. Error? not Sendable (NonBlockingProtocols.swift:49)
4. defer with async calls (StreamingBufferProtocols.swift:353)
5. URL injection (AssemblyAITranscriptionService.swift:434)
6. Unbounded streaming buffer (StreamingTranscriber.swift:528)

### Next Step
Run `/wfc-implement` on this plan to execute fixes.

### Update 2026-05-01 16:45:00 - EEDOM Complexity Integration

**Added Wave 4**: Complexity Reduction based on EEDOM findings
- 6 new tasks targeting CCN >20 functions
- Target: Reduce CCN from 32→<15 for critical functions
- Preserve maintainability grade A (94/100)

**Wave 4 Tasks**:
- TASK-031: finalizeCurrentSession (CCN 32→<15)
- TASK-032: StreamingTranscriber.run (CCN 29→<15)
- TASK-033: TranscriptionEngine.start (CCN 26→<15)
- TASK-034: extractSamples (CCN 22→<15)
- TASK-035: writeMicBuffer (CCN 21→<15)
- TASK-036: mergeAndEncode (CCN 20→<15)

**Updated Totals**:
- Tasks: 36 (was 30)
- Properties: 15 (was 12)
- Test Cases: 16 (was 12)
- Waves: 4 (was 3)

**EEDOM Baseline**:
- Security: 100/100 ✅
- Quality: 100/100 ✅
- Maintainability: 94/100 (A) ✅
- High Complexity Functions: 51
- Avg CCN: 2.2
