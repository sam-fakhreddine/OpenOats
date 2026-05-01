# TASK-012: Design Review Checklist

## Comprehensive Validation Framework

This document provides a complete checklist for reviewing the 3-tier architecture design, including AST-based code quality validation queries.

---

## 1. Architecture Review

### Layer Responsibilities

| Layer | Responsibility | Verification |
|-------|---------------|------------|
| Presentation | UI rendering, user input, view models | Check: No direct I/O |
| Business Logic | Use cases, orchestration, coordination | Check: Protocol dependencies only |
| Domain | Entities, value objects, errors, identifiers | Check: Zero external deps |
| Infrastructure | External services, persistence, APIs | Check: Swappable implementations |

### Dependency Direction

```
✅ CORRECT: Presentation → Business → Domain ← Infrastructure

❌ WRONG: Domain → Infrastructure (layer violation)
❌ WRONG: Business → Presentation (circular)
```

**Checklist:**

- [ ] **All layers have clear responsibilities** (verified via protocol inspection)
  - Verification: `grep -r "import.*Infrastructure" OpenOats/Sources/Domain/` should return nothing
  - Tool: OpenGrep rule `domain-imports-infrastructure.yaml`

- [ ] **Dependencies flow inward only**
  - Verification: No file in `Domain/` imports from `Infrastructure/`
  - No file in `BusinessLogic/` imports from `Presentation/`
  - Tool: EEDOM SQL query for import cycles

- [ ] **No circular dependencies**
  - Verification: Run circular dependency SQL query (see Section 6)
  - Target: Zero cycles in protocol graph

- [ ] **Domain layer has zero external framework dependencies**
  - Verification: Check Package.swift - Domain target has no external deps
  - Acceptable: Foundation, Swift Standard Library only

- [ ] **All public APIs are protocol-based**
  - Verification: No public concrete classes in upper layers
  - All dependencies are `any ProtocolName` not concrete types

---

## 2. Swift 6.2 Concurrency Review

### Concurrency Checklist

| # | Item | Verification | Target |
|---|------|------------|--------|
| 1 | All async operations handle errors | Search for `try await` without `do/catch` | 100% handled |
| 2 | Sendable conformance verified | `Sendable` protocol on all domain types | 100% conformant |
| 3 | Actor isolation correct | `@MainActor` on UI, `actor` for shared state | 0 isolation errors |
| 4 | No blocking on MainActor | All long ops use `await` | 0 blocking calls |
| 5 | Cancellation handled | `Task.isCancelled` checks in loops | 100% cooperative |
| 6 | No unchecked Sendable | Audit all `@unchecked Sendable` | 0 undocumented |
| 7 | Actor reentrancy safe | No state assumptions across suspension | 0 race conditions |
| 8 | AsyncStream properly used | Non-isolated streams for cross-actor communication | 100% correct |

### Specific Verification Commands

```bash
# Check for @unchecked Sendable
opengrep scan --pattern "@unchecked Sendable" OpenOats/Sources/
# Target: Zero results (or documented with justification)

# Check for Sendable conformance
opengrep scan --pattern "struct.*:.*Sendable" OpenOats/Sources/Domain/
# Target: All domain structs conform

# Check for MainActor usage
opengrep scan --pattern "@MainActor" OpenOats/Sources/Presentation/
# Target: All view models have @MainActor

# Check for actor usage in services
opengrep scan --pattern "^public actor" OpenOats/Sources/Infrastructure/
# Target: All mutable services are actors
```

---

## 3. Protocol Design Review

### Protocol Quality Checklist

| # | Item | Verification | Target |
|---|------|------------|--------|
| 1 | Protocols are focused | Single responsibility per protocol | < 10 methods each |
| 2 | Method signatures complete | All parameters and return types explicit | 100% typed |
| 3 | Error handling comprehensive | `throws` or `Result` on all failable ops | 100% covered |
| 4 | Async where appropriate | Network/file I/O uses async | 100% non-blocking |
| 5 | Protocols support testing | Mock implementations possible | All protocols mockable |
| 6 | Sendable conformance | All protocols inherit Sendable | 100% Sendable |
| 7 | Documentation comments | All public APIs documented | 100% documented |

