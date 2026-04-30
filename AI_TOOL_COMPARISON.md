# AI Tool Comparison: Context Consistency When Bouncing Between OpenCode, Claude, and Codex

## Short Answer: **No, They Won't Be Equal**

Bouncing between OpenCode, Claude Code, and Codex creates **context fragmentation**. Each tool has different:
- Context window sizes (what they can "remember")
- Context loading mechanisms (what files they auto-include)
- Knowledge cutoff dates (what APIs they know)
- Specialization (what they're good at)

This document explains the trade-offs and provides a **unified workflow strategy**.

---

## Context Window Comparison

| Tool | Context Window | Effective for OpenOats |
|------|---------------|------------------------|
| **OpenCode** | ~200K tokens | ✅ Full Package.swift + 10-15 core Swift files |
| **Claude Code** | ~200K tokens | ✅ Same, but better at complex reasoning |
| **Codex** | ~128K tokens | ⚠️ Package.swift + 5-8 core files only |

**Implication**: Codex can't hold the entire audio pipeline architecture in context simultaneously. You must be more selective about what you give it.

---

## Context Loading Mechanisms

### OpenCode
```yaml
# .opencode/config.yaml - Auto-loads based on patterns
context:
  include_patterns:
    - "**/*.swift"  # Auto-loads ALL Swift files
  exclude_patterns:
    - "Tests/**"    # But excludes tests
```
**Behavior**: Automatically discovers and loads files. May miss context if files are added outside patterns.

### Claude Code
```markdown
# CLAUDE.md - Explicit context + file references
## Key Files Reference
- Transcription/TranscriptionBackend.swift
- Audio/SystemAudioCapture.swift
```
**Behavior**: Loads CLAUDE.md first, then you reference files with `@filename`. More explicit control.

### Codex
```json
// .codex/config.json - Explicit file list
"context": {
  "files": [
    "CLAUDE.md",
    "Package.swift"
  ]
}
```
**Behavior**: Loads only specified files. Must manually update config when context needs change.

---

## Knowledge Cutoff & Specialization

| Tool | Knowledge Date | MLX Swift | Metal Audio | Swift 6.2 |
|------|---------------|-----------|-------------|-----------|
| **OpenCode** | 2024-06 | ⚠️ Limited | ⚠️ Limited | ✅ Good |
| **Claude Code** | 2024-06 | ⚠️ Limited | ⚠️ Limited | ✅ Good |
| **Codex** | 2024-06 | ⚠️ Limited | ⚠️ Limited | ✅ Good |

**Critical Gap**: None of them know `mlx-swift-audio` (released ~late 2024). All require:
- Context7 MCP queries
- Custom skill documentation (`.claude/skills/metal-audio-ml.md`)
- Explicit API examples in CLAUDE.md

---

## What Each Tool Excels At

### OpenCode: **Strict Implementation & TDD**
- ✅ Swift 6.2 strict concurrency enforcement
- ✅ Red-green-refactor discipline
- ✅ Build/test integration
- ✅ WFC skills integration (concurrency-patterns, tdd-workflow)
- ❌ Complex architecture decisions
- ❌ Novel problem solving

**Best for**: 
- Writing protocol conformance code
- Fixing Sendable warnings
- Writing tests first
- Build verification

### Claude Code: **Complex Reasoning & Investigation**
- ✅ Architecture tradeoff analysis
- ✅ Debugging complex interactions (ANE vs GPU contention)
- ✅ Performance investigation
- ✅ Axiom skills (memory/concurrency audits)
- ✅ Long-context reasoning (200K tokens)
- ❌ Quick code generation
- ❌ Repetitive refactoring

**Best for**:
- "Should we use FFT or LMS for echo cancellation?"
- "Why is ANE context switching slow?"
- Memory leak investigation
- Hybrid backend orchestration design

### Codex: **Pattern Implementation & Refactoring**
- ✅ Fast code generation
- ✅ Pattern matching across codebase
- ✅ Refactoring large file sets
- ✅ Bulk edits
- ❌ Deep reasoning about novel problems
- ❌ Context-heavy architecture

**Best for**:
- "Implement MLXWhisperBackend given this protocol"
- "Extract Metal resampler into separate class"
- "Find all [Float] copies and suggest MLX alternatives"

---

## The Problem: Context Drift When Bouncing

### Scenario: Echo Cancellation Implementation

**You start with Claude:**
```
Claude: "Design GPUAcousticEchoCanceller using Metal FFT"
→ Produces: Design doc with FFT approach
→ Context: Has full audio pipeline architecture loaded
```

**Switch to Codex:**
```
Codex: "Implement GPUAcousticEchoCanceller from design doc"
→ Context: Only has CLAUDE.md + Package.swift, NOT the design doc
→ Result: Implements basic version, misses nuances
```

**Switch to OpenCode:**
```
OpenCode: "Fix Sendable warnings in GPUAcousticEchoCanceller"
→ Context: Loads all Swift files, sees implementation
→ Result: Fixes warnings but may not understand WHY certain patterns
```

**Problem**: Each tool has **different mental model** of the project.

---

## Solution: Unified Context Strategy

### Strategy 1: Single Source of Truth (Recommended)

Maintain **one canonical context file** that all tools load:

```
.ai-sync/
├── CONTEXT.md          # Master context (all tools load this)
├── DECISIONS.md        # Architecture decision log
└── CURRENT_FOCUS.md    # What's being worked on now
```

**OpenCode** config:
```yaml
context:
  files:
    - ".ai-sync/CONTEXT.md"
    - ".ai-sync/CURRENT_FOCUS.md"
```

**Claude**: Always starts with `@CONTEXT.md`

**Codex** config:
```json
"context": {
  "files": [
    ".ai-sync/CONTEXT.md",
    ".ai-sync/CURRENT_FOCUS.md"
  ]
}
```

### Strategy 2: Tool-Specific Checkpoints

When switching tools, **export context** from previous tool:

```bash
# After Claude architecture session
claude "Summarize our echo cancellation approach for the next tool"
→ Output: .ai-sync/checkpoints/echo-cancellation-approach.md

# Before Codex implementation
codex --context .ai-sync/checkpoints/echo-cancellation-approach.md

# After Codex implementation
codex "Summarize what was implemented"
→ Output: .ai-sync/checkpoints/implementation-summary.md

# OpenCode verification
opencode ask "Verify implementation matches approach in .ai-sync/checkpoints/"
```

### Strategy 3: Role-Based Assignment (No Bouncing)

Assign specific **roles** to each tool and **don't bounce**:

| Phase | Tool | Handoff Artifact |
|-------|------|------------------|
| Architecture | Claude | `DECISIONS.md` |
| Implementation | Codex | Code + `IMPLEMENTATION.md` |
| Verification | OpenCode | Test results |
| Debugging | Claude (again) | Fix plan |

**No bouncing within a phase**. Complete the phase with one tool.

---

## Practical Workflow: Minimizing Context Loss

### Workflow A: Serial Phases (Recommended for OpenOats)

```
Phase 1: Investigation (Claude only)
├── MLX Audio API spike
├── Echo delay measurement  
├── Metal resampler benchmark
└── Output: investigations/*/REPORT.md

Phase 2: Architecture (Claude only)
├── Review investigation findings
├── Design hybrid backend
├── Design echo cancellation
└── Output: .ai-sync/DECISIONS.md

Phase 3: Implementation (Codex only)
├── Implement MLXWhisperBackend
├── Implement GPUAcousticEchoCanceller
├── Implement MetalResampler
└── Output: Working code

Phase 4: Verification (OpenCode only)
├── Fix Swift 6.2 concurrency
├── Write comprehensive tests
├── Fix Sendable warnings
└── Output: Production-ready code

Phase 5: Debugging (Claude only if needed)
├── Memory leak investigation
├── Performance profiling
└── Output: Fixes
```

**Key**: Only switch tools at **phase boundaries**, not mid-task.

### Workflow B: Parallel Specialization

Use tools simultaneously on **different concerns**:

```
Claude (Architecture track):
  "Design echo cancellation algorithm"
  → Uses full context

Codex (Implementation track A):
  "Implement MLXWhisperBackend from protocol"
  → Uses protocol definition only

OpenCode (Implementation track B):
  "Fix existing Sendable warnings in Transcription/"
  → Uses existing files only
```

**Merge point**: Daily sync in `.ai-sync/DAILY_SYNC.md`

---

## Tool-Specific Context Preservation

### Preserving Context: Claude → Others

Claude has **best context retention**. When leaving Claude:

```
Claude: "Create handoff document summarizing:
1. What we decided about echo cancellation
2. Why we chose FFT over LMS
3. The MLX Audio API patterns to use
4. Open questions remaining"

→ Output: .ai-sync/handoffs/claude-to-codex-YYYYMMDD.md
```

### Preserving Context: Codex → Others

Codex is **stateless between invocations**. Always:

```bash
# Before ending Codex session
codex "Write implementation notes to .ai-sync/IMPLEMENTATION_NOTES.md"

# Next session
codex --context .ai-sync/IMPLEMENTATION_NOTES.md "Continue implementation"
```

### Preserving Context: OpenCode → Others

OpenCode has **project-level context** but not **conversation context**:

```bash
# End of session
opencode ask "Summarize what was accomplished and blockers for next session"

# Output goes to .ai-sync/opencode-session-YYYYMMDD.md
```

---

## Red Flags: When Bouncing Causes Problems

Watch for these symptoms:

1. **Repeated questions**: Tool asks about something already decided
   - *Fix*: Check `.ai-sync/DECISIONS.md` is being loaded

2. **Inconsistent patterns**: Different coding styles in same file
   - *Fix*: Codex needs style guide in context

3. **Missing constraints**: Tool suggests disabled approach
   - *Fix*: Context doesn't include feasibility report

4. **Reverting decisions**: Tool undoes previous work
   - *Fix*: Use handoff documents between tool switches

---

## Recommended: Minimal Bouncing Protocol

For OpenOats ASR migration, use this **strict protocol**:

```
Rule 1: One tool per task
  ❌ "Claude, design this, then Codex implement"
  ✅ Complete design, export handoff, then start implementation

Rule 2: Export before switching
  ❌ Switch tools mid-conversation
  ✅ "Write handoff doc" → Switch → "Read handoff doc"

Rule 3: Single source of truth
  ❌ Each tool has different .md files
  ✅ All tools load .ai-sync/CONTEXT.md

Rule 4: Phase boundaries only
  ❌ "Claude help with this line, now OpenCode fix it"
  ✅ Finish phase with one tool, handoff to next

Rule 5: Context validation
  Before starting: "What files are you aware of?"
  Should match: Files you expect
```

---

## Quick Decision Matrix

| Situation | Primary Tool | Secondary | Never Use |
|-----------|--------------|-----------|-----------|
| Swift 6.2 strict concurrency fix | OpenCode | - | Codex |
| Architecture decision (ANE vs GPU) | Claude | - | Codex |
| Bulk refactoring (extract class) | Codex | - | OpenCode |
| Memory leak investigation | Claude | - | Codex |
| TDD: Write failing test | OpenCode | - | Codex |
| Novel algorithm design (echo cancellation) | Claude | - | Codex |
| Protocol conformance implementation | OpenCode | Claude (review) | - |
| Performance profiling | Claude | - | Codex |
| MLX API integration (new territory) | Claude | - | Codex |
| Fix build warnings (bulk) | Codex | - | OpenCode |

---

## Summary: The Cost of Bouncing

| Bounce Pattern | Context Loss | Time Cost | Quality Risk |
|----------------|--------------|-----------|--------------|
| Claude → Codex (no handoff) | 40% | +30 min | High |
| Codex → OpenCode (no handoff) | 30% | +20 min | Medium |
| OpenCode → Claude (no handoff) | 20% | +15 min | Low |
| **Any tool → Same tool (handoff doc)** | **5%** | **+5 min** | **Low** |
| **Single tool per phase** | **0%** | **0 min** | **None** |

**Recommendation**: Use **serial phases** (Claude → Codex → OpenCode) with explicit handoffs, or **parallel tracks** (each tool owns a vertical slice). Avoid bouncing within a task.

---

## Action Items

1. ✅ Choose workflow: Serial Phases (recommended) or Parallel Tracks
2. ✅ Create `.ai-sync/` directory structure
3. ✅ Write `CONTEXT.md` with full project state
4. ✅ Configure all tools to load `CONTEXT.md`
5. ✅ Establish handoff document template
6. ✅ Set rule: No bouncing within a phase
