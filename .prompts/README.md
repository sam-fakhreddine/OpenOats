# OpenOats Prompt Templates

**Version**: 2.0.0  
**Pattern**: Structured JSON I/O with isolated agent phases

This directory contains **production-grade prompt templates** following the [30 Subagent Prompt Best Practices](https://github.blog/developer-skills/ai/prompt-engineering/).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR (You)                      │
│  1. Constructs JSON input with correlation_id              │
│  2. Dispatches to RED → GREEN → REFACTOR agents          │
│  3. Parses JSON output for next phase                     │
└─────────────────────────────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│  RED AGENT   │   │ GREEN AGENT  │   │REFACTOR AGENT│
│              │   │              │   │              │
│ Input: JSON  │   │ Input: JSON  │   │ Input: JSON  │
│ Output: JSON │   │ Output: JSON │   │ Output: JSON │
│ Schema: v1.0 │   │ Schema: v1.0 │   │ Schema: v1.0 │
└──────────────┘   └──────────────┘   └──────────────┘
```

## Templates (Version 2.0.0)

| Template | Purpose | I/O Schema | Worktree |
|----------|---------|------------|----------|
| `swift-tdd-red.md` | Write failing test | JSON | `.worktrees/task-XXX-red/` |
| `swift-tdd-green.md` | Minimal implementation | JSON | `.worktrees/task-XXX-green/` |
| `swift-tdd-refactor.md` | Optimize & review | JSON | `.worktrees/task-XXX-refactor/` |

**Legacy Templates** (Version 1.x - deprecated):
- `swift-tdd-workflow.md` - Old flat format
- `swift-implementation.md` - Old flat format

## Quick Start: Dispatch a TDD Task

### Phase 1: RED Agent

```json
{
  "tool": "Task",
  "prompt": {
    "subagent_type": "general",
    "prompt": "Read .prompts/swift-tdd-red.md then execute with input:\n\n```json\n{\n  \"correlation_id\": \"task-015-run-001\",\n  \"prompt_version\": \"1.0.0\",\n  \"task\": {\n    \"id\": \"TASK-015\",\n    \"description\": \"vDSP deinterleave optimization\",\n    \"test_file_path\": \"Tests/OpenOatsTests/Infrastructure/Services/MLX/AudioProcessorTests.swift\"\n  },\n  \"worktree_path\": \".worktrees/task-015-red/OpenOats/\",\n  \"target_file\": \"Sources/OpenOats/Infrastructure/Services/MLX/MLXAudioProcessor.swift\"\n}\n```"
  }
}
```

**Expected Output**:
```json
{
  "status": "ok",
  "correlation_id": "task-015-run-001",
  "phase": "RED",
  "task_id": "TASK-015",
  "verification": {
    "build_succeeded": true,
    "test_failed_as_expected": true
  },
  "next_phase": "GREEN"
}
```

### Phase 2: GREEN Agent

```json
{
  "tool": "Task",
  "prompt": {
    "subagent_type": "general",
    "prompt": "Read .prompts/swift-tdd-green.md then execute with input:\n\n```json\n{\n  \"correlation_id\": \"task-015-run-001\",\n  \"prompt_version\": \"1.0.0\",\n  \"task\": {\n    \"id\": \"TASK-015\",\n    \"description\": \"vDSP deinterleave optimization\"\n  },\n  \"worktree_path\": \".worktrees/task-015-green/OpenOats/\",\n  \"input_artifacts\": {\n    \"red_test_file\": \"Tests/OpenOatsTests/Infrastructure/Services/MLX/AudioProcessorTests.swift\",\n    \"red_worktree\": \".worktrees/task-015-red/OpenOats/\"\n  },\n  \"target_file\": \"Sources/OpenOats/Infrastructure/Services/MLX/MLXAudioProcessor.swift\"\n}\n```"
  }
}
```

**Expected Output**:
```json
{
  "status": "ok",
  "correlation_id": "task-015-run-001",
  "phase": "GREEN",
  "task_id": "TASK-015",
  "verification": {
    "build_succeeded": true,
    "test_passed": true
  },
  "technical_debt": ["Scalar loop O(n) instead of vDSP"],
  "next_phase": "REFACTOR"
}
```

### Phase 3: REFACTOR Agent

```json
{
  "tool": "Task",
  "prompt": {
    "subagent_type": "general",
    "prompt": "Read .prompts/swift-tdd-refactor.md then execute with input:\n\n```json\n{\n  \"correlation_id\": \"task-015-run-001\",\n  \"prompt_version\": \"1.0.0\",\n  \"task\": {\n    \"id\": \"TASK-015\",\n    \"description\": \"Optimize audio deinterleave with vDSP\"\n  },\n  \"worktree_path\": \".worktrees/task-015-refactor/OpenOats/\",\n  \"input_artifacts\": {\n    \"red_test_file\": \"Tests/OpenOatsTests/Infrastructure/Services/MLX/AudioProcessorTests.swift\",\n    \"green_implementation_file\": \"Sources/OpenOats/Infrastructure/Services/MLX/MLXAudioProcessor.swift\",\n    \"red_worktree\": \".worktrees/task-015-red/OpenOats/\",\n    \"green_worktree\": \".worktrees/task-015-green/OpenOats/\"\n  },\n  \"target_file\": \"Sources/OpenOats/Infrastructure/Services/MLX/MLXAudioProcessor.swift\",\n  \"performance_targets\": {\n    \"audio_latency_ms\": 20,\n    \"speedup_factor\": \"2-4x\"\n  }\n}\n```"
  }
}
```

**Expected Output**:
```json
{
  "status": "ok",
  "correlation_id": "task-015-run-001",
  "phase": "REFACTOR",
  "task_id": "TASK-015",
  "verification": {
    "build_succeeded": true,
    "swift6_errors": 0,
    "tests_passed": true
  },
  "performance": {
    "latency_ms": 12,
    "speedup_factor": "3.5x",
    "meets_target": true
  },
  "ready_for_merge": true
}
```

### Integration

After REFACTOR returns `ready_for_merge: true`:

```bash
# From feat!/3tier-clean-architecture branch
git merge task-015-refactor
swift test --filter TASK-015

# Clean up worktrees (CRITICAL - 2.5GB each)
git worktree remove .worktrees/task-015-red --force
git worktree remove .worktrees/task-015-green --force
git worktree remove .worktrees/task-015-refactor --force
git branch -D task-015-red task-015-green task-015-refactor
```

## Input/Output Schemas

### RED Agent Schema

**Input**:
```json
{
  "correlation_id": "string (uuid)",
  "prompt_version": "string (semver)",
  "task": {
    "id": "string",
    "description": "string",
    "test_file_path": "string"
  },
  "worktree_path": "string",
  "target_file": "string"
}
```

**Output**:
```json
{
  "status": "ok | error",
  "correlation_id": "string",
  "phase": "RED",
  "task_id": "string",
  "verification": {
    "build_succeeded": "boolean",
    "test_failed_as_expected": "boolean",
    "test_output": "string"
  },
  "artifacts": {
    "test_file": "string",
    "test_code": "string"
  },
  "next_phase": "GREEN",
  "notes": "string"
}
```

### GREEN Agent Schema

**Input**:
```json
{
  "correlation_id": "string",
  "prompt_version": "string",
  "task": {
    "id": "string",
    "description": "string"
  },
  "worktree_path": "string",
  "input_artifacts": {
    "red_test_file": "string",
    "red_worktree": "string"
  },
  "target_file": "string"
}
```

**Output**:
```json
{
  "status": "ok | error",
  "correlation_id": "string",
  "phase": "GREEN",
  "task_id": "string",
  "verification": {
    "build_succeeded": "boolean",
    "test_passed": "boolean",
    "swift6_compliant": "boolean"
  },
  "artifacts": {
    "implementation_file": "string",
    "implementation_code": "string"
  },
  "technical_debt": ["string"],
  "next_phase": "REFACTOR"
}
```

### REFACTOR Agent Schema

**Input**:
```json
{
  "correlation_id": "string",
  "prompt_version": "string",
  "task": {
    "id": "string",
    "description": "string"
  },
  "worktree_path": "string",
  "input_artifacts": {
    "red_test_file": "string",
    "green_implementation_file": "string",
    "red_worktree": "string",
    "green_worktree": "string"
  },
  "target_file": "string",
  "performance_targets": {
    "audio_latency_ms": "number",
    "speedup_factor": "string"
  }
}
```

**Output**:
```json
{
  "status": "ok | error",
  "correlation_id": "string",
  "phase": "REFACTOR",
  "task_id": "string",
  "verification": {
    "build_succeeded": "boolean",
    "swift6_errors": "number",
    "tests_passed": "boolean"
  },
  "performance": {
    "latency_ms": "number",
    "speedup_factor": "string",
    "meets_target": "boolean"
  },
  "artifacts": {
    "refactored_file": "string",
    "implementation_code": "string"
  },
  "improvements": ["string"],
  "checklist": {
    "performance_optimized": "boolean",
    "swift6_compliant": "boolean",
    "security_dps8": "boolean",
    "property_tests": "boolean",
    "documentation": "boolean",
    "all_tests_pass": "boolean"
  },
  "ready_for_merge": "boolean",
  "next_action": "string"
}
```

## Design Principles

### 1. Structured I/O (JSON)

All agents receive and return JSON. No prose parsing required.

### 2. Correlation IDs

Every phase carries the same `correlation_id` for distributed tracing.

### 3. Idempotent Actions

Agents can be safely retried if they fail or timeout.

### 4. Explicit Boundaries

Each agent has clear "NEVER do" lists to prevent overreach.

### 5. Context Isolation

REFACTOR agent has **ZERO** knowledge of RED/GREEN reasoning.

### 6. Schema Validation

Agents validate input at start and return structured errors if invalid.

## Required Skills

Load before any implementation:

```bash
# RED agent
skill(name="swift-testing-pro")
skill(name="swift-concurrency-pro")

# GREEN agent
skill(name="swift-concurrency-pro")

# REFACTOR agent
skill(name="swift-concurrency-pro")
skill(name="swift-architecture-skill")
skill(name="swift-testing-pro")
```

## Resources

- **AGENTS.md**: Project coding standards (must read first)
- **swift-tdd-red.md**: RED agent template
- **swift-tdd-green.md**: GREEN agent template
- **swift-tdd-refactor.md**: REFACTOR agent template
- **.wfc/epics/**: Hierarchical epic workspace