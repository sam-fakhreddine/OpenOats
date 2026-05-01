# OpenOats 3-Tier Architecture Design Epic

## Overview
Design comprehensive 3-tier architecture for OpenOats macOS transcription system to replace current "Big Ball of Mud" structure (36K lines, massive files: NotesView 3.7K lines, SessionRepository 2.1K lines).

**Phase**: DESIGN ONLY (No Implementation)  
**Complexity**: HIGH  
**Target**: Clean separation with protocol-based dependency injection, Swift 6.2 concurrency

**Critical Issues Addressed** (from `.temp/` analysis):
- **Data races** in StreamingTranscriber and MicCapture (C1, C2)
- **OOM crashes** from unbounded memory loading (C3)
- **Temp file durability** issues (C4)
- **Complexity hotspots** (CCN 34, 32, 27 in audio pipeline)
- **Latency spikes** from blocking transcription calls (H1)
- **Performance issues** with scalar DSP under locks (H2)

## Execution Waves

| Wave | Focus | Tasks | Deliverables |
|------|-------|-------|--------------|
| Wave 1 | Foundation & Domain | TASK-001 to TASK-003 | Domain entities, Core protocols, Error contracts |
| Wave 2 | Boundary Contracts | TASK-004 to TASK-007 | Layer protocols, DI strategy, Data flow diagrams |
| Wave 3 | Infrastructure & Migration | TASK-008 to TASK-018 | Migration strategy, Risk assessment, Critical fixes, Implementation guide |
| Wave 4 | Validation | TASK-012 to TASK-014 | Design review, Acceptance criteria, Test plan |

---

## Wave 1: Foundation & Domain Design

### TASK-001: Design Domain Layer Entities and Value Objects
**Complexity**: M  
**Dependencies**: []  
**Canary**: true  
**Wave**: 1  
**Files**: Design output (no code changes)

**Description**:  
Define core domain entities with proper Swift value semantics:
- `Meeting` - Root aggregate for meeting sessions
- `Session` - Individual recording session
- `Transcript` - Collection of transcribed content
- `Utterance` - Single speech segment with speaker and timing
- `Speaker` - Speaker identity with voice signature
- `Note` - AI-generated meeting notes
- `AudioSegment` - Raw audio with metadata

**Acceptance Criteria**:
- [ ] All entities are immutable value types (struct, not class)
- [ ] All entities conform to `Equatable`, `Hashable`, `Codable`, `Sendable`
- [ ] No external framework dependencies in domain layer
- [ ] Properties use appropriate types (UUID, Date, Duration, etc.)
- [ ] Documentation comments explain business invariants
- [ ] Example: `Utterance` has `speakerId: SpeakerID`, `text: String`, `startTime: Duration`, `confidence: Double`

**Formal Properties**:
- SAFETY: Domain entities never expose mutable references
- INVARIANT: All domain types are Sendable-safe for Swift 6.2

---

### TASK-002: Design Domain Error Types and Result Types
**Complexity**: S  
**Dependencies**: [TASK-001]  
**Wave**: 1  
**Files**: Design output (no code changes)

**Description**:  
Create domain-specific error taxonomy:
- `TranscriptionError` - Backend failures, audio issues, timeout
- `StorageError` - Persistence failures, corruption, migration
- `ValidationError` - Invalid input, malformed data
- `NetworkError` - API failures, connectivity
- `AudioError` - Capture failures, permission denied, format issues

**Acceptance Criteria**:
- [ ] Errors are enum cases with associated values for context
- [ ] Errors conform to `Error`, `LocalizedError` protocols
- [ ] Error hierarchy allows catching broad or specific cases
- [ ] Associated values provide actionable debugging info
- [ ] Example: `case backendFailed(backend: String, reason: String, recoverable: Bool)`

**Formal Properties**:
- SAFETY: All error paths are exhaustively handled in protocols
- INVARIANT: Errors preserve context for debugging without exposing internals

---

### TASK-003: Define Core Type Aliases and Identifiers
**Complexity**: S  
**Dependencies**: [TASK-001]  
**Wave**: 1  
**Files**: Design output (no code changes)

**Description**:  
Create strong type aliases for domain identifiers:
- `MeetingID` - UUID wrapper for meeting identification
- `SessionID` - UUID wrapper for session identification
- `SpeakerID` - UUID wrapper for speaker identification
- `TranscriptID` - UUID wrapper for transcript identification
- `BackendID` - String wrapper for backend names

**Acceptance Criteria**:
- [ ] All IDs are distinct types (not raw typealiases)
- [ ] IDs conform to `RawRepresentable`, `Codable`, `Hashable`, `Sendable`
- [ ] String interpolation is disabled or controlled
- [ ] Example: `struct MeetingID: RawRepresentable, Sendable { let rawValue: UUID }`

**Formal Properties**:
- INVARIANT: ID types prevent accidental mixing of different ID kinds

---

## Wave 2: Boundary Contracts & Layer Protocols

### TASK-004: Design Presentation Layer Protocols
**Complexity**: M  
**Dependencies**: [TASK-001, TASK-002]  
**Wave**: 2  
**Files**: Design output (no code changes)

**Description**:  
Define protocols for SwiftUI views to interact with business logic:
- `SessionViewModel` - Observable object for session UI state
- `TranscriptViewModel` - Observable object for transcript display
- `SettingsViewModel` - Observable object for settings management
- `CoordinatorProtocol` - Navigation and flow coordination

