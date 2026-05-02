# TDD Orchestration System

**Status**: ✅ MVP Complete

A production-grade TDD orchestration system with **one master prompt** and **composable components** that works with any AI coding tool.

## Quick Start

```bash
# Generate RED phase prompt for a task
python3 .prompts/orchestrator.py TASK-SW6-015 --red

# Generate all phases to files
python3 .prompts/orchestrator.py TASK-SW6-015 --all --output-format=files --output-dir=./generated

# Install MCP server for Claude Code/Cursor
./mcp-server/install.sh
```

## What We Built

### 1. Master Prompt (swift-tdd-master.md)

**One prompt to rule them all** - handles all three TDD phases:

- **RED**: Write failing tests
- **GREEN**: Minimal implementation  
- **REFACTOR**: Optimize and clean

Each phase is selected via the `phase` field in input JSON. Subagents have **zero context sharing** between phases.

### 2. Component System (Lego Pieces)

Composable fragments in `.prompts/components/`:

```
components/
├── skills/
│   ├── swift-testing.yaml       # Swift Testing skills
│   └── swift-concurrency.yaml   # Swift 6 concurrency
├── context/
│   ├── red-context.yaml         # RED phase instructions
│   ├── green-context.yaml       # GREEN phase instructions
│   └── refactor-context.yaml    # REFACTOR phase instructions
└── actions/
    └── write-tests.yaml         # Test writing steps
```

Each component is a **YAML file** with:
- `id`: Unique identifier
- `version`: Semver
- `applies_when`: Conditions for use
- Content specific to type

### 3. Orchestrator (orchestrator.py)

Tool-agnostic Python orchestrator:

```bash
# Generate prompt for copy-paste
python3 .prompts/orchestrator.py TASK-SW6-015 --red

# Generate JSON dispatch instructions
python3 .prompts/orchestrator.py TASK-SW6-015 --red --output-format=json

# Write to files
python3 .prompts/orchestrator.py TASK-SW6-015 --all --output-format=files
```

**Features**:
- Reads tasks from `.wfc/epics/*/TASKS.md`
- Derives file paths from task ID
- Creates isolated git worktrees
- Generates correlation IDs for tracing
- Tool-agnostic (works with Claude, Cursor, Copilot, etc.)

### 4. MCP Server (mcp-server/)

Full MCP (Model Context Protocol) server for native AI tool integration:

**Tools**:
- `generate_prompt` - Build phase-specific prompts
- `get_task_info` - Read task specifications
- `list_components` - Show available Lego pieces

**Resources**:
- `prompts://master` - The One Prompt
- `prompts://components/{type}/{id}` - Individual components
- `tasks://{epic}/{task_id}` - Task specs

**Prompts**:
- `tdd_red` - RED phase
- `tdd_green` - GREEN phase
- `tdd_refactor` - REFACTOR phase

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AI TOOL (Any)                           │
│              Claude / Cursor / Copilot                      │
└─────────────────────────────────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌──────────┐   ┌──────────┐   ┌──────────┐
       │   MCP    │   │   CLI    │   │  Copy    │
       │  Server  │   │   Tool   │   │  Paste   │
       └──────────┘   └──────────┘   └──────────┘
              │              │              │
              └──────────────┼──────────────┘
                             ▼
              ┌──────────────────────────┐
              │    ORCHESTRATOR         │
              │  • Read TASKS.md        │
              │  • Derive paths         │
              │  • Create worktrees     │
              │  • Assemble prompts     │
              └──────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────┐
              │   COMPONENT ASSEMBLER     │
              │  • Load skills            │
              │  • Load context           │
              │  • Load actions           │
              │  • Merge into prompt      │
              └──────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────┐
              │      SUBAGENT            │
              │  • Execute phase          │
              │  • Return JSON output     │
              └──────────────────────────┘
