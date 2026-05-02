# Prompt Version Registry

**Purpose**: Track all prompt changes as breaking API changes

## Philosophy

Prompts are **API contracts** between the orchestrator and subagents. Like any API:
- Changes must be versioned
- Breaking changes require major version bumps
- All versions must be documented
- Migration paths must be provided

## Current Versions

| Prompt | Version | Status | Breaking Changes |
|--------|---------|--------|------------------|
| `swift-tdd-master.md` | 2.0.0 | **ACTIVE** | Consolidated 3-phase prompt with JSON I/O |
| `swift-tdd-red.md` | 1.0.0 | **DEPRECATED** | Split into master prompt |
| `swift-tdd-green.md` | 1.0.0 | **DEPRECATED** | Split into master prompt |
| `swift-tdd-refactor.md` | 1.0.0 | **DEPRECATED** | Split into master prompt |

## Version History

### 2.0.0 - swift-tdd-master.md (Current)

**Date**: 2026-05-02
**Breaking Changes**: YES (from 1.x)

**Summary**: Consolidated the three separate TDD prompts (RED/GREEN/REFACTOR) into a single master prompt with phase selection.

**Changes**:
- Unified RED, GREEN, REFACTOR into one prompt
- Phase determined by `phase` field in input JSON
- Each phase has isolated instructions
- All phases use same output schema pattern
- Tool-agnostic (works with Claude, Cursor, Copilot)

**Migration**:
```python
# OLD (1.x) - Three separate dispatches
dispatch("swift-tdd-red.md", task, worktree_red)
dispatch("swift-tdd-green.md", task, worktree_green)
dispatch("swift-tdd-refactor.md", task, worktree_refactor)

# NEW (2.0) - One prompt, phase in input
dispatch("swift-tdd-master.md", {**task, "phase": "RED"}, worktree_red)
dispatch("swift-tdd-master.md", {**task, "phase": "GREEN"}, worktree_green)
dispatch("swift-tdd-master.md", {**task, "phase": "REFACTOR"}, worktree_refactor)
```

### 1.0.0 - Individual Phase Prompts

**Date**: 2026-05-02
**Status**: DEPRECATED

**Files**:
- `swift-tdd-red.md` - Write failing tests
- `swift-tdd-green.md` - Minimal implementation
- `swift-tdd-refactor.md` - Optimize and clean

**Reason for Deprecation**: Maintenance overhead of three files, drift between versions, no unified phase handling.

## Schema Versions

### Input Schema (2.0.0)

```json
{
  "correlation_id": "string (uuid)",
  "prompt_version": "2.0.0",
  "phase": "RED | GREEN | REFACTOR",
  "task": {
    "id": "string",
    "description": "string"
  },
  "worktree_path": "string",
  "paths": {
    "test_file": "string",
    "implementation_file": "string"
  },
  "constraints": {
    "performance_target_ms": 20,
    "min_property_tests": 2
  }
}
```

### Output Schemas (2.0.0)

**RED Phase Output**:
```json
{
  "status": "ok | error",
  "correlation_id": "string",
  "phase": "RED",
  "task_id": "string",
  "verification": {
    "build_succeeded": "boolean",
    "test_count": "number",
    "tests_compiled": "boolean",
    "tests_failed_as_expected": "boolean"
  },
  "next_phase": "GREEN"
}
```

**GREEN Phase Output**:
```json
{
  "status": "ok | error",
  "correlation_id": "string",
  "phase": "GREEN",
  "task_id": "string",
  "verification": {
    "build_succeeded": "boolean",
    "tests_passed": "boolean",
    "swift6_errors": "number"
  },
  "technical_debt": ["string"],
  "next_phase": "REFACTOR"
}
```

**REFACTOR Phase Output**:
```json
{
  "status": "ok | error",
  "correlation_id": "string",
  "phase": "REFACTOR",
  "task_id": "string",
  "verification": {
    "build_succeeded": "boolean",
    "swift6_errors": "number",
    "tests_passed": "boolean",
    "test_count": "number",
    "property_tests": "number"
  },
  "performance": {
    "meets_target": "boolean",
    "latency_ms": "number"
  },
  "improvements": ["string"],
  "ready_for_merge": "boolean",
  "next_action": "string"
}
```

## Deprecation Policy

1. **Major versions** (X.0.0): Breaking changes, new schema
2. **Minor versions** (x.Y.0): New features, backward compatible
3. **Patch versions** (x.y.Z): Bug fixes, no schema changes

**Deprecation timeline**:
- Deprecation announced: Immediately
- Support ends: 30 days after new major version
- Removal: 60 days after new major version

## Migration Checklist

When updating prompt version:

- [ ] Update `PROMPT_VERSIONS.md`
- [ ] Update orchestrator default version
- [ ] Test with all three phases
- [ ] Update schema documentation
- [ ] Announce in AGENTS.md
- [ ] Provide migration guide
- [ ] Tag git commit with prompt version

## Adding New Prompts

When creating a new prompt:

1. Start at version 1.0.0
2. Add to this registry
3. Define input/output schemas
4. Document in AGENTS.md
5. Add to orchestrator

**Example entry**:
```markdown
### 1.0.0 - new-prompt.md

**Date**: YYYY-MM-DD
**Status**: ACTIVE

**Purpose**: What this prompt does

**Input Schema**: ...
**Output Schema**: ...
```