**Acceptance Criteria**:
- [ ] ViewModels use `@MainActor` for UI-bound properties
- [ ] Protocols expose `ObservableObject` or `@Observable` patterns
- [ ] No direct dependencies on Infrastructure layer
- [ ] Methods return async results for business operations
- [ ] State changes are published for SwiftUI observation
- [ ] Example: `func startRecording() async throws -> SessionID`

**Formal Properties**:
- SAFETY: ViewModels never perform direct I/O operations
- LIVENESS: UI updates are delivered on MainActor

---

### TASK-005: Design Business Logic Layer (Use Cases)
**Complexity**: L  
**Dependencies**: [TASK-001, TASK-002, TASK-004]  
**Wave**: 2  
**Files**: Design output (no code changes)

**Description**:  
Define use case protocols for core operations:
- `StartSessionUseCase` - Begin recording and transcription
- `StopSessionUseCase` - End session and finalize
- `GenerateNotesUseCase` - AI-powered note generation
- `ExportTranscriptUseCase` - Export in various formats
- `ImportAudioUseCase` - Process external audio files
- `SwitchBackendUseCase` - Change transcription provider

**Acceptance Criteria**:
- [ ] Each use case is a single responsibility protocol
- [ ] Protocols define async execution with error handling
- [ ] Use cases depend only on Domain and Infrastructure protocols
- [ ] Input/output defined as value types
- [ ] Use cases orchestrate multiple infrastructure services
- [ ] Example: `protocol StartSessionUseCase { func execute(input: StartSessionInput) async throws -> Session }`

**Formal Properties**:
- SAFETY: Use cases maintain transactional consistency
- LIVENESS: Long-running operations are cancellable

---

### TASK-006: Design Infrastructure Layer Protocols
**Complexity**: L  
**Dependencies**: [TASK-001, TASK-002]  
**Wave**: 2  
**Files**: Design output (no code changes)

**Description**:  
Define protocols for external concerns:

**Transcription Services:**
- `TranscriptionService` - Abstract transcription interface
- `StreamingTranscriptionService` - Real-time transcription
- `BatchTranscriptionService` - File-based transcription

**Audio Services:**
- `AudioCaptureService` - Microphone and system audio capture
- `AudioFormatService` - Format conversion and validation

**Storage Services:**
- `SessionRepository` - Session persistence (refactor from 2.1K lines)
- `TranscriptRepository` - Transcript storage and retrieval
- `SettingsRepository` - User preferences persistence

**AI Services:**
- `LLMService` - OpenRouter, Ollama integration
- `EmbeddingService` - Voyage embedding generation
- `SuggestionService` - AI-powered suggestions

**Acceptance Criteria**:
- [ ] Each service protocol has clear, single responsibility
- [ ] Async/await signatures with proper error propagation
- [ ] No dependencies on Presentation or Business Logic layers
- [ ] Implementations are swappable via protocols
- [ ] Example: `protocol TranscriptionService: Sendable { func transcribe(audio: AudioStream) -> AsyncThrowingStream<TranscriptionSegment, Error> }`

**Formal Properties**:
- SAFETY: Infrastructure services are Sendable-safe
- LIVENESS: Resource cleanup on cancellation

---

### TASK-007: Design Dependency Injection Strategy
**Complexity**: M  
**Dependencies**: [TASK-004, TASK-005, TASK-006]  
**Wave**: 2  
**Files**: Design output (no code changes)

**Description**:  
Define DI container and composition patterns:
- `AppContainer` - Root composition root
- `ServiceFactory` - Factory for creating service implementations
- `ViewModelFactory` - Factory for creating view models with dependencies
- `UseCaseFactory` - Factory for creating use cases

**Acceptance Criteria**:
- [ ] Composition root initializes all dependencies at app startup
- [ ] Factory pattern abstracts concrete implementation creation
- [ ] Protocol-based injection throughout (no concrete types in upper layers)
- [ ] Test double injection supported via protocol conformance
- [ ] Lifecycle management defined (singleton vs transient)
- [ ] Example: `container.register(TranscriptionService.self) { MLXTranscriptionService() }`

**Formal Properties**:
- SAFETY: No circular dependencies in DI graph
- INVARIANT: All dependencies resolved at startup or explicitly lazy

---

## Wave 3: Migration Strategy & Documentation

### TASK-008: Create Migration Strategy from Big Ball of Mud
**Complexity**: XL  
**Dependencies**: [TASK-001, TASK-004, TASK-005, TASK-006, TASK-007]  
**Wave**: 3  
**Files**: Design output (no code changes)

**Description**:  
Design step-by-step migration plan from current state to clean architecture:

**Phase 1: Extract Domain (Weeks 1-2)**
- Create domain types alongside existing models
- Gradually migrate model usage to domain types

**Phase 2: Extract Infrastructure (Weeks 3-4)**
- Create repository protocols
- Extract SessionRepository (2.1K lines → multiple focused repositories)

**Phase 3: Extract Business Logic (Weeks 5-6)**
- Create use case protocols
- Move logic from NotesView (3.7K lines) into use cases

**Phase 4: Refactor Presentation (Weeks 7-8)**
- Create view models
- Refactor SwiftUI views to use view models

**Phase 5: Clean Up (Week 9)**
- Remove old code paths
- Verify all tests pass