### Protocol Inspection

```swift
// Example: Well-designed protocol checklist

public protocol SessionRepositoryProtocol: Sendable {
    // ✅ Single responsibility: Session persistence only
    // ✅ Sendable-safe for Swift 6
    // ✅ Async for non-blocking I/O
    // ✅ Typed throws for specific error handling
    // ✅ Clear parameter and return types
    
    /// Save a session to persistent storage
    /// - Parameter session: The session to save
    /// - Throws: StorageError if persistence fails
    func save(_ session: Session) async throws(StorageError)
    
    /// Load a session by its identifier
    /// - Parameter id: The session ID
    /// - Returns: The session if found, nil otherwise
    /// - Throws: StorageError if loading fails
    func load(id: SessionID) async throws(StorageError) -> Session?
}
```

---

## 4. Code Quality Metrics (AST-Based Hotpoint Detection)

### Tool Strategy: EEDOM (Primary) + OpenGrep (Quick)

**EEDOM** provides full AST graph analysis with SQL queries.
**OpenGrep** provides fast pattern-based validation without database setup.

### 4.1 High Fan-Out Detection (God Functions)

**SQL Query:**
```sql
-- Finds functions calling >8 other functions (indicates SRP violation)
SELECT s.name, s.file, s.line, COUNT(e.id) as calls_out
FROM symbols s
JOIN edges e ON e.source_id = s.id AND e.kind = 'calls'
WHERE s.file IN ({changed_files})
GROUP BY s.id
HAVING calls_out > 8
ORDER BY calls_out DESC;
```

**OpenGrep Rule:**
```yaml
# .opengrep/high-fanout.yaml
rules:
  - id: high-fanout-function
    pattern: |
      func $NAME(...) {
        $FUNCS
      }
    metavariable-regex:
      metavariable: $FUNCS
      regex: '(?s).{500,}'  # Approximation: long body suggests many calls
    languages: [swift]
    message: "Function may have high fan-out. Check for SRP violation."
    severity: WARNING
```

**Target:**
- [ ] **Zero functions with >8 calls after migration**
- [ ] **Current concern:** NotesView (3.7K lines) likely has god functions
- [ ] **Action:** Split into focused use cases during TASK-008

**Running:**
```bash
# EEDOM SQL (exact)
sqlite3 .eedom/code_graph.sqlite "SELECT s.name, s.file, COUNT(e.id) as calls FROM symbols s JOIN edges e ON e.source_id = s.id AND e.kind = 'calls' GROUP BY s.id HAVING calls > 8;"

# OpenGrep (approximation)
opengrep scan --config .opengrep/high-fanout.yaml OpenOats/Sources/
```

### 4.2 Blast Radius Analysis (Coupling Detection)

**SQL Query:**
```sql
-- Finds symbols with >10 dependents (high coupling risk)
SELECT s.name, s.file, s.line, COUNT(e.id) as dependents
FROM symbols s
JOIN edges e ON e.target_id = s.id
WHERE s.file IN ({changed_files})
GROUP BY s.id
HAVING dependents > 10
ORDER BY dependents DESC;
```

**Target:**
- [ ] **Zero symbols with >10 dependents after migration**
- [ ] **Current concern:** SessionRepository (2.1K lines) likely high blast radius
- [ ] **Action:** Use protocols to reduce coupling during TASK-007

**Running:**
```bash
sqlite3 .eedom/code_graph.sqlite "SELECT s.name, s.file, COUNT(e.id) as deps FROM symbols s JOIN edges e ON e.target_id = s.id GROUP BY s.id HAVING deps > 10;"
```

### 4.3 Critical Blast Radius (Blockers)

**SQL Query:**
```sql
-- Finds symbols with >25 dependents (critical coupling)
SELECT s.name, s.file, s.line, COUNT(e.id) as dependents
FROM symbols s
JOIN edges e ON e.target_id = s.id
WHERE s.file IN ({changed_files})
GROUP BY s.id
HAVING dependents > 25;
```

