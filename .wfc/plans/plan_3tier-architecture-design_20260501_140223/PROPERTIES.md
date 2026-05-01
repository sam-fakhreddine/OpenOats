# OpenOats 3-Tier Architecture Formal Properties

## Overview
This document defines the formal properties that must hold true for the OpenOats 3-tier architecture design. These properties serve as design constraints and validation criteria.

## Property Taxonomy

### SAFETY Properties (Bad things must never happen)

**SAFETY-001: No Circular Dependencies**  
**Type**: SAFETY  
**Priority**: CRITICAL  
**Statement**: The dependency graph between layers must be acyclic; dependencies may only flow inward from Presentation → Business → Domain ← Infrastructure.  
**Rationale**: Circular dependencies create tight coupling, make testing impossible, and prevent incremental migration.  
**Observable**: Static analysis of protocol imports and conformance.

**SAFETY-002: Domain Layer Isolation**  
**Type**: SAFETY  
**Priority**: CRITICAL  
**Statement**: Domain entities and value objects must have zero dependencies on external frameworks (SwiftUI, Combine, MLX, WhisperKit, etc.).  
**Rationale**: Domain layer must be pure business logic that can be tested in isolation and moved between platforms.  
**Observable**: Grep domain layer files for import statements; must only import Foundation.

**SAFETY-003: No UI Thread Blocking**  
**Type**: SAFETY  
**Priority**: CRITICAL  
**Statement**: No operation in the Presentation layer (ViewModels) may block the MainActor for more than 16ms (one frame at 60fps).  
**Rationale**: Blocking the UI thread causes jank and poor user experience, especially during transcription.  
**Observable**: Code review + runtime profiling of MainActor usage.

**SAFETY-004: Immutable Domain State**  
**Type**: SAFETY  
**Priority**: HIGH  
**Statement**: All domain entities must be immutable value types; mutation must produce new instances.  
**Rationale**: Immutability prevents race conditions and makes reasoning about state changes easier.  
**Observable**: Domain types are `struct` not `class`; no `var` properties on domain types.

**SAFETY-005: Exhaustive Error Handling**  
**Type**: SAFETY  
**Priority**: HIGH  
**Statement**: All async operations in Business and Infrastructure layers must have explicit error handling; no force unwraps or implicit optional unwrapping.  
**Rationale**: Transcription errors (network, audio, backend) must be handled gracefully without crashing.  
**Observable**: Compiler warnings enabled for exhaustive switch; code review for error propagation.

**SAFETY-006: Sendable-Safe Concurrency**  
**Type**: SAFETY  
**Priority**: HIGH  
**Statement**: All types crossing actor boundaries must be Sendable-safe; no data races possible under Swift 6.2 StrictConcurrency.  
**Rationale**: Swift 6.2 enforces strict concurrency; violations are compilation errors or runtime crashes.  
**Observable**: Compiler build with `-strict-concurrency=complete` produces zero errors/warnings.

**SAFETY-007: Backend Failure Isolation**  
**Type**: SAFETY  
**Priority**: HIGH  
**Statement**: Failure of one transcription backend must not affect other backends or crash the app.  
**Rationale**: Users may switch between MLX, WhisperKit, and cloud backends; failures must be isolated.  
**Observable**: Unit tests inject backend failures and verify graceful degradation.

---

### LIVENESS Properties (Good things must eventually happen)

**LIVENESS-001: UI Updates Delivered**  
**Type**: LIVENESS  
**Priority**: CRITICAL  
**Statement**: All state changes in ViewModels must eventually be delivered to the UI (SwiftUI views) within 100ms.  
**Rationale**: Real-time transcription requires UI to stay in sync with audio processing.  
**Observable**: UI tests verify transcript updates appear within timeout.

**LIVENESS-002: Transcription Progress**  
**Type**: LIVENESS  
**Priority**: CRITICAL  
**Statement**: If audio is being captured, transcription segments must be emitted at least every 5 seconds during active speech.  
**Rationale**: Users expect to see transcription appear continuously during meetings.  
**Observable**: Integration tests with sample audio verify segment emission timing.

**LIVENESS-003: Resource Cleanup**  
**Type**: LIVENESS  
**Priority**: HIGH  
**Statement**: All resources (audio buffers, file handles, network connections) must be released within 1 second of cancellation or completion.  
**Rationale**: Long-running transcription sessions must not leak memory or hold system resources.  
**Observable**: Memory profiling during long transcription sessions shows no growth.