**Acceptance Criteria**:
- [ ] Migration phases have clear boundaries and deliverables
- [ ] Each phase maintains backward compatibility
- [ ] Feature flags or branching strategy defined
- [ ] Rollback plan for each phase
- [ ] Testing strategy at each milestone
- [ ] Risk mitigation for 36K line codebase

**Formal Properties**:
- SAFETY: Each migration phase preserves existing functionality
- LIVENESS: Users can use app throughout migration

---

### TASK-009: Design Data Flow Diagrams
**Complexity**: M  
**Dependencies**: [TASK-004, TASK-005, TASK-006]  
**Wave**: 3  
**Files**: Design output (Mermaid diagrams)

**Description**:  
Create visual diagrams for:
1. **Architecture Overview** - 4-layer structure with arrows
2. **Session Lifecycle** - Start → Record → Transcribe → Stop → Save
3. **Real-time Transcription Flow** - Audio → Segments → UI updates
4. **Note Generation Flow** - Transcript → AI → Notes → Display
5. **Error Propagation** - How errors flow from Infrastructure → Business → Presentation

**Acceptance Criteria**:
- [ ] All diagrams use Mermaid format
- [ ] Layer boundaries clearly marked
- [ ] Data flow direction indicated with arrows
- [ ] Async boundaries and actor isolation marked
- [ ] Error paths clearly distinguished from happy path
- [ ] Example: Sequence diagram showing `View → ViewModel → UseCase → Service`

**Formal Properties**:
- INVARIANT: Data flow always unidirectional (Presentation → Business → Infrastructure)

---

### TASK-010: Design Transcription Backend Abstraction
**Complexity**: M  
**Dependencies**: [TASK-006]  
**Wave**: 3  **Files**: Design output (no code changes)

**Description**:  
Create detailed protocol hierarchy for multiple transcription backends:

**Protocol Hierarchy:**
```
TranscriptionService (base)
├── StreamingTranscriptionService
│   ├── MLXStreamingTranscriptionService
│   ├── WhisperKitStreamingTranscriptionService
│   └── AssemblyAIStreamingTranscriptionService
├── BatchTranscriptionService
│   ├── MLXBatchTranscriptionService
│   ├── WhisperKitBatchTranscriptionService
│   └── ParakeetBatchTranscriptionService
```

**Configuration:**
- `TranscriptionConfiguration` - Common settings (language, model, quality)
- `MLXConfiguration` - MLX-specific settings
- `WhisperKitConfiguration` - WhisperKit-specific settings
- `CloudConfiguration` - API keys, endpoints

**Acceptance Criteria**:
- [ ] Base protocol defines common interface
- [ ] Streaming vs Batch have appropriate async patterns
- [ ] Backend-specific configurations are separate from common config
- [ ] Factory can instantiate correct backend based on settings
- [ ] Error mapping from backend-specific to domain errors
- [ ] Example: `protocol StreamingTranscriptionService: TranscriptionService { var transcriptionStream: AsyncStream<TranscriptionSegment> { get } }`

**Formal Properties**:
- SAFETY: Backend failures don't crash the app
- LIVENESS: Backend switching doesn't lose in-progress transcription

---

### TASK-011: Document Swift 6.2 Concurrency Strategy
**Complexity**: M  
**Dependencies**: [TASK-001, TASK-006]  
**Wave**: 3  
**Files**: Design output (no code changes)

**Description**:  
Define concurrency patterns for Swift 6.2:

**Actor Strategy:**
- `@MainActor` for all UI-related code
- Custom actors for domain layer shared state
- `actor TranscriptionActor` for managing transcription state
- `actor SessionActor` for session management

**Sendable Conformance:**
- All domain types are Sendable
- All protocols specify Sendable requirements
- Infrastructure services are Sendable-safe

**Structured Concurrency:**
- Use `TaskGroup` for parallel operations
- Use `AsyncStream` for streaming transcription
- Proper cancellation propagation

**Acceptance Criteria**:
- [ ] Actor boundaries defined for each layer
- [ ] Sendable conformance strategy documented
- [ ] Structured concurrency patterns specified
- [ ] Cancellation handling defined for long-running operations
- [ ] Thread-safety documented for shared resources
- [ ] Example: `actor TranscriptionState { private var currentSession: Session? }`

**Formal Properties**:
- SAFETY: No data races across actor boundaries
- SAFETY: All shared mutable mutable state is actor-protected
- INVARIANT: All Sendable conformance is compiler-verifiable

---

### TASK-015: Address Critical Data Races and Concurrency Issues
**Complexity**: H  
**Dependencies**: [TASK-011]  
**Wave**: 3  
**Files**: Design output (no code changes)

**Description**:  
Address critical data races identified in deep architecture review (.temp/deep-architecture-review.md):

**C1. StreamingTranscriber Data Race:**
- **Issue**: `@unchecked Sendable` with mutable fields (`converter`, `rateTrackingStartDate`, `previousContext`, `effectiveSampleRate`)
- **Risk**: `EXC_BAD_ACCESS` if concurrent access occurs
- **Fix**: Convert to actor or use `OSAllocatedUnfairLock`
- **Design**: `actor StreamingTranscriptionActor` with isolated mutable state

**C2. MicCapture Audio Callback Data Race:**
- **Issue**: `tapCallCount += 1` on audio thread without synchronization
- **Risk**: Data race on mutable var from audio callback
- **Fix**: Use atomic operations or proper isolation
- **Design**: `nonisolated(unsafe)` with documentation OR proper actor isolation

