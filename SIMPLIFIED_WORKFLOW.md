# OpenOats ASR Migration: Simplified Workflow (OpenCode + Kimi K2.5 Turbo)

## The Realization

If **Kimi K2.5 Turbo via OpenCode** is successfully handling:
- ✅ Swift 6.2 strict concurrency
- ✅ Complex architecture decisions  
- ✅ MLX/Metal integration
- ✅ TDD workflow
- ✅ WFC skills integration

Then **simplify to primarily OpenCode**. Use Claude/Codex only for specific gaps.

---

## Simplified Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ PRIMARY: OpenCode + Kimi K2.5 Turbo                         │
│                                                              │
│ All phases: Investigation → Architecture → Implementation    │
│              → Verification → Debugging                      │
│                                                              │
│ Context: .ai-sync/CONTEXT.md (single source)                 │
└──────────────────────────┬──────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │  Claude  │    │  Codex   │    │  Axiom   │
    │ (escape  │    │ (escape  │    │ (skills  │
    │  hatch)  │    │  hatch)  │    │  only)   │
    └──────────┘    └──────────┘    └──────────┘
```

---

## When to Use Escape Hatches

### Use Claude Code When:
- **Stuck on complex reasoning** OpenCode can't resolve
- **Novel debugging** - strange ANE/GPU interaction
- **Performance profiling** - Instruments analysis
- **Axiom skills needed** - `/axiom:audit memory`

**Workflow**:
```bash
# Try OpenCode first
opencode ask "Why is ANE context switching causing 50ms latency?"
# If stuck after 2-3 attempts...

# Escalate to Claude
claude "@CONTEXT.md OpenCode couldn't resolve: ANE latency issue. Deep analysis needed."
# Get answer

# Return to OpenCode
opencode ask "Implement fix per Claude's analysis: [paste solution]"
```

### Use Codex When:
- **Bulk refactoring** across 20+ files
- **Pattern extraction** - "find all X and convert to Y"
- **Large file generation** - complete implementation from scratch
- **Parallel work** - you want to work on 2 things simultaneously

**Workflow**:
```bash
# OpenCode doing main track
opencode ask "Implement MLXWhisperBackend"

# Simultaneously, Codex does refactoring
codex "Extract all Metal-related code into Audio/Metal/ directory"

# Merge results manually
```

---

## Simplified Context Strategy

### Single File: `.ai-sync/CONTEXT.md`

Keep it **lightweight** - OpenCode loads this automatically:

```markdown
# OpenOats ASR Migration

