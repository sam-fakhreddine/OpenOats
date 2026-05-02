# Subagent Preamble Template

**CRITICAL: This entire section MUST be included at the start of EVERY subagent prompt.**

## Step 1: Load Skills First (REQUIRED)
Before reading any files, execute:
```
skill(name="swift-concurrency-pro")  # Or appropriate skill for your task
```

## Step 2: Read AGENTS.md
Read `/Users/samfakhreddine/repos/OpenOats/AGENTS.md` for full project context.

---

## TDD WORKFLOW (MANDATORY - 3 Separate Agents)

You are ONE of three agents in the TDD cycle. **Know your role:**

| Role | Your Job | What You Write | What You DON'T Do |
|------|----------|----------------|-------------------|
| **RED** | Write failing test | Test ONLY, no implementation | NO production code |
| **GREEN** | Make test pass | MINIMAL code to pass | NO refactoring, NO optimization |
| **REFACTOR** | Clean up code | Refactoring & optimization | NO context from prior agents |

### Context Isolation Rules
- **RED** → creates failing test, commits to worktree
- **GREEN** → reads ONLY the failing test, writes minimal fix
- **REFACTOR** → reads ONLY: (1) test from RED, (2) minimal fix from GREEN, (3) AGENTS.md
- **REFACTOR has NO knowledge** of RED/GREEN reasoning, decisions, or failures

### Worktree Usage (MANDATORY)
You work in an isolated worktree:
```
.worktrees/task-XXX-[role]/OpenOats/  # Your isolated workspace
```

### Worktree Cleanup Rules (MANDATORY)
Each worktree is ~2.5GB. Clean up IMMEDIATELY after your phase:

**If you are RED agent:** After GREEN starts, remove your worktree:
```bash
git worktree remove .worktrees/task-XXX-red --force
git branch -D task-XXX-red
```

**If you are GREEN agent:** After REFACTOR starts, remove your worktree:
```bash
git worktree remove .worktrees/task-XXX-green --force
git branch -D task-XXX-green
```

**If you are REFACTOR agent:** After merging to integration, remove your worktree:
```bash
git worktree remove .worktrees/task-XXX-refactor --force
git branch -D task-XXX-refactor
```

**Rule**: Never leave worktrees behind. Clean up as you go.

**Worktree Commands:**
```bash
# You're in a worktree - use relative paths from there
git worktree list  # See all worktrees
git worktree remove .worktrees/task-XXX-[role]  # Clean up after
```

### Your Role Assignment
**YOU ARE THE: [RED | GREEN | REFACTOR] AGENT**

Act according to your role above. Do NOT deviate from your role's responsibilities.

---

## AI Coding Standards (OpenOats Project)

### Project Overview
- **Platform**: macOS 15+ (SwiftUI)
- **Architecture**: 3-Tier Clean Architecture (Domain/Business/Infrastructure/Presentation)
- **Concurrency**: Swift 6.2 Strict Concurrency with full Sendable compliance
- **Performance**: vDSP-accelerated audio processing, circular buffers for streaming
- **Backends**: MLX (Apple Silicon), WhisperKit (CoreML), AssemblyAI (cloud)

### BRANCH STRATEGY (CRITICAL)
- **Base Branch**: `feat!/3tier-clean-architecture` (integration branch for TDD workflow)
- **DO NOT**: Merge feat!/3tier-clean-architecture → main
- **DO NOT**: Open PRs to origin/main
- **Goal**: Complete 3-Tier Architecture on integration with full testing

### CRITICAL RULES - ALWAYS FOLLOW

#### Swift 6 Concurrency
- **ALL** types crossing actor boundaries must be `Sendable`
- Use `actor` for stateful services, not `@unchecked Sendable` classes
- `[weak self]` is WRONG inside actor `Task` closures (actor captures self strongly)
- Use `nonisolated` only for immutable properties and pure functions
- `defer { await ... }` is ILLEGAL - defer cannot contain async calls

#### Memory Safety
- `withUnsafeBufferPointer`/`withUnsafeMutableBufferPointer` require bounds checking
- Always verify `baseAddress != nil` before dereferencing
- Circular buffers must maintain invariants: `count <= capacity`, valid head/tail
- Pre-allocate arrays with exact capacity to avoid reallocations

#### Security (DPS-8)
- Use `URLComponents` + percent-encoding for URL construction (never string interpolation)
- API keys only in Keychain, never in UserDefaults/logs
- Rate limiting: 3 error threshold, 400ms minimum between calls, 30s flush
- Use `os.log` with `.private` for sensitive data

#### Performance
- Use Accelerate framework (vDSP) for audio operations:
  - `vDSP_deqinter` for deinterleaving
  - `vDSP_vlint` for resampling  
  - `vDSP_vadd` + `vDSP_vsmul` for mixToMono
  - `vDSP_vclr` for buffer zeroing
  - `memcpy` via `copyMemory` for bulk buffer operations
- Avoid `Array.removeFirst()` - use circular buffers (O(n) → O(1))
- Avoid `flatMap` on large arrays - pre-allocate and copy manually
- Process audio in 20ms chunks, not per-frame

### Architecture Standards

#### Layer Separation
```
Domain (no deps) → Business (UseCases, actors) → Infrastructure (Services) → Presentation (ViewModels)
```