**Acceptance Criteria**:
- [ ] All `@unchecked Sendable` types converted to proper actors
- [ ] Audio callback thread-safety documented
- [ ] Mutable state in concurrent contexts uses proper synchronization
- [ ] No `nonisolated(unsafe)` without explicit justification
- [ ] Actor isolation boundaries defined for audio pipeline
- [ ] Example: `actor StreamingTranscriptionActor { private var converter: AudioConverter? }`

**Formal Properties**:
- SAFETY: No `@unchecked Sendable` with mutable state
- SAFETY: Audio callbacks use thread-safe operations
- INVARIANT: All concurrent mutable state is properly isolated

---

### TASK-016: Fix Memory Management and OOM Prevention
**Complexity**: H  
**Dependencies**: [TASK-006]  
**Wave**: 3  
**Files**: Design output (no code changes)

**Description**:  
Address memory issues identified in deep architecture review (.temp/deep-architecture-review.md):

**C3. Unbounded Memory in mergeAndEncode:**
- **Issue**: `readAllMono()` loads entire recording into `[Float]` arrays
- **Risk**: 2-hour meeting at 48kHz = ~2.6GB memory → OOM kill on 8GB Macs
- **Fix**: Stream processing with fixed-size buffers
- **Design**: 
  - `AudioStreamProcessor` protocol with chunked processing
  - Buffer pool with 64K frame chunks (~768KB max regardless of recording length)
  - Streaming merge instead of loading entire file

**C4. Temp Audio File Durability:**
- **Issue**: `NSTemporaryDirectory()` can be purged by OS under memory pressure
- **Risk**: Recording files deleted during live recording
- **Fix**: Use Application Support directory
- **Design**: 
  - `AudioRecordingRepository` with configurable storage location
  - Application Support as default (durable, crash-recoverable)
  - Temp directory only for ephemeral cache

**H3. Unbounded Speech Buffer:**
- **Issue**: `speechSamples` grows until flush interval (30s = ~1.9MB)
- **Risk**: Latency spike on flush, memory pressure
- **Fix**: Sliding window approach
- **Design**: 
  - `AudioBuffer` with circular buffer implementation
  - Fixed-size window with overlap
  - Streaming transcription in chunks

**Acceptance Criteria**:
- [ ] Audio processing uses streaming (not load-all)
- [ ] Memory budget defined: 768KB max for audio buffers
- [ ] Recording files stored in Application Support (not temp)
- [ ] Circular buffer design for speech samples
- [ ] Buffer pool pattern for memory reuse
- [ ] Example: `struct AudioBuffer { private var circularBuffer: [Float]; let maxSize: Int }`

**Formal Properties**:
- SAFETY: Memory usage bounded regardless of recording length
- SAFETY: Recording files durable against OS purge
- LIVENESS: No OOM crashes on 8GB Macs
- INVARIANT: Audio buffer size < 1MB at all times

---

### TASK-017: Reduce Complexity Hotspots
**Complexity**: M  
**Dependencies**: [TASK-008]  
**Wave**: 3  
**Files**: Design output (no code changes)

**Description**:  
Address complexity hotspots identified in complexity analysis (.temp/complexity-analysis.txt):

**Top Complexity Offenders (CCN > 20):**

1. **writeMicBuffer (CCN 34, 108 lines)**
   - **Issues**: Audio format negotiation + ring buffer + error recovery + silence detection
   - **Fix**: Extract into 3 focused functions (CCN ~10 each):
     - `AudioFormatNegotiator` (format negotiation)
     - `RingBufferManager` (buffer management)
     - `SilenceDetector` (silence detection)

2. **finalizeCurrentSession (CCN 32, 240 lines)**
   - **Issues**: Teardown + save + export + notification + cleanup
   - **Fix**: Command pattern with single-responsibility operations:
     - `SessionTeardownUseCase`
     - `SessionPersistenceUseCase`
     - `SessionExportUseCase`
     - `NotificationDispatchUseCase`
     - `ResourceCleanupUseCase`

3. **StreamingTranscriber.run (CCN 27, 112 lines)**
   - **Issues**: Async loop + retry + timeout + partial result merging + cancellation
   - **Fix**: Extract concerns:
     - `RetryPolicy` wrapper
     - `PartialResultAccumulator`
     - `TranscriptionOrchestrator`

**Acceptance Criteria**:
- [ ] All functions have CCN < 15 (target: <10)
- [ ] No functions > 100 lines
- [ ] Single responsibility: each function does one thing
- [ ] Command pattern for complex orchestration
- [ ] Complexity reduction documented with before/after CCN
- [ ] Example: `writeMicBuffer` refactored to 3 functions at CCN 8-10 each

**Formal Properties**:
- INVARIANT: All functions have cyclomatic complexity < 15
- INVARIANT: All functions have lines of code < 100
- SAFETY: Complex operations use command pattern for clarity

---

### TASK-018: Fix Performance and Latency Issues
**Complexity**: M  
**Dependencies**: [TASK-015, TASK-016]  
**Wave**: 3  
**Files**: Design output (no code changes)

**Description**:  
Address performance issues identified in deep architecture review (.temp/deep-architecture-review.md):