**LIVENESS-004: Session Persistence**  
**Type**: LIVENESS  
**Priority**: HIGH  
**Statement**: Session data must be persisted to storage within 2 seconds of session completion.  
**Rationale**: Users must not lose transcription data if app crashes after stopping recording.  
**Observable**: Unit tests simulate crash and verify data recovery.

**LIVENESS-005: Cancellation Responsiveness**  
**Type**: LIVENESS  
**Priority**: MEDIUM  
**Statement**: Long-running operations (transcription, AI note generation) must respond to cancellation requests within 500ms.  
**Rationale**: Users expect immediate response when stopping recording or cancelling AI processing.  
**Observable**: Cancellation token propagation verified in code review; timing tests.

---

### INVARIANT Properties (Things that must always be true)

**INVARIANT-001: Unidirectional Data Flow**  
**Type**: INVARIANT  
**Priority**: CRITICAL  
**Statement**: Data must flow in one direction: Presentation → Business → Infrastructure (commands) and Infrastructure → Business → Presentation (events).  
**Rationale**: Bidirectional data flow creates spaghetti code and unpredictable state mutations.  
**Observable**: Architecture diagrams + code review verify no callbacks from lower to upper layers.

**INVARIANT-002: Protocol-Based APIs**  
**Type**: INVARIANT  
**Priority**: CRITICAL  
**Statement**: All public APIs between layers must be protocol-based; concrete types may only appear in DI container and tests.  
**Rationale**: Protocols enable testability, swapping implementations, and loose coupling.  
**Observable**: Protocol conformance checks; no concrete type parameters in layer boundaries.

**INVARIANT-003: Layer-Appropriate Concurrency**  
**Type**: INVARIANT  
**Priority**: HIGH  
**Statement**: Each layer has specific concurrency rules: Presentation = MainActor only, Business = Structured concurrency, Domain = Sendable-safe, Infrastructure = Background queues/actors.  
**Rationale**: Proper concurrency prevents races while maintaining UI responsiveness.  
**Observable**: `@MainActor`, `actor`, `Sendable` annotations in code review.

**INVARIANT-004: Complete Error Propagation**  
**Type**: INVARIANT  
**Priority**: HIGH  
**Statement**: Every error produced in Infrastructure must be mappable to a domain error and propagatable to Presentation for user notification.  
**Rationale**: Users must see helpful error messages, not crashes or silent failures.  
**Observable**: Error mapping functions in all infrastructure implementations.

**INVARIANT-005: Backend Configuration Isolation**  
**Type**: INVARIANT  
**Priority**: MEDIUM  
**Statement**: Configuration for one transcription backend must not affect other backends; backend-specific settings are isolated.  
**Rationale**: Users switching backends should not have to reconfigure unrelated settings.  
**Observable**: Configuration structs are backend-specific; no shared mutable state.

**INVARIANT-006: Domain Identifier Uniqueness**  
**Type**: INVARIANT  
**Priority**: MEDIUM  
**Statement**: All domain identifiers (MeetingID, SessionID, etc.) must be globally unique and immutable once assigned.  
**Rationale**: Identifiers are used for persistence and referencing; duplicates cause data corruption.  
**Observable**: ID generation uses UUID; no reassignment of ID properties.

**INVARIANT-007: Backward Compatibility During Migration**  
**Type**: INVARIANT  
**Priority**: HIGH  
**Statement**: During incremental migration from old to new architecture, existing user data and functionality must remain intact.  
**Rationale**: Users cannot tolerate data loss or broken features during refactor.  
**Observable**: Migration tests with legacy data; feature parity verification.

---

### PERFORMANCE Properties (Resource constraints)

**PERF-001: Audio Latency**  
**Type**: PERFORMANCE  
**Priority**: CRITICAL  
**Statement**: Audio capture to transcription segment latency must be < 500ms for real-time streaming.  
**Rationale**: Delays > 500ms are perceptible and degrade user experience in live transcription.  
**Observable**: Benchmark tests measure end-to-end latency.

**PERF-002: Memory Footprint**  
**Type**: PERFORMANCE  
**Priority**: HIGH  
**Statement**: App memory usage during transcription must not exceed 2GB on systems with 8GB+ RAM.  
**Rationale**: MLX models are memory-intensive; must not cause system swapping.  
**Observable**: Memory profiling during transcription of 1-hour meeting.

**PERF-003: Layer Overhead Budget**  
**Type**: PERFORMANCE  
**Priority**: MEDIUM  
**Statement**: Architecture layer abstraction overhead must not exceed 5% of total processing time.  
**Rationale**: Clean architecture should not significantly impact performance vs direct calls.  
**Observable**: Profiling comparison of layered vs direct architecture (in prototype).

