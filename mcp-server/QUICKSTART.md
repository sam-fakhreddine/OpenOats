# OpenOats MCP Server - Quick Start

## Install (One Command)

```bash
cd /path/to/OpenOats
./mcp-server/install.sh
```

This installs to:
- Claude Code: `~/.config/claude/config.json`
- Cursor: `~/.cursor/mcp.json`

## Usage

### 1. Generate a TDD Prompt

Ask your AI assistant:

> "Use the openoats server to generate a RED phase prompt for TASK-015"

The AI will call:
```json
{
  "tool": "generate_prompt",
  "arguments": {
    "phase": "RED",
    "task_id": "TASK-015"
  }
}
```

**Returns**: Complete prompt with:
- Master TDD instructions
- RED phase context
- Task-specific input JSON
- Correlation ID for tracking

### 2. Get Task Info

> "What is TASK-015 about?"

AI calls:
```json
{
  "tool": "get_task_info",
  "arguments": {
    "epic": "swift6-compliance",
    "task_id": "TASK-015"
  }
}
```

**Returns**: Task ID, description, epic

### 3. List Available Components

> "What Lego pieces are available?"

AI calls:
```json
{
  "tool": "list_components",
  "arguments": {}
}
```

**Returns**: All available components:
```json
{
  "skills": ["swift-testing", "swift-concurrency", ...],
  "context": ["red-context", "green-context", "refactor-context"],
  "actions": ["write-tests", "implement", "optimize"]
}
```

## Full TDD Cycle Example

### Phase 1: RED (Write Failing Tests)

```
You: Generate RED phase for TASK-015

AI: [Calls generate_prompt]
    
    Returns:
    - Full prompt with instructions
    - Correlation ID: 20260502-a1b2c3d4
    - Paths to test/implementation files

You: Dispatch subagent with this prompt

Subagent: Writes tests, returns JSON:
{
  "status": "ok",
  "phase": "RED",
  "verification": {
    "tests_compiled": true,
    "tests_failed_as_expected": true
  }
}
```

### Phase 2: GREEN (Minimal Implementation)

```
You: Generate GREEN phase for TASK-015 (same correlation ID)

AI: [Calls generate_prompt]

You: Dispatch subagent

Subagent: Implements minimal code, returns:
{
  "status": "ok",
  "phase": "GREEN",
  "technical_debt": ["Scalar loop O(n)", "Hardcoded values"]
}
```

### Phase 3: REFACTOR (Optimize)

```
You: Generate REFACTOR phase for TASK-015

Subagent: Optimizes, returns:
{
  "status": "ok",
  "phase": "REFACTOR",
  "performance": {
    "meets_target": true,
    "speedup": "3.5x"
  },
  "ready_for_merge": true
}
```

## Architecture

```
AI Assistant → MCP Protocol → OpenOats Server → Components → Assembled Prompt
     ↑                                                              ↓
     └──────── JSON Output ←──────── Subagent ←────────────────────┘
```

**Key Design**:
- **One Master Prompt** (swift-tdd-master.md) with 3 phase modes
- **Composable Components** (skills, context, actions) as Lego pieces
- **Tool Agnostic** - works with Claude, Cursor, Copilot, etc.
- **Deterministic** - same input → same output
- **Versioned** - prompt_version tracked in all I/O

## Components (Lego Pieces)

Located in `.prompts/components/`:

### Skills
What to load before work:
- `swift-testing` → `skill(name="swift-testing-pro")`
- `swift-concurrency` → `skill(name="swift-concurrency-pro")`

### Context
What to read for each phase:
- `red-context` → AGENTS.md, test file, stubs
- `green-context` → Test file (spec), implementation file
- `refactor-context` → Tests, current implementation, optimize

### Actions
What steps to take:
- `write-tests` → Create test file, property tests, edge cases
- `implement` → Minimal code, make tests pass
- `optimize` → vDSP, Swift 6, performance targets

## Troubleshooting

### Server not connecting

```bash
# Test server manually
cd mcp-server
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node dist/index.js
```

### Components not found

```bash
# Check component structure
ls .prompts/components/
# Should show: skills/ context/ actions/ validations/ schemas/
```

### Rebuild after changes

```bash
cd mcp-server
npm run build
```

## Advanced Usage

### Custom Component Selection

Override default component selection:

```json
{
  "tool": "generate_prompt",
  "arguments": {
    "phase": "REFACTOR",
    "task_id": "TASK-015",
    "components": [
      "skills/swift-concurrency",
      "context/refactor-context",
      "actions/optimize-vdsp"
    ]
  }
}
```

### Raw Resource Access

Access master prompt directly:
- `resource: prompts://master`

Access specific component:
- `resource: prompts://components/skills/swift-testing`

### Using Prompts Endpoint

Get pre-assembled prompt:
- `prompt: tdd_red(task_id: "TASK-015")`
- `prompt: tdd_green(task_id: "TASK-015")`
- `prompt: tdd_refactor(task_id: "TASK-015")`

## Version

- **MCP Server**: 1.0.0
- **Master Prompt**: 2.0.0
- **Protocol**: MCP 0.5.0

## Links

- [Master Prompt](../.prompts/swift-tdd-master.md)
- [Components](../.prompts/components/)
- [PROMPT_VERSIONS.md](../.prompts/PROMPT_VERSIONS.md)