**H1. Partial Transcription Blocks VAD Loop:**
- **Issue**: `backend.transcribe` awaited inline in VAD loop
- **Risk**: 200-500ms inference stalls VAD, audio buffers queue up
- **Fix**: Fire in child Task
- **Design**: 
  - `TranscriptionTaskManager` with `isRunningPartial` guard
  - Non-blocking transcription dispatch
  - Result callback when complete

**H2. Scalar Audio DSP Under NSLock:**
- **Issue**: `writeMicBuffer` runs entirely under lock including scalar downmix
- **Risk**: Contention with `writeSysBuffer`, no vDSP optimization
- **Fix**: vDSP + lock minimization
- **Design**: 
  - `AudioDSPProcessor` using vDSP for downmix
  - Process outside lock, only hold lock for file write
  - Separate read/write locks if needed

**H4. Unstructured Tasks Without Cancellation:**
- **Issue**: `Task { for await buffer in ... }` not cancelled when engine stops
- **Risk**: Dangling tasks for mic, system, diarization
- **Fix**: Structured concurrency with proper cancellation
- **Design**: 
  - `TaskCancellable` protocol
  - Parent Task scope with cancellation propagation
  - `withTaskCancellationHandler` for cleanup

**Acceptance Criteria**:
- [ ] Transcription runs in child Task (non-blocking)
- [ ] vDSP used for audio DSP (not scalar loops)
- [ ] Lock contention minimized (process outside locks)
- [ ] All Tasks have proper cancellation handling
- [ ] Latency budget: <500ms for transcription
- [ ] Example: `Task { await transcriptionService.transcribe(buffer) }` with guard

**Formal Properties**:
- LIVENESS: VAD loop never blocked by transcription
- LIVENESS: All tasks cancellable within 500ms
- SAFETY: No dangling tasks after engine stop
- PERF: Audio DSP uses vDSP (not scalar)

---

## Wave 4: Design Validation

### TASK-012: Create Design Review Checklist
**Complexity**: S  
**Dependencies**: [TASK-001 through TASK-011]  
**Wave**: 4  
**Files**: Design output (no code changes)

**Description**:  
Create comprehensive checklist for design review:

**Architecture Review:**
- [ ] All layers have clear responsibilities
- [ ] Dependencies flow inward only
- [ ] No circular dependencies
- [ ] Domain layer has zero external dependencies
- [ ] All public APIs are protocol-based

**Swift 6.2 Review:**
- [ ] All async operations properly handle errors
- [ ] Sendable conformance verified
- [ ] Actor isolation correct
- [ ] No blocking operations on MainActor

**Protocol Design Review:**
- [ ] Protocols are focused and cohesive
- [ ] Method signatures are complete with types
- [ ] Error handling is comprehensive
- [ ] Protocols support testing with mocks

**Code Quality Metrics (AST-Based Hotpoint Detection):**

The following SQL queries validate code quality via AST graph analysis. Run these against the codebase to identify architectural hotpoints:

*High Fan-Out (God Functions Detection):*
```sql
-- Finds functions calling >8 other functions (indicates SRP violation)
SELECT s.name, s.file, s.line, COUNT(e.id) as calls_out
FROM symbols s
JOIN edges e ON e.source_id = s.id AND e.kind = 'calls'
WHERE s.file IN ({changed_files})
GROUP BY s.id
HAVING calls_out > 8
ORDER BY calls_out DESC
```
- [ ] **Target**: Zero functions with >8 calls after migration
- [ ] **Current concern**: NotesView (3.7K lines) likely has god functions
- [ ] **Action**: Split into focused use cases during TASK-008

*Blast Radius Analysis (Coupling Detection):*
```sql
-- Finds symbols with >10 dependents (high coupling risk)
SELECT s.name, s.file, s.line, COUNT(e.id) as dependents
FROM symbols s
JOIN edges e ON e.target_id = s.id
WHERE s.file IN ({changed_files})
GROUP BY s.id
HAVING dependents > 10
ORDER BY dependents DESC
```
- [ ] **Target**: Zero symbols with >10 dependents after migration
- [ ] **Current concern**: SessionRepository (2.1K lines) likely high blast radius
- [ ] **Action**: Use protocols to reduce coupling during TASK-007

*Critical Blast Radius (Blockers):*
```sql
-- Finds symbols with >25 dependents (critical coupling)
SELECT s.name, s.file, s.line, COUNT(e.id) as dependents
FROM symbols s
JOIN edges e ON e.target_id = s.id
WHERE s.file IN ({changed_files})
GROUP BY s.id
HAVING dependents > 25
```
- [ ] **Target**: Zero symbols with >25 dependents
- [ ] **Action**: Immediate protocol extraction required

*Circular Dependency Detection:*
```sql
-- Finds import cycles A→B→A (violates Clean Architecture)
SELECT DISTINCT s1.file as file_a, s2.file as file_b
FROM edges e1
JOIN symbols s1 ON e1.source_id = s1.id
JOIN symbols s2 ON e1.target_id = s2.id
JOIN edges e2 ON e2.source_id = s2.id AND e2.target_id = s1.id
WHERE e1.kind = 'imports' AND e2.kind = 'imports'
  AND s1.file IN ({changed_files})
```
- [ ] **Target**: Zero circular dependencies in protocol graph
- [ ] **Validation**: Run before and after TASK-007 (DI Strategy)

