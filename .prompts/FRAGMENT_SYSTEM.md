---
name: prompt-fragment-system
version: "1.0.0"
description: Deterministic prompt assembly from composable fragments
---

# Prompt Fragment System

**Version**: 1.0.0  
**Purpose**: Build prompts like Lego blocks using deterministic assembly

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR (You)                      │
│  1. Reads task spec (TASKS.md entry)                       │
│  2. Selects fragments from library                         │
│  3. Assembles prompt via builder spec                       │
│  4. Dispatches to subagent                                  │
└─────────────────────────────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
  ┌──────────┐        ┌──────────┐        ┌──────────┐
  │ Fragments │        │ Assembly │        │ Builder  │
  │  (YAML)   │        │  (JSON)  │        │ (Script) │
  └──────────┘        └──────────┘        └──────────┘
       │                   │                   │
       └───────────────────┴───────────────────┘
                           │
                    ┌──────────────┐
                    │ Final Prompt │
                    │  (Markdown)  │
                    └──────────────┘
```

## Fragment Types

### 1. Role Fragments (`components/roles/`)

Define agent personality and constraints:

```yaml
# components/roles/red-agent.yaml
id: red-agent
version: "1.0.0"
description: RED agent writes failing tests
purpose: |
  You are the RED Agent in a 3-phase TDD workflow.
  
  **Purpose**: Write a failing test that defines required behavior.
  **Exit Condition**: Test compiles but FAILS when run.
  **Out of Scope**: Any implementation code.
  
constraints:
  - MUST NOT write any implementation code
  - MUST NOT make the test pass
  - MUST use property-based testing (at least 2)
  - MUST mark tests with @Test
  
output_schema: red-output-schema
```

### 2. Skill Fragments (`components/skills/`)

Define required skill loads:

```yaml
# components/skills/swift-testing.yaml
id: swift-testing
skills:
  - swift-testing-pro
  - swift-concurrency-pro
load_instructions: |
  ## Required Skills (Load First)
  
  Load these skills before any work:
  ```bash
  skill(name="swift-testing-pro")
  skill(name="swift-concurrency-pro")
  ```
```

### 3. Context Fragments (`components/context/`)

Define what to read:

```yaml
# components/context/tdd-red.yaml
id: tdd-red-context
required_reads:
  - path: AGENTS.md
    reason: Coding standards and patterns
  - path: "{{task.test_file_path}}"
    reason: Where to write the test
  - path: "{{task.target_file}}"
    reason: What code to test (stub expected)
    optional: true
validation: |
  If any required file (non-optional) is missing:
  ```json
  {
    "status": "error",
    "reason": "missing_artifact",
    "missing": ["{{path}}"],
    "output": null
  }
  ```
```

### 4. Action Fragments (`components/actions/`)

Define what actions to take:

```yaml
# components/actions/write-failing-test.yaml
id: write-failing-test
steps:
  - name: Setup worktree
    command: |
      git worktree add {{worktree_path}} -b {{task.id}}-red
      
  - name: Create test file
    template: |
      import Testing
      
      struct {{task.id}}Tests {
          // TASK-{{task.id}}: {{task.description}}
          
          @Test
          func basicFunctionality() {
              #expect(false, "Not yet implemented")
          }
          
          {{#properties}}
          @Test(arguments: {{generator}})
          func {{name}}({{params}}) {
              // Test invariant: {{invariant}}
          }
          {{/properties}}
      }
      
  - name: Verify test fails
    command: |
      cd {{worktree_path}}
      swift test --filter {{task.id}} 2>&1 | grep -c "failed\|FAIL"
      
validation: |
  Test MUST fail. If it passes, return error.
```

### 5. Output Schema Fragments (`components/schemas/`)

Define response structure:

```yaml
# components/schemas/red-output.yaml
id: red-output-schema
schema:
  type: object
  required:
    - status
    - correlation_id
    - phase
    - task_id
    - verification
  properties:
    status:
      type: string
      enum: [ok, error]
    correlation_id:
      type: string
    phase:
      type: string
      enum: [RED]
    task_id:
      type: string
    verification:
      type: object
      properties:
        build_succeeded:
          type: boolean
        test_failed_as_expected:
          type: boolean
    next_phase:
      type: string
      enum: [GREEN]
```

## Assembly Specifications

JSON specs that compose fragments:

```json
{
  "id": "tdd-red-prompt",
  "version": "1.0.0",
  "fragments": [
    { "id": "red-agent", "section": "role" },
    { "id": "swift-testing", "section": "skills" },
    { "id": "tdd-red-context", "section": "context" },
    { "id": "write-failing-test", "section": "actions" },
    { "id": "red-output-schema", "section": "output" }
  ],
  "template": "standard-prompt",
  "variables": {
    "task": "{{task}}",
    "worktree_path": "{{worktree_path}}",
    "correlation_id": "{{correlation_id}}"
  }
}
```

## Builder Tool

A CLI tool that assembles prompts:

```bash
# Assemble a prompt for TASK-015 (RED phase)
.prompts/builder assemble \
  --spec .prompts/assembly/tdd-red.json \
  --vars task_id=TASK-015,correlation_id=run-001 \
  --output .prompts/generated/task-015-red.md
```

The builder:
1. Loads the assembly spec
2. Resolves all fragment references
3. Substitutes variables
4. Applies the template
5. Validates against output schema
6. Returns the final prompt

## Templates

Base markdown structures:

```markdown
<!-- templates/standard-prompt.md -->
---
name: {{role.id}}
version: "{{role.version}}"
---

{{role.purpose}}

{{skills.load_instructions}}

## Input Context

{{context.validation}}

{{context.required_reads}}

## Actions

{{actions.steps}}

## Output Schema

You MUST return valid JSON conforming to:

```json
{{output.schema}}
```

{{output.example}}
```

## Usage Example

Given a task in TASKS.md:

```yaml
- id: TASK-015
  description: "vDSP deinterleave optimization"
  test_file: "Tests/.../AudioProcessorTests.swift"
  target: "Sources/.../MLXAudioProcessor.swift"
```

The orchestrator:

```python
# Conceptual orchestrator code
spec = load_assembly("tdd-red")
prompt = builder.assemble(spec, {
    "task": task_015,
    "correlation_id": generate_uuid(),
    "worktree_path": f".worktrees/{task_015.id}-red/OpenOats/"
})
dispatch_to_subagent(prompt)
```

## Benefits

1. **DRY**: Common fragments (skills, schemas) reused across prompts
2. **Version Control**: Each fragment versioned independently
3. **Testing**: Fragments can be unit tested for correctness
4. **Flexibility**: Same fragments compose differently for different phases
5. **Auditability**: Full assembly chain visible in spec file