```

## Input/Output Schema

### Input (to subagent)

```json
{
  "correlation_id": "20260502-abc123",
  "prompt_version": "2.0.0",
  "phase": "RED",
  "task": {
    "id": "TASK-SW6-015",
    "description": "Test Double Swift 6 Update"
  },
  "worktree_path": ".worktrees/TASK-SW6-015-red/OpenOats/",
  "paths": {
    "test_file": "Tests/.../TASK-SW6-015Tests.swift",
    "implementation_file": "Sources/.../MLXAudioProcessor.swift"
  },
  "constraints": {
    "performance_target_ms": 20,
    "min_property_tests": 2
  }
}
```

### Output (from subagent)

**RED Phase**:
```json
{
  "status": "ok",
  "correlation_id": "20260502-abc123",
  "phase": "RED",
  "task_id": "TASK-SW6-015",
  "verification": {
    "build_succeeded": true,
    "test_count": 5,
    "tests_compiled": true,
    "tests_failed_as_expected": true
  },
  "next_phase": "GREEN"
}
```

**GREEN Phase**:
```json
{
  "status": "ok",
  "correlation_id": "20260502-abc123",
  "phase": "GREEN",
  "task_id": "TASK-SW6-015",
  "verification": {
    "build_succeeded": true,
    "tests_passed": true,
    "swift6_errors": 0
  },
  "technical_debt": ["Scalar loop O(n)"],
  "next_phase": "REFACTOR"
}
```

**REFACTOR Phase**:
```json
{
  "status": "ok",
  "correlation_id": "20260502-abc123",
  "phase": "REFACTOR",
  "task_id": "TASK-SW6-015",
  "verification": {
    "build_succeeded": true,
    "swift6_errors": 0,
    "tests_passed": true
  },
  "performance": {
    "meets_target": true,
    "latency_ms": 12
  },
  "improvements": ["vDSP optimization 3.5x"],
  "ready_for_merge": true
}
```

## Workflow

### Manual Mode (Copy-Paste)

```bash
# Generate prompt
python3 .prompts/orchestrator.py TASK-SW6-015 --red

# Copy output, paste to AI assistant
# AI executes, returns JSON output
# Save output to file

# Parse output, determine next phase
cat /tmp/subagent-output.json | jq '.next_phase'
# Output: "GREEN"

# Generate next phase
python3 .prompts/orchestrator.py TASK-SW6-015 --green

# Repeat...
```

### MCP Mode (Native Integration)

```json
// AI assistant calls MCP tool
{
  "tool": "generate_prompt",
  "arguments": {
    "phase": "RED",
    "task_id": "TASK-SW6-015"
  }
}

// Returns complete prompt
// AI dispatches subagent with prompt
// Subagent returns JSON output
// AI parses output, calls next phase automatically
```

## Files

| File | Purpose |
|------|---------|
| `.prompts/swift-tdd-master.md` | The One Prompt |
| `.prompts/orchestrator.py` | Python orchestrator CLI |
| `.prompts/components/` | Lego pieces (skills, context, actions) |
| `.prompts/PROMPT_VERSIONS.md` | Version registry |
| `mcp-server/` | MCP server implementation |
| `mcp-server/install.sh` | Installation script |

## Benefits

1. **One Prompt** - Single source of truth for all TDD phases
2. **Composable** - Mix and match components based on task type
3. **Tool-Agnostic** - Works with any AI coding tool
4. **Versioned** - All changes tracked as breaking API changes
5. **Deterministic** - Same input → same output
6. **Isolated** - Worktrees ensure clean separation
7. **Traced** - Correlation IDs link all phases

## Next Steps

- [ ] Add more component types (validations, schemas)
- [ ] Build worktree management tools
- [ ] Add output parsing and result tracking
- [ ] Create test validation suite
- [ ] Add component hot-reloading
- [ ] Multi-epic support

## Version

- **System**: 2.0.0
- **Master Prompt**: 2.0.0
- **MCP Server**: 1.0.0
- **Orchestrator**: 2.0.0