*Large Class Detection (SRP Violations):*
```sql
-- Finds classes with >15 methods (god classes)
SELECT c.name, c.file, COUNT(*) AS method_count
FROM symbols c
JOIN symbols m ON m.file = c.file AND m.kind = 'function' 
  AND m.line > c.line AND m.line <= COALESCE(c.end_line, 99999)
WHERE c.kind = 'class'
  AND c.file IN ({changed_files})
GROUP BY c.name, c.file
HAVING COUNT(*) > 15
```
- [ ] **Target**: All classes have <15 methods after migration
- [ ] **Current concern**: NotesView, SessionRepository are god classes
- [ ] **Action**: Decompose during TASK-008 (Migration Strategy)

*Orphan Symbol Detection (Dead Code):*
```sql
-- Finds functions with zero callers (potential dead code)
SELECT s.name, s.file, s.line, s.kind
FROM symbols s
LEFT JOIN edges e ON e.target_id = s.id AND e.kind = 'calls'
WHERE s.file IN ({changed_files})
  AND s.kind IN ('function', 'method')
  AND s.name NOT LIKE '\_%' ESCAPE '\'
  AND s.name NOT IN ('main', 'setup', 'teardown')
  AND e.id IS NULL
```
- [ ] **Target**: Document or remove all orphan symbols during cleanup
- [ ] **Action**: Run during TASK-011 (Cleanup Phase)

**Tool Strategy: EEDOM (Primary) + OpenGrep (Quick)**

**Primary: EEDOM** (has OpenGrep built-in)
- Full AST graph analysis with SQL queries
- Integrated OpenGrep for pattern matching
- Best for comprehensive metrics and migration tracking

**Quick: Standalone OpenGrep** (open-source fork of Semgrep)
- Fast pattern-based validation without database setup
- Best for quick checks, CI/CD blocking, pre-commit hooks
- Install: `brew install opengrep`

*OpenGrep Rules (YAML-based):*
```yaml
# .opengrep/layer-violation.yaml
rules:
  - id: domain-imports-infrastructure
    pattern: |
      import MLX
      import WhisperKit
    languages: [swift]
    message: "Layer Violation: Domain must not import infrastructure"
    severity: ERROR
    paths:
      include: ["**/Domain/**/*.swift"]
```

*Running OpenGrep (Quick Validation):*
```bash
# Quick local check
opengrep scan --config .opengrep/layer-violation.yaml OpenOats/Sources/

# CI/CD with SARIF output
opengrep scan --config .opengrep/ --sarif-output=results.sarif
```

*Comparison:*
| Metric | EEDOM (Primary) | OpenGrep Standalone (Quick) |
|--------|-----------------|------------------------------|
| **Blast Radius** | ✅ Exact SQL count | ❌ Not available |
| **Circular Deps** | ✅ Symbol-level SQL | ⚠️ File-level patterns |
| **Layer Violations** | ✅ SQL + OpenGrep | ✅ OpenGrep only |
| **God Functions** | ✅ Exact call graph | ⚠️ Pattern approximation |
| **Setup** | Database required | Single binary |
| **Speed** | Slower (full analysis) | Fast (patterns only) |

**Recommendation**: 
- **Day-to-day**: Use standalone OpenGrep for quick validation
- **Deep analysis**: Use eedom SQL queries for metrics and trends
- **CI/CD**: Use either (eedom integrated or standalone OpenGrep)

**Acceptance Criteria**:
- [ ] Checklist covers all 8 design deliverables
- [ ] Each item is verifiable (yes/no or measurable)
- [ ] Review process defined (who reviews, how to sign off)
- [ ] Templates for review comments provided
- [ ] **AST Hotpoint Queries**: All 6 SQL validation queries are documented with:
  - [ ] Target thresholds (e.g., "Zero functions with >8 calls")
  - [ ] Current baseline measurements (run before migration)
  - [ ] Post-migration success criteria
  - [ ] Integration plan for CI/CD (run on PRs)

**Metrics Baseline (Pre-Migration):**
Document current hotpoint counts by running queries on existing codebase:
- [ ] High fan-out functions (>8 calls): ___ found (SQL) / ___ found (OpenGrep)
- [ ] High blast radius symbols (>10 dependents): ___ found (SQL only)
- [ ] Critical blast radius (>25 dependents): ___ found (SQL only)
- [ ] Circular dependencies: ___ found (SQL) / ___ found (OpenGrep)
- [ ] Large classes (>15 methods): ___ found (SQL) / ___ found (OpenGrep)
- [ ] Orphan symbols (dead code): ___ found (SQL only)

**OpenGrep Configuration:**
- [ ] OpenGrep installed locally (`brew install opengrep`)
- [ ] `.opengrep/` directory created with rule files
- [ ] Layer violation rules configured (Domain → Infrastructure)
- [ ] Force unwrap detection rules active (ERROR severity)
- [ ] CI/CD pipeline configured to run OpenGrep on PRs
- [ ] Pre-commit hooks configured (optional but recommended)

**Success Criteria (Post-Migration):**
- [ ] High fan-out: Zero functions with >8 calls (use cases are focused)
- [ ] Blast radius: Zero symbols with >10 dependents (protocols reduce coupling)
- [ ] Critical blast radius: Zero symbols with >25 dependents
- [ ] Circular dependencies: Zero cycles in protocol graph
- [ ] Large classes: All classes have <15 methods (SRP compliance)
- [ ] Orphan symbols: All documented or removed