**Target:**
- [ ] **Zero symbols with >25 dependents**
- [ ] **Action:** Immediate protocol extraction required

### 4.4 Circular Dependency Detection

**SQL Query:**
```sql
-- Finds import cycles A→B→A (violates Clean Architecture)
SELECT DISTINCT s1.file as file_a, s2.file as file_b
FROM edges e1
JOIN symbols s1 ON e1.source_id = s1.id
JOIN symbols s2 ON e1.target_id = s2.id
JOIN edges e2 ON e2.source_id = s2.id AND e2.target_id = s1.id
WHERE e1.kind = 'imports' AND e2.kind = 'imports'
  AND s1.file IN ({changed_files});
```

**OpenGrep Rule:**
```yaml
# .opengrep/circular-import.yaml
rules:
  - id: circular-import-risk
    pattern: |
      import OpenOats.$MODULE_A
      ...
      import OpenOats.$MODULE_B
    languages: [swift]
    message: "Check for circular import between modules"
    severity: INFO
```

**Target:**
- [ ] **Zero circular dependencies in protocol graph**
- [ ] **Validation:** Run before and after TASK-007 (DI Strategy)

**Running:**
```bash
sqlite3 .eedom/code_graph.sqlite "SELECT DISTINCT s1.file, s2.file FROM edges e1 JOIN symbols s1 ON e1.source_id = s1.id JOIN symbols s2 ON e1.target_id = s2.id JOIN edges e2 ON e2.source_id = s2.id AND e2.target_id = s1.id WHERE e1.kind = 'imports';"
```

### 4.5 Large Class Detection (SRP Violations)

**SQL Query:**
```sql
-- Finds classes with >15 methods (god classes)
SELECT c.name, c.file, COUNT(*) AS method_count
FROM symbols c
JOIN symbols m ON m.file = c.file AND m.kind = 'function' 
  AND m.line > c.line AND m.line <= COALESCE(c.end_line, 99999)
WHERE c.kind = 'class'
  AND c.file IN ({changed_files})
GROUP BY c.name, c.file
HAVING COUNT(*) > 15;
```

**OpenGrep Rule:**
```yaml
# .opengrep/god-class.yaml
rules:
  - id: god-class
    pattern: |
      class $CLASS {
        $METHODS
      }
    metavariable-regex:
      metavariable: $METHODS
      regex: '(?s)(func\s+\w+.*\{.*\}){15,}'
    languages: [swift]
    message: "Class has >15 methods. Consider decomposition."
    severity: WARNING
```

**Target:**
- [ ] **All classes have <15 methods after migration**
- [ ] **Current concern:** NotesView, SessionRepository are god classes
- [ ] **Action:** Decompose during TASK-008 (Migration Strategy)

### 4.6 Orphan Symbol Detection (Dead Code)

**SQL Query:**
```sql
-- Finds functions with zero callers (potential dead code)
SELECT s.name, s.file, s.line, s.kind
FROM symbols s
LEFT JOIN edges e ON e.target_id = s.id AND e.kind = 'calls'
WHERE s.file IN ({changed_files})
  AND s.kind IN ('function', 'method')
  AND s.name NOT LIKE '\_%' ESCAPE '\'
  AND s.name NOT IN ('main', 'setup', 'teardown', 'preview')
  AND e.id IS NULL;
```

**Target:**
- [ ] **Document or remove all orphan symbols during cleanup**
- [ ] **Action:** Run during TASK-011 (Cleanup Phase)

---

## 5. Layer Violation Detection

### OpenGrep Rules for Layer Enforcement

```yaml
# .opengrep/layer-violation.yaml
rules:
  - id: domain-imports-infrastructure
    pattern: |
      import MLX
      import WhisperKit
    languages: [swift]
    message: "Layer Violation: Domain must not import infrastructure frameworks"
    severity: ERROR
    paths:
      include: ["**/Domain/**/*.swift"]
      
  - id: business-imports-presentation
    pattern: |
      import SwiftUI
    languages: [swift]
    message: "Layer Violation: Business Logic must not import Presentation (SwiftUI)"
    severity: ERROR
    paths:
      include: ["**/BusinessLogic/**/*.swift"]
      
  - id: domain-depends-on-infrastructure
    pattern: |
      import OpenOats.Infrastructure
    languages: [swift]
    message: "Layer Violation: Domain must not import Infrastructure module"
    severity: ERROR
    paths:
      include: ["**/Domain/**/*.swift"]
```