**PERF-004: Storage Efficiency**  
**Type**: PERFORMANCE  
**Priority**: MEDIUM  
**Statement**: Session storage must use efficient encoding; 1 hour meeting transcript < 50MB storage.  
**Rationale**: Users may have hundreds of meetings; storage must scale reasonably.  
**Observable**: File size measurements of serialized sessions.

---

## Property Validation Matrix

| Property | Design Phase | Implementation Phase | Testing Phase |
|----------|--------------|------------------------|---------------|
| SAFETY-001 | ✅ Protocol graph analysis | ✅ Import checks | N/A |
| SAFETY-002 | ✅ Dependency review | ✅ Import audit | N/A |
| SAFETY-003 | ✅ Architecture design | ✅ Code review | ✅ UI profiling |
| SAFETY-004 | ✅ Type definitions | ✅ Code review | N/A |
| SAFETY-005 | ✅ Error protocol design | ✅ Compiler checks | ✅ Error injection tests |
| SAFETY-006 | ✅ Sendable annotations | ✅ Compiler strict mode | N/A |
| SAFETY-007 | ✅ Backend abstraction | ✅ Error handling | ✅ Chaos testing |
| LIVENESS-001 | ✅ ViewModel design | ✅ Observable patterns | ✅ UI tests |
| LIVENESS-002 | ✅ Streaming design | ✅ Segment buffering | ✅ Integration tests |
| LIVENESS-003 | ✅ Resource management | ✅ Cleanup code | ✅ Memory profiling |
| LIVENESS-004 | ✅ Persistence design | ✅ Save logic | ✅ Crash recovery tests |
| LIVENESS-005 | ✅ Cancellation design | ✅ Task cancellation | ✅ Cancellation tests |
| INVARIANT-001 | ✅ Data flow diagrams | ✅ Code review | N/A |
| INVARIANT-002 | ✅ Protocol definitions | ✅ API review | N/A |
| INVARIANT-003 | ✅ Concurrency design | ✅ Actor annotations | ✅ Thread sanitizers |
| INVARIANT-004 | ✅ Error mapping design | ✅ Mapping functions | ✅ Error propagation tests |
| INVARIANT-005 | ✅ Configuration design | ✅ Settings isolation | N/A |
| INVARIANT-006 | ✅ ID type design | ✅ ID generation | N/A |
| INVARIANT-007 | ✅ Migration plan | ✅ Feature flags | ✅ Regression tests |
| PERF-001 | ✅ Streaming architecture | ✅ Buffer sizing | ✅ Latency benchmarks |
| PERF-002 | ✅ Memory architecture | ✅ Model loading | ✅ Memory profiling |
| PERF-003 | ✅ Abstraction design | ✅ Hot path optimization | ✅ Profiling comparison |
| PERF-004 | ✅ Storage format | ✅ Compression | ✅ Storage benchmarks |

---

## Design Phase Property Verification

During the design phase, each property must be validated as follows:

### SAFETY Properties
- **Design Review**: Architecture diagrams and protocol definitions reviewed for violations
- **Static Analysis**: Dependency graphs checked for cycles
- **Protocol Audit**: Domain protocols checked for external framework imports

### LIVENESS Properties
- **Timing Design**: Expected timing budgets allocated in design
- **Flow Validation**: Sequence diagrams verify state propagation paths
- **Resource Design**: Cleanup patterns designed into protocols

### INVARIANT Properties
- **Architecture Review**: Unidirectional flow verified in data flow diagrams
- **Protocol Definition**: All public APIs defined as protocols
- **Concurrency Design**: Actor boundaries marked in design docs

### PERFORMANCE Properties
- **Budget Allocation**: Performance budgets assigned to each layer
- **Prototype Validation**: Critical paths validated with throwaway prototypes
- **Review Sign-off**: Performance team reviews design for feasibility

---

## Property Violation Severity

| Severity | Response | Example |
|----------|----------|---------|
| CRITICAL | Block implementation | Circular dependency, UI blocking |
| HIGH | Must fix before release | Domain layer framework dependency |
| MEDIUM | Fix in next iteration | Non-optimal error handling |
| LOW | Track and prioritize | Minor performance overhead |

---

## Sign-Off

Design phase properties validated by:

- [ ] Lead Developer: Architecture review completed
- [ ] Product Owner: Business invariants accepted
- [ ] Technical Reviewer: Performance budgets feasible

**Date**: _______________

**Status**: ⬜ PASS  ⬜ FAIL (with blocking issues)  ⬜ CONDITIONAL (with non-blocking issues)

---

*This document is the contract for the 3-tier architecture. Violations during implementation must be escalated to the design review board.*