**Formal Properties**:
- INVARIANT: Design review checklist is complete before implementation begins
- SAFETY: AST hotpoint detection prevents architectural regression
- LIVENESS: All quality metrics show improvement from baseline to target

---

### TASK-013: Define Acceptance Criteria for Design Quality
**Complexity**: S  
**Dependencies**: [TASK-012]  
**Wave**: 4  
**Files**: Design output (no code changes)

**Description**:  
Define measurable criteria for design validation:

**Completeness Metrics:**
- 100% of domain entities defined
- 100% of layer protocols defined
- 100% of use cases identified
- All data flows diagrammed

**Quality Metrics:**
- Zero circular dependencies in protocol graph
- All protocols have < 10 methods (Single Responsibility)
- All domain types are Sendable-safe
- All async operations have error handling

**AST-Based Code Quality Metrics (from TASK-012):**
Quantitative validation via AST graph analysis:
- **High Fan-Out**: Zero functions with >8 calls (use case focus)
- **Blast Radius**: Zero symbols with >10 dependents (low coupling)
- **Critical Blast Radius**: Zero symbols with >25 dependents (no blockers)
- **Circular Dependencies**: Zero import cycles (acyclic protocol graph)
- **Large Classes**: All classes have <15 methods (SRP compliance)
- **Orphan Symbols**: All dead code documented or removed

**Measurement Method:**
Run SQL queries from TASK-012 against indexed codebase:
```bash
# Example: Check for high fan-out functions
sqlite3 .eedom/code_graph.sqlite "SELECT s.name, s.file, COUNT(e.id) as calls 
FROM symbols s JOIN edges e ON e.source_id = s.id AND e.kind = 'calls' 
GROUP BY s.id HAVING calls > 8;"
```

**Documentation Metrics:**
- All protocols have documentation comments
- All complex flows have sequence diagrams
- Migration strategy has risk mitigations for each phase

**Acceptance Criteria**:
- [ ] Metrics are measurable (yes/no or numeric)
- [ ] Pass/fail criteria defined for each metric
- [ ] Review process defined for evaluating metrics
- [ ] Sign-off authority identified
- [ ] **AST Metrics Validation**:
  - [ ] SQL queries from TASK-012 are executable against codebase
  - [ ] Baseline measurements documented (pre-migration hotpoint counts)
  - [ ] Target thresholds defined (post-migration success criteria)
  - [ ] CI/CD integration plan for automated AST validation
  - [ ] Regression detection: Queries will fail build if hotpoints exceed thresholds

**Formal Properties**:
- INVARIANT: All acceptance criteria must pass before implementation begins
- SAFETY: AST-based metrics provide objective quality gates
- LIVENESS: Metrics demonstrate measurable improvement from baseline

---

### TASK-014: Create Design Validation Test Plan
**Complexity**: S  
**Dependencies**: [TASK-012, TASK-013]  
**Wave**: 4  
**Files**: Design output (no code changes)

**Description**:  
Create test plan for validating the design:

**Protocol Validation:**
- Compile-time verification of protocol conformance
- Mock implementations for testing protocol design
- Test that protocols support dependency injection

**Architecture Validation:**
- Static analysis for dependency direction
- Verify no layer violations
- Check for Sendable conformance

**Review Process:**
- Design walkthrough with stakeholders
- Architecture review session
- Sign-off from Lead Developer and Product Owner

**Acceptance Criteria**:
- [ ] Test plan covers all design deliverables
- [ ] Validation methods defined (review, static analysis, prototype)
- [ ] Success criteria for each test
- [ ] Schedule for validation activities
- [ ] Responsibility assignment for each test

**Formal Properties**:
- LIVENESS: Design validation completes before implementation phase
- SAFETY: Design flaws caught in validation, not implementation

---

## Design Deliverables Summary

| Deliverable | Task | Status |
|-------------|------|--------|
| Domain Entities (Meeting, Session, Transcript, Utterance) | TASK-001 | Wave 1 |
| Domain Error Types | TASK-002 | Wave 1 |
| Core Type Aliases | TASK-003 | Wave 1 |
| Presentation Layer Protocols | TASK-004 | Wave 2 |
| Business Logic (Use Cases) | TASK-005 | Wave 2 |
| Infrastructure Layer Protocols | TASK-006 | Wave 2 |
| Dependency Injection Strategy | TASK-007 | Wave 2 |
| Migration Strategy | TASK-008 | Wave 3 |
| Data Flow Diagrams | TASK-009 | Wave 3 |
| Transcription Backend Abstraction | TASK-010 | Wave 3 |
| Swift 6.2 Concurrency Strategy | TASK-011 | Wave 3 |
| **Critical Data Race Fixes** | **TASK-015** | **Wave 3** |
| **Memory Management & OOM Prevention** | **TASK-016** | **Wave 3** |
| **Complexity Hotspot Reduction** | **TASK-017** | **Wave 3** |
| **Performance & Latency Fixes** | **TASK-018** | **Wave 3** |
| Design Review Checklist | TASK-012 | Wave 4 |
| Acceptance Criteria | TASK-013 | Wave 4 |
| Design Validation Test Plan | TASK-014 | Wave 4 |

---

## Dependency Graph