**Running:**
```bash
# Install OpenGrep
brew install opengrep

# Create rules directory
mkdir -p .opengrep

# Write rules above to .opengrep/layer-violation.yaml

# Run check
opengrep scan --config .opengrep/layer-violation.yaml OpenOats/Sources/

# CI/CD with SARIF
opengrep scan --config .opengrep/ --sarif-output=results.sarif
```

---

## 6. Design Deliverables Checklist

| Deliverable | Task | Verification | Status |
|-------------|------|--------------|--------|
| Domain Entities (Meeting, Session, Transcript, Utterance) | TASK-001 | Check Entities/ folder | ✅ |
| Domain Error Types | TASK-002 | Check Errors/ folder | ✅ |
| Core Type Aliases | TASK-003 | Check Identifiers/ folder | ✅ |
| Presentation Layer Protocols | TASK-004 | Check protocols defined | ✅ |
| Business Logic (Use Cases) | TASK-005 | Check UseCases/ folder | ✅ |
| Infrastructure Layer Protocols | TASK-006 | Check Protocols/ folder | ✅ |
| Dependency Injection Strategy | TASK-007 | Check DI documentation | ✅ |
| Migration Strategy | TASK-008 | 9-week plan documented | ✅ |
| Data Flow Diagrams | TASK-009 | Mermaid diagrams complete | ✅ |
| Transcription Backend Abstraction | TASK-010 | Protocol hierarchy defined | ✅ |
| Swift 6.2 Concurrency Strategy | TASK-011 | Actor design complete | ✅ |
| Critical Data Race Fixes | TASK-015 | Actor conversion design | ✅ |
| Memory Management & OOM Prevention | TASK-016 | Streaming design | ✅ |
| Complexity Hotspot Reduction | TASK-017 | Command pattern design | ✅ |
| Performance & Latency Fixes | TASK-018 | Non-blocking design | ✅ |
| **Design Review Checklist** | **TASK-012** | **This document** | ✅ |
| **Acceptance Criteria** | **TASK-013** | Next task | ⏳ |
| **Design Validation Test Plan** | **TASK-014** | Next task | ⏳ |

---

## 7. Review Process

### Who Reviews

| Role | Responsibility |
|------|---------------|
| Lead Developer | Architecture review, Swift 6.2 concurrency |
| Senior iOS Engineer | Protocol design, layer boundaries |
| QA Lead | Test plan review, acceptance criteria |
| Product Owner | Feature coverage, user impact |

### How to Sign Off

1. **Self-Review:** Developer runs all SQL queries and OpenGrep rules
2. **Peer Review:** Another developer reviews design documents
3. **Lead Review:** Lead developer verifies architecture
4. **Sign-off Meeting:** 30-minute meeting with all stakeholders
5. **Approval:** Document signed in GitHub PR or Confluence

### Review Template

```markdown
## Design Review: OpenOats 3-Tier Architecture

**Review Date:** [DATE]
**Reviewers:** [NAMES]

### Architecture Review
- [ ] Layer responsibilities clear
- [ ] Dependencies flow inward only
- [ ] No circular dependencies (SQL verified)
- [ ] Domain has zero external deps

### Swift 6.2 Concurrency
- [ ] All Sendable conformance verified
- [ ] Actor isolation appropriate
- [ ] No @unchecked Sendable (or documented)
- [ ] Cancellation handling complete

### Code Quality
- [ ] High fan-out: 0 functions >8 calls
- [ ] Blast radius: 0 symbols >10 deps
- [ ] Critical blast: 0 symbols >25 deps
- [ ] Circular deps: 0 cycles
- [ ] God classes: 0 classes >15 methods
- [ ] Orphan symbols: documented/removed

### Final Verdict
[ ] APPROVED - Proceed to implementation
[ ] APPROVED WITH CHANGES - Document required changes
[ ] REJECTED - Major revisions needed

**Sign-off:**
Lead Developer: _________________ Date: _______
Product Owner: _________________ Date: _______
```

