# OpenOats State - Session Handoff

**Last Updated**: 2026-05-02  
**Current Branch**: `feat!/3tier-clean-architecture`  
**Integration Branch**: `feat!/3tier-clean-architecture` (fork: sam-fakhreddine/OpenOats)

---

## ✅ COMPLETED (Ready to Use)

### TDD Orchestration System v2.0
One master prompt + composable components for deterministic TDD workflows.

**Files Built:**
- `.prompts/swift-tdd-master.md` - The One Prompt (handles RED/GREEN/REFACTOR)
- `.prompts/orchestrator.py` - Python CLI (tool-agnostic)
- `.prompts/components/` - Lego pieces:
  - `skills/swift-testing.yaml` - Swift Testing skills
  - `skills/swift-concurrency.yaml` - Swift 6 concurrency
  - `context/red-context.yaml` - RED phase context
  - `context/green-context.yaml` - GREEN phase context
  - `context/refactor-context.yaml` - REFACTOR phase context
  - `actions/write-tests.yaml` - Test writing steps
- `TDD_ORCHESTRATION.md` - Full system documentation
- `.prompts/PROMPT_VERSIONS.md` - Version registry

**MCP Server:**
- `mcp-server/src/index.ts` - Full MCP implementation
- `mcp-server/install.sh` - One-command install for Claude/Cursor
- `mcp-server/README.md` - Server docs
- `mcp-server/QUICKSTART.md` - Usage examples

**Epic Workspace:**
- `.wfc/epics/swift6-compliance/TASKS.md` - 20 tasks, 4 phases
- `.wfc/epics/swift6-compliance/adr/` - 5 ADRs
- `.wfc/epics/swift6-compliance/PROPERTIES.md` - 21 formal properties

---

## 🎯 NEXT STEPS (Priority Order)

### 1. Start TDD Cycle (Immediate)
Pick a task from TASKS.md and run:

```bash
# Generate RED phase prompt
python3 .prompts/orchestrator.py TASK-SW6-015 --red

# Copy output, dispatch to subagent
# Subagent returns JSON output
# Save to file

# Continue to GREEN
python3 .prompts/orchestrator.py TASK-SW6-015 --green

# Continue to REFACTOR
python3 .prompts/orchestrator.py TASK-SW6-015 --refactor
```

**Recommended First Task**: TASK-SW6-015 "Test Double Swift 6 Update"
- Infrastructure layer (familiar territory)
- Tests existing test doubles
- Good for validating the system

### 2. Install MCP Server (Optional)
For native AI tool integration:

```bash
./mcp-server/install.sh
```

Then use via AI assistant:
- Tool: `generate_prompt(phase='RED', task_id='TASK-SW6-015')`
- Resource: `prompts://master`
- Prompt: `tdd_red(task_id: 'TASK-SW6-015')`

### 3. Build Missing Components
- [ ] Validations (red-checks, green-checks, refactor-checks)
- [ ] Output schemas (JSON Schema files)
- [ ] More action components (optimize-vdsp, add-sendable, etc.)

---

## 📁 Key Locations

| What | Where |
|------|-------|
| Master Prompt | `.prompts/swift-tdd-master.md` |
| Orchestrator | `.prompts/orchestrator.py` |
| Components | `.prompts/components/{type}/{id}.yaml` |
| Task List | `.wfc/epics/swift6-compliance/TASKS.md` |
| Documentation | `TDD_ORCHESTRATION.md` |
| MCP Server | `mcp-server/` |
| Version Registry | `.prompts/PROMPT_VERSIONS.md` |

---

## 🔧 Quick Commands

```bash
# Generate phase prompt (markdown to stdout)
python3 .prompts/orchestrator.py TASK-SW6-015 --red

# Generate to files
python3 .prompts/orchestrator.py TASK-SW6-015 --all --output-format=files

# Generate JSON dispatch instructions
python3 .prompts/orchestrator.py TASK-SW6-015 --red --output-format=json

# List available components
python3 -c "
import yaml
from pathlib import Path
for f in Path('.prompts/components').rglob('*.yaml'):
    doc = yaml.safe_load(f.read_text())
    print(f'{f.parent.name}/{f.stem}: {doc.get(\"description\", \"\")}')
"

# Clean worktrees after TDD cycle
git worktree remove .worktrees/TASK-XXX-red --force 2>/dev/null
git branch -D TASK-XXX-red 2>/dev/null
```

---

## 🏗️ Architecture Reminder

```
┌─────────────────────────────────────────────────────────────┐
│  AI Assistant (Claude/Cursor/Copilot)                       │
└─────────────────────────────────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
         Orchestrator   MCP Server   Copy-Paste
              │              │              │
              └──────────────┼──────────────┘
                             ▼
              ┌──────────────────────────┐
              │  Component Assembler   │
              │  • Load skills          │
              │  • Load context         │
              │  • Merge into prompt    │
              └──────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────┐
              │    Subagent              │
              │  • Execute phase          │
              │  • Return JSON output     │
              └──────────────────────────┘
```

**Key Principle**: One master prompt + `phase` field in input JSON. Zero context sharing between RED/GREEN/REFACTOR agents.

---

## 📝 Input/Output Schema

### Input (to subagent)
```json
{
  "correlation_id": "20260502-uuid",
  "prompt_version": "2.0.0",
  "phase": "RED",
  "task": {
    "id": "TASK-SW6-015",
    "description": "Test Double Swift 6 Update"
  },
  "worktree_path": ".worktrees/TASK-SW6-015-red/OpenOats/",
  "paths": {
    "test_file": "Tests/.../TASK-SW6-015Tests.swift",
    "implementation_file": "Sources/.../File.swift"
  },
  "constraints": {
    "performance_target_ms": 20,
    "min_property_tests": 2
  }
}
```

### Output (from subagent)
```json
{
  "status": "ok",
  "correlation_id": "20260502-uuid",
  "phase": "RED",
  "task_id": "TASK-SW6-015",
  "verification": {
    "build_succeeded": true,
    "tests_compiled": true,
    "tests_failed_as_expected": true
  },
  "next_phase": "GREEN"
}
```

---

## ⚠️ Important Notes

1. **Branch Strategy**: Always use `feat!/3tier-clean-architecture` as base
2. **Worktrees**: Each phase gets isolated worktree (clean up after: 2.5GB each)
3. **Correlation IDs**: Track across phases for distributed tracing
4. **JSON I/O**: All subagent output must be valid JSON
5. **Context Isolation**: REFACTOR agent has zero knowledge of RED/GREEN reasoning

---

## 🚀 For Next Session

**If Starting Fresh:**
1. Read this file
2. Read `TDD_ORCHESTRATION.md`
3. Pick task from `.wfc/epics/swift6-compliance/TASKS.md`
4. Run: `python3 .prompts/orchestrator.py TASK-XXX --red`

**If Continuing TDD:**
- Parse subagent output from previous phase
- Run next phase with same correlation_id
- Or use: `python3 .prompts/orchestrator.py TASK-XXX --green`

**If Debugging:**
- Check worktree exists: `ls .worktrees/TASK-XXX-*/`
- Check output valid JSON: `cat output.json | jq .`
- Check branch clean: `git status`

---

## 📊 Current Stats

- **Tasks**: 20 (swift6-compliance epic)
- **Phases**: 4 (Mock → Protocol → Actor → Test)
- **ADRs**: 5
- **Components**: 6 (skills, context, actions)
- **Files Created**: 41
- **Lines Added**: 9,910

**Status**: ✅ System complete and ready for TDD cycles