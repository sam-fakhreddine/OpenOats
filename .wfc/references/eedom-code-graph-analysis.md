# EEDOM Code Graph Analysis for OpenOats Architecture

## Overview

The `.eedom/code_graph.sqlite` database contains code analysis data and architectural checks that are highly relevant to the 3-tier architecture design.

## Database Statistics

- **Total Symbols**: 5,757 (functions, classes, methods, modules)
- **Total Relationships**: 9,310 (calls, imports, inherits)
- **Files Tracked**: 505
- **Primary Languages**: Python (mlx-swift checkouts), TypeScript (sidecast-debug tool)

**Note**: The main OpenOats Swift source files are not fully indexed in this database (filtered out), but the **architectural checks** defined are highly valuable for the design phase.

---

## Architectural Checks (Highly Relevant to 3-Tier Design)

The database defines 12 architectural checks that should be used to validate the new design:

### 1. **layer_violation** (HIGH severity)
```
Description: "core/ symbol imports from data/ (tier violation)"
```
**Application to OpenOats**: 
- This is exactly what we need to prevent in our 3-tier architecture!
- Domain layer should NOT import from Infrastructure
- Presentation should NOT import from Infrastructure directly
- Use this check to validate our Clean Architecture boundaries

### 2. **blast_radius_high** (INFO) / **blast_radius_critical** (MEDIUM)
```
Description: "Symbol has >10 direct dependents" / "Symbol has >25 direct dependents"
```
**Application to OpenOats**:
- Identify high-coupling symbols during migration
- Target: No symbol should have >10 dependents in clean architecture
- Use protocols to reduce coupling

### 3. **circular_dependency** (MEDIUM)
```
Description: "File imports form a cycle"
```
**Application to OpenOats**:
- Critical for our protocol-based design
- Domain → Business → Infrastructure should be acyclic
- Use dependency graph validation in TASK-009

### 4. **high_fan_out** (MEDIUM)
```
Description: "Function calls >8 other functions (god function)"
```
**Application to OpenOats**:
- Current issue: NotesView (3.7K lines), SessionRepository (2.1K lines)
- Target: Use cases should call <8 services
- Break down large functions during migration

### 5. **srp_high_fan_out_imports** (MEDIUM)
```
Description: "Module imports from 4+ distinct packages (SRP violation signal)"
```
**Application to OpenOats**:
- Each layer should have focused imports
- Domain: 0 external imports
- Business: Only Domain imports
- Infrastructure: Domain + external frameworks

### 6. **srp_large_class** (MEDIUM)
```
Description: "Class has >15 methods (SRP violation signal)"
```
**Application to OpenOats**:
- Current issue: Large View classes
- Target: ViewModels <15 methods, Services <15 methods
- Split large classes during migration (TASK-008)

### 7. **deep_inheritance** (MEDIUM)
```
Description: "Class inheritance chain deeper than 3 levels"
```
**Application to OpenOats**:
- Prefer composition over inheritance
- Protocol-oriented design (Swift-style)
- Max inheritance depth: 2 levels

### 8. **orphan_symbol** (INFO)
```
Description: "Function with zero callers (potential dead code)"
```
**Application to OpenOats**:
- Use during migration cleanup phase
- Identify dead code in 36K line codebase
- Remove or document intentional orphans

### 9. **noop_function** (MEDIUM)
```
Description: "Function that accomplishes nothing (pass, return None, stub)"
```
**Application to OpenOats**:
- Check for stub implementations
- Ensure protocols have real implementations

### 10. **mock_stub_in_source** (HIGH)
```
Description: "Stub/mock pattern found in non-test source file"
```
**Application to OpenOats**:
- Keep mocks in test targets only
- Use protocol-based DI for testability

### 11. **missing_tested_by** (MEDIUM)
```
Description: "Source file has no tested-by annotation"
```
**Application to OpenOats**:
- Track test coverage during migration
- Ensure new protocols have test implementations

---

## How to Apply These Checks to the Design Epic

### During Design Phase (TASKS.md)

**TASK-006: Design Infrastructure Layer Protocols**
- Use `layer_violation` check to validate: Domain has zero external imports
- Use `srp_high_fan_out_imports` to ensure focused service responsibilities

**TASK-007: Design Dependency Injection Strategy**
- Use `circular_dependency` check to validate acyclic dependency graph
- Use `blast_radius` checks to ensure low coupling

**TASK-008: Migration Strategy**
- Use `high_fan_out` to identify god functions to break down
- Use `srp_large_class` to identify classes needing decomposition
- Use `orphan_symbol` during cleanup phase

**TASK-012: Design Review Checklist**
- Add these checks as validation criteria:
  - [ ] Zero layer violations (Domain → Infrastructure imports)
  - [ ] No symbols with >10 dependents
  - [ ] No circular dependencies in protocol graph
  - [ ] All classes <15 methods
  - [ ] All functions call <8 other functions

### During Implementation Phase

**Static Analysis Integration:**
```bash
# Run checks against new code
sqlite3 .eedom/code_graph.sqlite "SELECT s.name, s.file FROM symbols s JOIN edges e ON s.id = e.source_id WHERE e.kind = 'layer_violation';"

# Check for high coupling
sqlite3 .eedom/code_graph.sqlite "SELECT s.name, s.file, COUNT(e.target_id) as fan_out FROM symbols s JOIN edges e ON s.id = e.source_id GROUP BY s.id HAVING fan_out > 8;"
```

**CI/CD Integration:**
- Add checks to pre-commit hooks
- Fail build on HIGH severity violations
- Track metrics over time (coupling trends)

---

## Recommendations for OpenOats

### 1. **Layer Violation Prevention**
```swift
// BAD - Domain importing Infrastructure (layer violation)
import MLX  // ❌ Domain should not know about MLX

// GOOD - Domain defines protocol, Infrastructure implements
// Domain layer:
protocol TranscriptionService { }

// Infrastructure layer:
import MLX
struct MLXTranscriptionService: TranscriptionService { }
```

### 2. **Coupling Reduction Targets**
- **Current state**: Unknown (need to index Swift source)
- **Target state**: 
  - Max 10 dependents per symbol
  - Max 8 function calls per function
  - Max 15 methods per class

### 3. **Circular Dependency Prevention**
```swift
// BAD - Circular dependency
// A imports B, B imports A

// GOOD - Protocol breaks cycle
// Domain defines protocol
// Business uses protocol
// Infrastructure implements protocol
```

### 4. **SRP Enforcement**
- Split NotesView (3.7K lines) into:
  - NotesView (UI only)
  - NotesViewModel (state management)
  - NotesUseCases (business logic)
  - NotesRepository (data access)

---

## Action Items

1. **Index Swift Source**: Run eedom analysis on OpenOats Swift source (not just checkouts)
2. **Baseline Metrics**: Get current coupling/dependency metrics
3. **Set Thresholds**: Define acceptable blast radius, fan-out, class size
4. **CI Integration**: Add checks to build pipeline
5. **Migration Tracking**: Use orphan_symbol check during cleanup

---

## Related Documents

- `TASKS.md` - Design tasks (incorporate these checks)
- `code-patterns-from-repos.md` - Implementation patterns
- `apple-macos-design-patterns.md` - UI/UX patterns
- `swift-troubleshooting/SKILL.md` - Best practices

---

**Conclusion**: The eedom code graph database defines excellent architectural checks that should be integrated into the design validation (TASK-012) and used throughout implementation to ensure the 3-tier architecture maintains clean boundaries and low coupling.