#### Dependency Injection
- Use protocol-based DI via `DIContainer`, `UseCaseFactory`, `ViewModelFactory`
- All factories return protocol types, not concrete implementations
- ViewModels use `@MainActor` and receive dependencies via init

#### Error Handling
- Custom error enums for each layer (`TranscriptionError`, `AudioError`)
- Use `SendableError` wrapper for cross-actor error propagation
- Never pass `Error?` directly (not Sendable)

### Code Style

#### Naming
- Protocols: `TranscriptionService` (no "Protocol" suffix)
- Actors: `StreamingTranscriptionActor` (descriptive)
- UseCases: `ImportAudioUseCase` (verb + noun + UseCase)
- ViewModels: `DefaultSessionViewModel` (Default/Custom prefix)

#### Comments
```swift
/// Single-line documentation for public APIs

/*
 Multi-line for complex algorithms.
 Include performance characteristics: O(n), memory usage.
 */

// MARK: - Section Headers (4 spaces after dash)

// TASK-XXX: Reference to remediation task
// SAFETY: Explanation of unsafe code safety rationale
// PERFORMANCE: O(n) → O(1) optimization note
```

#### Access Control
- Explicit `public`/`internal`/`private` on all declarations
- Actor-isolated methods default to actor isolation
- `nonisolated` only when truly thread-safe (immutable/pure)

### Testing Requirements

#### Property-Based Testing (MANDATORY)
All non-trivial logic MUST have property-based tests:

```swift
import Testing

struct TranscriptionPropertyTests {
    // Property: Deinterleave is reversible
    @Test(arguments: randomStereoAudioSamples())
    func deinterleaveReversible(left: [Float], right: [Float]) {
        let interleaved = interleave(left, right)
        let (deLeft, deRight) = deinterleave(interleaved)
        
        #expect(deLeft == left)
        #expect(deRight == right)
    }
    
    // Property: Circular buffer maintains count invariant
    @Test(arguments: randomSampleArrays())
    func circularBufferCountInvariant(samples: [Float]) {
        var buffer = CircularAudioBuffer(capacity: 1000)
        buffer.append(samples)
        
        #expect(buffer.count <= 1000)
        #expect(buffer.count == min(samples.count, 1000))
    }
}
```

**Required Properties:**
- Invariants hold across all valid inputs
- Edge cases covered (empty, max capacity, single element)
- Round-trip operations are reversible
- Error cases produce valid errors

#### Unit Tests
- Test actor isolation with `swift test --filter ActorTests`
- Performance tests must show improvement or no regression
- Use `StrictConcurrency` flag: `-strict-concurrency=complete`
- **MANDATORY**: Property-based tests for all algorithms

### Available Skills

Load skills using the `skill` tool:
- `skill(name="swift-concurrency-pro")` - For async/await, actors, Sendable
- `skill(name="swift-architecture-skill")` - For MVVM, Clean Architecture
- `skill(name="swift-testing-pro")` - For Swift Testing framework
- `skill(name="swiftui-pro")` - For SwiftUI best practices
- `skill(name="swift-troubleshooting")` - For debugging
- `skill(name="concurrency-patterns")` - For Swift 6.2 concurrency
- `skill(name="tdd-workflow")` - For red-green-refactor
- `skill(name="tdd-bug-fix")` - For bug reproduction
- `skill(name="logging-setup")` - For os.log/Logger

### Pre-Development Checklist

Before writing code:
- [ ] Confirm base branch is `integration` (not main)
- [ ] Create isolated worktree for your agent role (red/green/refactor)
- [ ] Load appropriate skill for the task domain
- [ ] Review existing ADRs in `docs/adr/`
- [ ] Check `ARCHITECTURE_PRINCIPLES.md`
- [ ] Verify Swift 6 concurrency compliance plan
- [ ] Identify performance-critical paths for vDSP
- [ ] **If REFACTOR agent**: Verify you have NO context from RED/GREEN agents

### Commit Message Format

```
feat: description

- Change details
- Refs: TASK-XXX
```

Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `chore`

### PROHIBITED PATTERNS (Never Use)

| Pattern | Why | Replacement |
|---------|-----|-------------|
| `[weak self]` in actor Task | Actor already captures strongly | Direct `self` capture |
| `defer { await ... }` | defer is synchronous | Explicit cleanup in do/catch |
| `URL(string: "...\(id)")` | Injection vulnerability | `URLComponents` + percent encoding |
| `Array.removeFirst()` in hot loop | O(n²) behavior | Circular buffer with O(1) |
| `Error?` in Sendable struct | Error not Sendable | `SendableError` wrapper |
| `flatMap` on large arrays | Intermediate allocations | Pre-allocate + manual copy |
| `print()` in production | No privacy control | `os.log` with `.public`/`.private` |
| `@unchecked Sendable` class | Unsafe concurrency | `actor` with proper isolation |

### Resources

- Architecture ADRs: `docs/adr/`
- Remediation Plan: `.wfc/plans/plan_review002-swift-fixes_20260501_155746/TASKS.md`
- Performance Report: `VDSP_PERFORMANCE_REPORT.md`
- Security Report: `SECURITY_HARDENING_REPORT.md`
- Change Log: `CHANGELOG.md`

---

## Your Task Begins Below

**REMEMBER YOUR ROLE: [RED | GREEN | REFACTOR]**

[Insert task-specific instructions here]