---

## 8. Metrics Baseline (Pre-Migration)

Run these queries on the existing codebase before migration:

```bash
#!/bin/bash
# baseline-metrics.sh - Run before migration starts

echo "=== Pre-Migration Baseline Metrics ==="
echo ""

echo "1. High fan-out functions (>8 calls):"
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.source_id = s.id AND e.kind = 'calls' GROUP BY s.id HAVING COUNT(e.id) > 8);"

echo "2. High blast radius symbols (>10 dependents):"
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.target_id = s.id GROUP BY s.id HAVING COUNT(e.id) > 10);"

echo "3. Critical blast radius (>25 dependents):"
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.target_id = s.id GROUP BY s.id HAVING COUNT(e.id) > 25);"

echo "4. Circular dependencies:"
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT DISTINCT s1.file, s2.file FROM edges e1 JOIN symbols s1 ON e1.source_id = s1.id JOIN symbols s2 ON e1.target_id = s2.id JOIN edges e2 ON e2.source_id = s2.id AND e2.target_id = s1.id WHERE e1.kind = 'imports');"

echo "5. Large classes (>15 methods):"
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT c.name FROM symbols c JOIN symbols m ON m.file = c.file WHERE c.kind = 'class' GROUP BY c.name HAVING COUNT(m.id) > 15);"

echo ""
echo "=== Record these values in TASK-012 ==="
```

---

## 9. Success Criteria (Post-Migration)

| Metric | Pre-Migration | Post-Migration Target | Verification |
|--------|--------------|----------------------|--------------|
| High fan-out (>8 calls) | TBD | 0 | SQL query |
| Blast radius (>10 deps) | TBD | 0 | SQL query |
| Critical blast (>25 deps) | TBD | 0 | SQL query |
| Circular dependencies | TBD | 0 | SQL query |
| Large classes (>15 methods) | TBD | 0 | SQL query |
| Orphan symbols | TBD | Documented/0 | SQL query |
| @unchecked Sendable | 2 (C1, C2) | 0 | OpenGrep |
| Data races | 2 | 0 | Thread sanitizer |
| CCN > 15 | 3 | 0 | Lizard |
| Files > 300 lines | 2 (NotesView, SessionRepo) | 0 | wc -l |

---

## 10. Tool Comparison Reference

| Metric | EEDOM (Primary) | OpenGrep Standalone (Quick) |
|--------|-----------------|------------------------------|
| **Blast Radius** | ✅ Exact SQL count | ❌ Not available |
| **Circular Deps** | ✅ Symbol-level SQL | ⚠️ File-level patterns |
| **Layer Violations** | ✅ SQL + OpenGrep | ✅ OpenGrep only |
| **God Functions** | ✅ Exact call graph | ⚠️ Pattern approximation |
| **Setup** | Database required | Single binary |
| **Speed** | Slower (full analysis) | Fast (patterns only) |
| **CI/CD** | ✅ SARIF output | ✅ SARIF output |

**Recommendation:**
- **Day-to-day:** Use standalone OpenGrep for quick validation
- **Deep analysis:** Use eedom SQL queries for metrics and trends
- **CI/CD:** Use either (eedom integrated or standalone OpenGrep)

---

## Formal Properties Verification

| Property | Status | Evidence |
|----------|--------|----------|
| INVARIANT: Design review checklist complete | ✅ | All 10 sections documented |
| SAFETY: AST hotpoint detection configured | ✅ | 6 SQL queries + OpenGrep rules |
| LIVENESS: All quality metrics show improvement | ⏳ | Run post-migration |
| INVARIANT: All items verifiable | ✅ | Each has yes/no or numeric target |

**Status**: Design deliverable complete, ready for review execution