## Current State
- **Phase**: [Investigation/Architecture/Implementation/Verification]
- **Active**: [What you're working on now]
- **Blocker**: [None or description]

## Key Files
- TranscriptionBackend.swift - Protocol
- StreamingTranscriber.swift - Pipeline
- SystemAudioCapture.swift - [BUG: Echo here]
- AcousticEchoFilter.swift - [INSUFFICIENT]

## Decisions Made
1. [Decision] - [Rationale]

## Next Actions
1. [ ] [Next step]
```

### No More Handoff Documents (Usually)

Since OpenCode is primary, no need for complex handoffs. Just:

```bash
# Yesterday
opencode ask "Investigate MLX Audio API"
# → Updates CONTEXT.md with findings

# Today  
opencode ask "@CONTEXT.md Continue implementation based on yesterday's findings"
# → Reads CONTEXT.md, continues work
```

### Only Use Handoffs for Escape Hatches

```bash
# If you used Claude for complex analysis
claude "Write one-paragraph summary to .ai-sync/CLAUDE_INSIGHT.md"

# Then OpenCode reads it
opencode ask "@CONTEXT.md @CLAUDE_INSIGHT.md Implement the fix"
```

---

## OpenCode-First Workflow

### Phase 1: Investigation
```bash
opencode init

# Spike project
opencode ask "Create investigations/mlx-audio-spike/ testing MLX Swift Audio API"

# Run and document
opencode ask "Run spike, document findings in REPORT.md, update CONTEXT.md"

# Validate
opencode ask "Verify RTF < 0.3 and thread-safety"
```

### Phase 2: Architecture
```bash
# Design
opencode ask "Design MLXWhisperBackend conforming to TranscriptionBackend"

# Echo cancellation
opencode ask "Design GPUAcousticEchoCanceller with Metal FFT"

# Document
opencode ask "Write architecture decisions to .ai-sync/DECISIONS.md"
```

### Phase 3: Implementation
```bash
# Implement
opencode ask "Implement MLXWhisperBackend.swift per DECISIONS.md"
opencode ask "Implement GPUAcousticEchoCanceller.swift"
opencode ask "Implement MetalResampler.swift"

# Build
opencode build

# If stuck on complex issue (rare)
# → Escalate to Claude, get answer, return to OpenCode
```

### Phase 4: Verification
```bash
# Strict mode
opencode ask "Enable Swift 6.2 strict concurrency, fix all warnings"

# TDD
opencode ask "Write failing test for echo cancellation"
opencode ask "Implement to make test pass"

# Test
opencode test

# Audit (if needed)
claude /axiom:audit memory
# → Get results, return to OpenCode for fixes
```

---

## Configuration for OpenCode + Kimi

### `.opencode/config.yaml`

```yaml
project:
  name: "OpenOats ASR Migration"
  language: swift
  framework: swiftui

ai:
  provider: openai  # or your Kimi endpoint
  model: kimi-k2.5-turbo  # Explicitly specify
  temperature: 0.3
  max_tokens: 200000

context:
  max_files: 30  # Keep context focused
  include_patterns:
    - "**/*.swift"
    - ".ai-sync/CONTEXT.md"
    - ".ai-sync/DECISIONS.md"
  exclude_patterns:
    - "Tests/**"  # Load only when testing
    - "*.caf"
    - ".build/"

# WFC skills you already have loaded
skills:
  - concurrency-patterns
  - swiftui-debugging
  - tdd-workflow
  - logging-setup

commands:
  build: "swift build"
  test: "swift test"
  test-filter: "swift test --filter"
  lint: "swift-format lint --recursive Sources/"
  format: "swift-format format --recursive Sources/ -i"

# Safety
rules:
  - "Swift 6.2 strict concurrency: complete"
  - "Run swift test before git operations"
  - "Never commit audio files"
```

### `.ai-sync/CONTEXT.md` (Minimal)

```markdown
# OpenOats ASR Migration

## Now
Phase: [Current]
Working on: [Specific task]

## Key Context
- [Critical fact 1]
- [Critical fact 2]
- [Critical fact 3]

## Files
- TranscriptionBackend.swift
- StreamingTranscriber.swift
- [etc]

## Blockers
[None or list]

## Next
1. [ ] [Step 1]
2. [ ] [Step 2]
```

---

## Tool Selection (Simplified)

| Situation | Primary | Escalation |
|-----------|---------|------------|
| Normal work | **OpenCode** (Kimi) | None |
| Stuck on complex architecture | OpenCode → **Claude** → OpenCode | Rare |
| Strange ANE/GPU behavior | OpenCode → **Claude** → OpenCode | Rare |
| Memory leak investigation | OpenCode → **Claude + Axiom** → OpenCode | Rare |
| Bulk refactor (20+ files) | OpenCode + **Codex** (parallel) | Codex |
| Parallel workstreams | **OpenCode** + **Codex** | Both active |
| Axiom audit needed | OpenCode → **Claude /axiom:audit** → OpenCode | Claude only |

**Default**: OpenCode  
**Escape hatches**: Claude (complex), Codex (bulk/parallel)

---

## Daily Workflow (Realistic)

```bash
# Morning: Check context
cat .ai-sync/CONTEXT.md

# Work
opencode ask "Continue implementing [feature]"

# [Iterate normally]

# If stuck:
# Option A: Try different prompt to OpenCode
opencode ask "Approach differently: [alternative approach]"

# Option B: Escalate to Claude (if truly stuck)
claude "@CONTEXT.md OpenCode stuck on: [problem]. Alternative approaches?"
# [Get insight]
opencode ask "Implement solution: [Claude's suggestion]"

# End of day: Update context
opencode ask "Update CONTEXT.md with today's progress"
```

---

## Success Metrics (Simplified)

| Metric | Target | Measurement |
|--------|--------|-------------|
| OpenCode usage | >90% | Log tool usage |
| Escalations to Claude | <5% | Count per week |
| Escalations to Codex | <10% | Count per week |
| Context sync issues | 0 | Re-work due to context |
| Phase completion | On time | Days per phase |

If **escalations > 20%**, reconsider OpenCode-first approach.

---

## Anti-Patterns (Revised)

### ❌ Still Bad: Tool Hopping
```
You: "OpenCode, implement X"
[5 min later] You: "Actually Claude, what about..."
[5 min later] You: "Codex, try this instead"
```
**Result**: Chaos

### ✅ Good: OpenCode Default, Escalate Intentionally
```
You: "OpenCode, implement X"
[Stuck after 3 attempts]
You: "Claude, deep analysis on this specific blocker"
[Get answer]
You: "OpenCode, implement per analysis"
```
**Result**: Progress

---

## TL;DR

**If Kimi K2.5 Turbo in OpenCode is working well:**

1. **Use OpenCode for 90%+ of work**
2. **Simplify context** to just `.ai-sync/CONTEXT.md`
3. **Escalate to Claude only** for true stuck points or Axiom audits
4. **Use Codex only** for bulk refactoring or parallel tracks
5. **No complex handoffs** - just reference CONTEXT.md

**Result**: Single primary tool, simple workflow, escape hatches for specific gaps.

---

## Migration from Complex to Simple

If you already set up the complex workflow:

```bash
# Keep these (useful)
.ai-sync/CONTEXT.md              # ✓ Keep
PROJECT_PREP_PLAN.md             # ✓ Keep (reference)
SETUP_GUIDE.md                   # ✓ Keep (for tool setup)

# Deprecate these (too complex for your use case)
.ai-sync/HANDOFF_TEMPLATE.md     # ✗ Remove (not needed)
.ai-sync/RECOMMENDED_WORKFLOW.md # ✗ Remove (use this simplified version)
.ai-sync/checkpoints/            # ✗ Remove (OpenCode handles)
.ai-sync/handoffs/               # ✗ Remove (not needed)

# New minimal structure
.ai-sync/
├── CONTEXT.md          # Only file you need daily
└── DECISIONS.md        # Only when architecture phase
```

**Bottom line**: Trust what's working. If Kimi in OpenCode handles it, simplify everything else.