```
Wave 1:
  TASK-001 → TASK-002 → TASK-003

Wave 2:
  TASK-001 → TASK-004 → TASK-005
  TASK-001 → TASK-006 → TASK-007
  TASK-002 → TASK-004, TASK-005, TASK-006
  TASK-004 → TASK-005

Wave 3:
  TASK-001, TASK-004, TASK-005, TASK-006, TASK-007 → TASK-008
  TASK-004, TASK-005, TASK-006 → TASK-009
  TASK-006 → TASK-010
  TASK-001, TASK-006 → TASK-011
  TASK-011 → TASK-015
  TASK-006 → TASK-016
  TASK-008 → TASK-017
  TASK-015, TASK-016 → TASK-018

Wave 4:
  All previous → TASK-012
  TASK-012 → TASK-013
  TASK-012, TASK-013 → TASK-014
```

---

## Risk Mitigation in Design

| Risk | Task | Mitigation |
|------|------|------------|
| Migration complexity | TASK-008 | Phased migration with rollback plans |
| Performance overhead | TASK-011 | Actor-based design minimizes contention |
| Swift 6.2 concurrency | TASK-011 | Sendable-safe design from start |
| Backend abstraction | TASK-010 | Adapter pattern for framework isolation |
| Large file extraction | TASK-008 | Incremental extraction strategy |
| **Data races (CRITICAL)** | **TASK-015** | **Convert to actors, remove @unchecked Sendable** |
| **OOM crashes (CRITICAL)** | **TASK-016** | **Streaming processing, bounded buffers** |
| **Complexity hotspots** | **TASK-017** | **Command pattern, function extraction** |
| **Latency spikes** | **TASK-018** | **Non-blocking transcription, vDSP** |

---

## Design Phase Exit Criteria

Before entering implementation phase, the following must be true:

1. ✅ All 18 design tasks completed and reviewed (14 original + 4 critical fixes)
2. ✅ All domain entities defined with Sendable conformance
3. ✅ All layer protocols complete with method signatures
4. ✅ Data flow diagrams created for all major flows
5. ✅ Migration strategy approved by stakeholders
6. ✅ Design review checklist completed
7. ✅ Acceptance criteria met (100% domain coverage, zero circular deps)
8. ✅ Design validation test plan executed successfully
9. ✅ **Critical issues addressed (from .temp/ analysis):**
   - ✅ Data race fixes designed (TASK-015)
   - ✅ Memory management fixed (TASK-016)
   - ✅ Complexity hotspots reduced (TASK-017)
   - ✅ Performance issues resolved (TASK-018)
10. ✅ Sign-off from Lead Developer and Product Owner

---

**Next Step After Design**: Implementation phase with wfc-implement using this design blueprint.

## Research Findings (wfc-deepen)
<!-- Generated: 2026-05-01T20:36:12Z -->
<!-- Do not edit this section manually; rerun wfc-deepen to refresh it -->
<!-- Begin wfc-deepen generated section -->

### Local Analysis Substrate
- **Source**: `run_analysis_substrate(...)` over `/Users/samfakhreddine/repos/OpenOats` (focus: `general`)
- **Adapters**: ast-grep=unavailable, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, python-ast=ok, semgrep=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok, tree-sitter=ok
- **Violation**: `python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected` at `/Users/samfakhreddine/repos/OpenOats/OpenOats/.build/checkouts/FluidAudio/Scripts/nemo_ami_benchmark/nemo_ami_benchmark.py:49` via `semgrep` — Detected a dynamic value being used with urllib. urllib supports 'file://' schemes, so a dynamic value controlled by a malicious actor may allow them to read arbitrary files. Audit uses of urllib calls to ensure user data cannot control the URLs, or consider using the 'requests' library instead.
- **Violation**: `python.lang.security.audit.subprocess-shell-true.subprocess-shell-true` at `/Users/samfakhreddine/repos/OpenOats/OpenOats/.build/checkouts/mlx-swift/Source/Cmlx/mlx/python/mlx/_distributed_utils/launch.py:59` via `semgrep` — Found 'subprocess' function 'Popen' with 'shell=True'. This is dangerous because this call will spawn the command using a shell process. Doing so propagates current shell settings and variables, which makes it much easier for a malicious actor to execute commands. Use 'shell=False' instead.
- **Violation**: `python.lang.security.audit.subprocess-shell-true.subprocess-shell-true` at `/Users/samfakhreddine/repos/OpenOats/OpenOats/.build/checkouts/mlx-swift/Source/Cmlx/mlx/python/mlx/_distributed_utils/launch.py:98` via `semgrep` — Found 'subprocess' function 'run' with 'shell=True'. This is dangerous because this call will spawn the command using a shell process. Doing so propagates current shell settings and variables, which makes it much easier for a malicious actor to execute commands. Use 'shell=False' instead.
- **Drift**: main has elevated complexity (19) (severity: `warning`; files: `/Users/samfakhreddine/repos/OpenOats/.claude/skills/swift-architecture/tooling/scripts/run/benchmarks.py`)
- **Drift**: parse_selection_matrix_slugs has elevated complexity (10) (severity: `warning`; files: `/Users/samfakhreddine/repos/OpenOats/.claude/skills/swift-architecture/tooling/scripts/validate/architecture.py`)
- **Drift**: parse_readme_supported_slugs has elevated complexity (11) (severity: `warning`; files: `/Users/samfakhreddine/repos/OpenOats/.claude/skills/swift-architecture/tooling/scripts/validate/architecture.py`)

<!-- End wfc-deepen generated section -->
