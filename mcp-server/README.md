# OpenOats MCP Server

**Status**: MVP Implementation

MCP (Model Context Protocol) server for orchestrating TDD workflows with **composable prompt fragments**.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AI TOOL (Claude/Cursor/etc)             │
│                     (MCP Client)                            │
└─────────────────────────────────────────────────────────────┘
                             │
                             │ MCP Protocol
                             │ (stdio / HTTP)
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                 OpenOats MCP Server                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   TOOLS     │  │  RESOURCES  │  │   PROMPTS   │         │
│  │             │  │             │  │             │         │
│  │• generate_  │  │• prompts:// │  │• tdd_red    │         │
│  │  prompt     │  │  master     │  │• tdd_green  │         │
│  │• get_task_  │  │• prompts:// │  │• tdd_refactor│         │
│  │  info       │  │  components │  │             │         │
│  │• list_      │  │• tasks://   │  │             │         │
│  │  components │  │  epic/task  │  │             │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │           COMPONENT ASSEMBLER                        │  │
│  │  • Load skill fragments                             │  │
│  │  • Load context fragments                           │  │
│  │  • Load action fragments                            │  │
│  │  • Assemble based on phase + task type              │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                             │
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
   ┌──────────┐       ┌──────────┐       ┌──────────┐
   │ Worktree │       │  Git     │       │  TASKS   │
   │ Manager  │       │  Repo    │       │  .md     │
   └──────────┘       └──────────┘       └──────────┘
```

## Installation

```bash
cd mcp-server
npm install
npm run build
```

## Usage

### As MCP Server (stdio)

Add to your AI tool's MCP config:

```json
{
  "mcpServers": {
    "openoats": {
      "command": "node",
      "args": ["/path/to/OpenOats/mcp-server/dist/index.js"],
      "env": {
        "OPENOATS_REPO_ROOT": "/path/to/OpenOats"
      }
    }
  }
}
```

### Available Tools

| Tool | Description |
|------|-------------|
| `generate_prompt` | Build phase-specific prompt from components |
| `get_task_info` | Read task from epic TASKS.md |
| `list_components` | List available Lego pieces |

### Available Resources

| Resource | URI | Description |
|----------|-----|-------------|
| Master Prompt | `prompts://master` | The One Prompt (swift-tdd-master.md) |
| Components | `prompts://components/{type}/{id}` | Individual Lego pieces |
| Tasks | `tasks://{epic}/{task_id}` | Task specifications |
| Schemas | `schemas://{name}` | Input/output schemas |

### Available Prompts

| Prompt | Description |
|--------|-------------|
| `tdd_red` | RED phase: Write failing tests |
| `tdd_green` | GREEN phase: Minimal implementation |
| `tdd_refactor` | REFACTOR phase: Optimize and clean |

## Example Usage

### Generate a RED Phase Prompt

```json
{
  "tool": "generate_prompt",
  "arguments": {
    "phase": "RED",
    "task_id": "TASK-015",
    "epic": "swift6-compliance"
  }
}
```

**Returns**:
```json
{
  "phase": "RED",
  "task_id": "TASK-015",
  "correlation_id": "20260502-abc123",
  "paths": {
    "test_file": "Tests/.../TASK-015Tests.swift",
    "implementation_file": "Sources/.../MLXAudioProcessor.swift"
  },
  "prompt": "[FULL ASSEMBLED PROMPT TEXT]"
}
```

### Get Task Info

```json
{
  "tool": "get_task_info",
  "arguments": {
    "epic": "swift6-compliance",
    "task_id": "TASK-015"
  }
}
```

**Returns**:
```json
{
  "id": "TASK-015",
  "description": "vDSP deinterleave optimization",
  "epic": "swift6-compliance"
}
```

### List Components

```json
{
  "tool": "list_components",
  "arguments": {
    "type": "skills"
  }
}
```

**Returns**:
```json
{
  "skills": ["swift-testing", "swift-concurrency", "swift-architecture"]
}
```

## Component System (Lego Pieces)

Components are YAML files in `.prompts/components/`:

```
components/
├── skills/
│   ├── swift-testing.yaml      # Swift Testing skills
│   ├── swift-concurrency.yaml  # Swift 6 concurrency
│   └── swift-architecture.yaml # Architecture patterns
├── context/
│   ├── red-context.yaml        # RED phase context
│   ├── green-context.yaml      # GREEN phase context
│   └── refactor-context.yaml   # REFACTOR phase context
├── actions/
│   ├── write-tests.yaml        # RED phase actions
│   ├── implement.yaml          # GREEN phase actions
│   └── optimize.yaml           # REFACTOR phase actions
├── validations/
│   ├── red-checks.yaml         # RED phase validations
│   ├── green-checks.yaml       # GREEN phase validations
│   └── refactor-checks.yaml    # REFACTOR phase validations
└── schemas/
    ├── red-output.yaml         # RED output schema
    ├── green-output.yaml       # GREEN output schema
    └── refactor-output.yaml    # REFACTOR output schema
```

Each component defines:
- `id`: Unique identifier
- `version`: Semver
- `applies_when`: Conditions for inclusion
- Content specific to component type

## How It Works

1. **Orchestrator** calls `generate_prompt` with phase and task
2. **Server** loads appropriate components:
   - Context component for the phase (red-context, green-context, etc.)
   - Skill components based on task type
   - Action components for steps to take
3. **Server** assembles master prompt + components + input JSON
4. **Subagent** receives complete prompt and executes
5. **Output** is validated against schema

## Development

```bash
# Install dependencies
npm install

# Build
npm run build

# Dev mode (watch)
npm run dev

# Test server
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node dist/index.js
```

## Roadmap

- [ ] HTTP transport option
- [ ] Component hot-reloading
- [ ] Validation schema enforcement
- [ ] Worktree management tools
- [ ] Output parsing and result tracking
- [ ] Multi-epic support
- [ ] Template engine (Handlebars/Mustache)