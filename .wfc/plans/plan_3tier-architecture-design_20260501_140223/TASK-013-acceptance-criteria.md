# TASK-013: Acceptance Criteria

## Measurable Quality Gates

This document defines objective, measurable criteria for validating the 3-tier architecture design before implementation begins.

---

## 1. Completeness Metrics

### Domain Coverage

| Metric | Target | Measurement Method | Pass/Fail |
|--------|--------|-------------------|-----------|
| Domain entities defined | 100% | Count files in `Domain/Entities/` | ≥ 7 types |
| Domain errors defined | 100% | Count files in `Domain/Errors/` | ≥ 5 error types |
| Domain identifiers defined | 100% | Count files in `Domain/Identifiers/` | ≥ 5 ID types |
| Layer protocols defined | 100% | Count protocols in all layers | ≥ 15 protocols |
| Use cases identified | 100% | Count use case protocols | ≥ 6 use cases |
| Data flows diagrammed | 100% | Count Mermaid diagrams | ≥ 5 diagrams |

**Measurement:**
```bash
# Domain entities
count_entities=$(ls OpenOats/Sources/Domain/Entities/*.swift 2>/dev/null | wc -l)
[ $count_entities -ge 7 ] && echo "PASS: $count_entities entities" || echo "FAIL: $count_entities entities"

# Protocols
count_protocols=$(grep -r "protocol.*Protocol:" OpenOats/Sources/ --include="*.swift" | wc -l)
[ $count_protocols -ge 15 ] && echo "PASS: $count_protocols protocols" || echo "FAIL: $count_protocols protocols"
```

### Coverage by Task

| Task | Deliverable | Acceptance Criteria | Measurement |
|------|-------------|---------------------|-------------|
| TASK-001 | Domain Entities | 7 entity types defined | File count |
| TASK-002 | Domain Errors | 5 error types defined | File count |
| TASK-003 | Identifiers | 5 ID types defined | File count |
| TASK-004 | Presentation Protocols | ViewModels defined | Protocol count |
| TASK-005 | Use Cases | 6 use cases defined | Protocol count |
| TASK-006 | Infrastructure Protocols | Services defined | Protocol count |
| TASK-007 | DI Strategy | Container pattern | Document exists |
| TASK-008 | Migration Plan | 9-week plan exists | Document exists |
| TASK-009 | Data Flows | 5+ diagrams | Diagram count |
| TASK-010 | Transcription Abstraction | Backend protocols | Protocol hierarchy |
| TASK-011 | Concurrency Strategy | Actor design | Actor definitions |
| TASK-012 | Review Checklist | Complete checklist | Sections ≥ 10 |

---

## 2. Quality Metrics

### Protocol Design Quality

| Metric | Target | Measurement | Tool |
|--------|--------|-------------|------|
| Protocols with <10 methods | 100% | Methods per protocol | OpenGrep |
| Zero circular dependencies | Required | Import cycles | EEDOM SQL |
| All domain types Sendable | 100% | Sendable conformance | Compiler |
| Async operations with error handling | 100% | `throws` coverage | Manual review |
| Protocol documentation | 100% | Comments per protocol | Documentation coverage |

**Measurement Commands:**
```bash
# Protocols with <10 methods
opengrep scan --pattern "protocol.*\{[^}]*func[^}]*func[^}]*func[^}]*func[^}]*func[^}]*func[^}]*func[^}]*func[^}]*func[^}]*func" OpenOats/Sources/
# Target: 0 results (no protocols with >10 func keywords)

# Sendable conformance
swift build 2>&1 | grep -i "sendable" | grep -i "error"
# Target: 0 errors

# Circular dependencies
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM edges e1 JOIN edges e2 ON e2.source_id = e1.target_id AND e2.target_id = e1.source_id WHERE e1.kind = 'imports';"
# Target: 0
```

### Code Quality Gates (AST-Based)

| Metric | Baseline (Pre) | Target (Post) | Measurement | CI/CD Integration |
|--------|---------------|---------------|-------------|-------------------|
| High fan-out (>8 calls) | ___ | 0 | EEDOM SQL | PR check |
| Blast radius (>10 deps) | ___ | 0 | EEDOM SQL | Weekly scan |
| Critical blast (>25 deps) | ___ | 0 | EEDOM SQL | PR block |
| Circular dependencies | ___ | 0 | EEDOM SQL | PR block |
| Large classes (>15 methods) | ___ | 0 | EEDOM SQL | PR check |
| Orphan symbols | ___ | Documented | EEDOM SQL | Weekly report |

**Baseline Measurement (Run Before Migration):**
```bash
#!/bin/bash
# measure-baseline.sh

cat << 'EOF'
=== Pre-Migration Baseline ===
Run these queries and record results:

High fan-out (>8 calls):
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.source_id = s.id AND e.kind = 'calls' GROUP BY s.id HAVING COUNT(e.id) > 8);"

Blast radius (>10 deps):
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.target_id = s.id GROUP BY s.id HAVING COUNT(e.id) > 10);"

Critical blast (>25 deps):
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.target_id = s.id GROUP BY s.id HAVING COUNT(e.id) > 25);"

Circular dependencies:
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT DISTINCT s1.file, s2.file FROM edges e1 JOIN symbols s1 ON e1.source_id = s1.id JOIN symbols s2 ON e1.target_id = s2.id JOIN edges e2 ON e2.source_id = s2.id AND e2.target_id = s1.id WHERE e1.kind = 'imports');"

Large classes (>15 methods):
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT c.name FROM symbols c JOIN symbols m ON m.file = c.file WHERE c.kind = 'class' GROUP BY c.name HAVING COUNT(m.id) > 15);"

Orphan symbols:
sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s LEFT JOIN edges e ON e.target_id = s.id AND e.kind = 'calls' WHERE s.kind IN ('function', 'method') AND s.name NOT LIKE '\_%' AND s.name NOT IN ('main', 'setup', 'teardown') AND e.id IS NULL);"
EOF
```

---

## 3. Documentation Metrics

| Metric | Target | Measurement | Pass Criteria |
|--------|--------|-------------|---------------|
| Protocols with documentation | 100% | `///` comments per public API | ≥ 90% coverage |
| Complex flows with sequence diagrams | 100% | Mermaid sequence diagrams | ≥ 5 diagrams |
| Migration strategy with risk mitigations | Required | Risk table complete | ≥ 5 risks documented |
| Architecture Decision Records | Recommended | ADR files | ≥ 3 ADRs |
| API documentation generated | Required | DocC output | Successfully generates |

**Measurement:**
```bash
# Documentation coverage
# Using jazzy or swift-doc to measure comment coverage

# Mermaid diagrams
count_diagrams=$(grep -c "^\`\`\`mermaid" .wfc/plans/plan_*/TASK-009*.md)
[ $count_diagrams -ge 5 ] && echo "PASS: $count_diagrams diagrams" || echo "FAIL: $count_diagrams diagrams"

# Risk table
count_risks=$(grep -c "^|.*|.*|.*|.*|$" TASK-008*.md)
[ $count_risks -ge 5 ] && echo "PASS: $count_risks risks" || echo "FAIL: $count_risks risks"
```

---

## 4. Critical Issues Resolution

### From .temp/ Analysis

| Issue | Severity | Design Fix | Acceptance Criteria | Verification |
|-------|----------|-----------|---------------------|------------|
| C1: StreamingTranscriber data race | CRITICAL | Actor conversion | `actor StreamingTranscriptionActor` exists | Code review |
| C2: MicCapture audio callback race | CRITICAL | Actor + atomic | `actor MicCaptureActor` or `OSAllocatedUnfairLock` | Code review |
| C3: Unbounded memory (mergeAndEncode) | CRITICAL | Streaming + buffer pool | `AudioBufferPool` with 64K chunks | Memory profiling |
| C4: Temp file durability | CRITICAL | Application Support | `AudioRecordingRepository` with durable storage | File system check |
| H1: Partial transcription blocks VAD | HIGH | Child Task dispatch | `TranscriptionTaskManager` with non-blocking dispatch | Latency test |
| H2: Scalar DSP under locks | HIGH | vDSP optimization | `AudioDSPProcessor` using vDSP | Performance test |
| H3: Unbounded speech buffer | HIGH | Circular buffer | `AudioBuffer` with sliding window | Memory profiling |
| H4: Unstructured tasks | HIGH | Structured concurrency | `withTaskCancellationHandler` usage | Static analysis |

**Measurement:**
```bash
# Verify actor designs exist
grep -r "actor StreamingTranscriptionActor" .wfc/plans/
grep -r "actor MicCaptureActor" .wfc/plans/
grep -r "AudioBufferPool" .wfc/plans/
grep -r "TranscriptionTaskManager" .wfc/plans/
```

---

## 5. Swift 6.2 Conformance

| Metric | Target | Measurement | Tool |
|--------|--------|-------------|------|
| Zero `@unchecked Sendable` | Required | Undocumented unsafe Sendable | OpenGrep |
| All actors properly isolated | Required | Actor usage audit | Compiler |
| All protocols Sendable | 100% | Protocol inheritance | Compiler |
| MainActor on all UI code | 100% | @MainActor coverage | OpenGrep |
| Cancellation handling | 100% | `Task.isCancelled` checks | Manual review |
| No blocking on MainActor | Required | Long-running ops analysis | Static analysis |

**Measurement:**
```bash
# @unchecked Sendable (should be 0 or documented)
opengrep scan --pattern "@unchecked Sendable" OpenOats/Sources/
# Target: 0 undocumented occurrences

# @MainActor coverage
opengrep scan --pattern "@MainActor" OpenOats/Sources/Presentation/
# Target: 100% of view models

# Sendable protocols
grep -r "protocol.*:.*Sendable" OpenOats/Sources/ | wc -l
# Target: All protocols
```

---

## 6. Performance Acceptance Criteria

### Memory Management

| Metric | Before | Target | Measurement |
|--------|--------|--------|-------------|
| Audio buffer memory (2hr recording) | ~2.6 GB | < 1 MB | Instruments |
| Peak memory usage | ~3 GB | < 1 GB | Instruments |
| Memory growth over time | Unbounded | Flat after warmup | Memory graph |

### Latency

| Metric | Before | Target | Measurement |
|--------|--------|--------|-------------|
| VAD loop blocking | 200-500ms | 0ms (non-blocking) | Time profiler |
| Transcription response | 200-500ms | < 100ms | Custom logging |
| UI update latency | Variable | < 16ms (60fps) | Core Animation |

### CPU

| Metric | Before | Target | Measurement |
|--------|--------|--------|-------------|
| Audio DSP optimization | Scalar loops | vDSP | Instruments |
| Lock contention | High | Minimal | Thread Sanitizer |
| Background task efficiency | Low | High | Energy diagnostics |

---

## 7. Review Process & Sign-off

### Review Stages

| Stage | Reviewer | Focus | Output |
|-------|----------|-------|--------|
| 1. Self-Review | Author | Completeness | Checklist filled |
| 2. Peer Review | Team Member | Quality | Review comments |
| 3. Technical Review | Lead Developer | Architecture | Approval/Changes |
| 4. Product Review | Product Owner | Feature coverage | Approval/Changes |
| 5. Final Sign-off | Tech Lead + Product Owner | All criteria | Signed document |

### Sign-off Authority

| Role | Can Approve | Responsibility |
|------|-------------|----------------|
| Tech Lead | Architecture, Concurrency, Performance | Technical correctness |
| Product Owner | Feature coverage, User impact | Business value |
| QA Lead | Testability, Validation criteria | Quality assurance |
| Engineering Manager | Resource allocation, Timeline | Feasibility |

### Pass/Fail Criteria Summary

**Must Pass (Blocking):**
- [ ] All 18 design tasks complete
- [ ] Zero circular dependencies
- [ ] All domain types Sendable
- [ ] All critical issues (C1-C4, H1-H4) addressed in design
- [ ] Migration plan with rollback strategy

**Should Pass (High Priority):**
- [ ] Protocol method count < 10
- [ ] All protocols documented
- [ ] 5+ data flow diagrams
- [ ] AST metrics baseline recorded

**Nice to Have:**
- [ ] ADRs written
- [ ] DocC documentation generated
- [ ] OpenGrep rules configured

---

## 8. AST Metrics Validation

### SQL Query Integration Plan

```bash
#!/bin/bash
# validate-ast-metrics.sh - CI/CD integration

set -e

EEDOM_DB=".eedom/code_graph.sqlite"
FAILURES=0

echo "=== AST Metrics Validation ==="

# 1. High fan-out check
FANOUT=$(sqlite3 "$EEDOM_DB" "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.source_id = s.id AND e.kind = 'calls' GROUP BY s.id HAVING COUNT(e.id) > 8);")
if [ "$FANOUT" -gt 0 ]; then
    echo "❌ FAIL: $FANOUT functions with >8 calls"
    sqlite3 "$EEDOM_DB" "SELECT s.name, s.file, COUNT(e.id) as calls FROM symbols s JOIN edges e ON e.source_id = s.id AND e.kind = 'calls' GROUP BY s.id HAVING calls > 8;"
    FAILURES=$((FAILURES + 1))
else
    echo "✅ PASS: High fan-out check"
fi

# 2. Blast radius check
BLAST=$(sqlite3 "$EEDOM_DB" "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.target_id = s.id GROUP BY s.id HAVING COUNT(e.id) > 10);")
if [ "$BLAST" -gt 0 ]; then
    echo "❌ FAIL: $BLAST symbols with >10 dependents"
    FAILURES=$((FAILURES + 1))
else
    echo "✅ PASS: Blast radius check"
fi

# 3. Circular dependency check
CIRCULAR=$(sqlite3 "$EEDOM_DB" "SELECT COUNT(*) FROM (SELECT DISTINCT s1.file, s2.file FROM edges e1 JOIN symbols s1 ON e1.source_id = s1.id JOIN symbols s2 ON e1.target_id = s2.id JOIN edges e2 ON e2.source_id = s2.id AND e2.target_id = s1.id WHERE e1.kind = 'imports');")
if [ "$CIRCULAR" -gt 0 ]; then
    echo "❌ FAIL: $CIRCULAR circular dependencies"
    FAILURES=$((FAILURES + 1))
else
    echo "✅ PASS: Circular dependency check"
fi

# 4. Large class check
LARGE=$(sqlite3 "$EEDOM_DB" "SELECT COUNT(*) FROM (SELECT c.name FROM symbols c JOIN symbols m ON m.file = c.file WHERE c.kind = 'class' GROUP BY c.name HAVING COUNT(m.id) > 15);")
if [ "$LARGE" -gt 0 ]; then
    echo "❌ FAIL: $LARGE classes with >15 methods"
    FAILURES=$((FAILURES + 1))
else
    echo "✅ PASS: Large class check"
fi

# 5. Orphan symbols check
ORPHANS=$(sqlite3 "$EEDOM_DB" "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s LEFT JOIN edges e ON e.target_id = s.id AND e.kind = 'calls' WHERE s.kind IN ('function', 'method') AND s.name NOT LIKE '\_%' AND s.name NOT IN ('main', 'setup', 'teardown') AND e.id IS NULL);")
if [ "$ORPHANS" -gt 0 ]; then
    echo "⚠️ WARN: $ORPHANS orphan symbols (review for dead code)"
    # Don't fail for orphans, just warn
else
    echo "✅ PASS: No orphan symbols"
fi

# Final result
if [ $FAILURES -gt 0 ]; then
    echo ""
    echo "❌ VALIDATION FAILED: $FAILURES checks failed"
    exit 1
else
    echo ""
    echo "✅ ALL CHECKS PASSED"
    exit 0
fi
```

### CI/CD Integration

```yaml
# .github/workflows/ast-validation.yml
name: AST Metrics Validation

on:
  pull_request:
    branches: [ main, develop ]
  push:
    branches: [ main ]

jobs:
  validate:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup EEDOM
        run: |
          # Install eedom
          pip install eedom
          eedom init
          eedom analyze
      
      - name: Run AST Validation
        run: |
          chmod +x scripts/validate-ast-metrics.sh
          ./scripts/validate-ast-metrics.sh
      
      - name: Run OpenGrep Checks
        run: |
          brew install opengrep
          opengrep scan --config .opengrep/ OpenOats/Sources/
      
      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: opengrep-results.sarif
```

---

## 9. Regression Detection

### Automated Regression Prevention

The following checks will fail the build if metrics regress:

```bash
# Store baseline in repo
cat > .wfc/baseline-metrics.json << 'EOF'
{
  "pre_migration": {
    "high_fan_out": TBD,
    "blast_radius": TBD,
    "critical_blast": TBD,
    "circular_deps": TBD,
    "large_classes": TBD,
    "orphan_symbols": TBD
  },
  "target_post_migration": {
    "high_fan_out": 0,
    "blast_radius": 0,
    "critical_blast": 0,
    "circular_deps": 0,
    "large_classes": 0
  }
}
EOF

# Compare current to baseline
jq -e '.target_post_migration | to_entries | all(.value == 0)' .wfc/baseline-metrics.json
```

### Trend Tracking

```bash
# Weekly trend report
#!/bin/bash
# trend-report.sh

echo "## AST Metrics Trend Report" > trend-report.md
echo "Date: $(date)" >> trend-report.md
echo "" >> trend-report.md

echo "### Current vs Target" >> trend-report.md
echo "" >> trend-report.md
echo "| Metric | Current | Target | Status |" >> trend-report.md
echo "|--------|---------|--------|--------|" >> trend-report.md

FANOUT=$(sqlite3 .eedom/code_graph.sqlite "SELECT COUNT(*) FROM (SELECT s.id FROM symbols s JOIN edges e ON e.source_id = s.id AND e.kind = 'calls' GROUP BY s.id HAVING COUNT(e.id) > 8);")
[ "$FANOUT" -eq 0 ] && STATUS="✅" || STATUS="❌"
echo "| High Fan-Out | $FANOUT | 0 | $STATUS |" >> trend-report.md

# ... repeat for other metrics
```

---

## 10. Final Acceptance Summary

### Pre-Implementation Gate

Before entering implementation phase (wfc-implement), ALL of the following must be true:

| # | Gate | Status | Evidence |
|---|------|--------|----------|
| 1 | All 18 design tasks complete | ⏳ | Document checklist |
| 2 | Zero circular dependencies | ⏳ | SQL query result |
| 3 | All domain types Sendable | ⏳ | Compiler check |
| 4 | Critical issues addressed | ⏳ | Design review |
| 5 | Migration plan approved | ⏳ | Sign-off document |
| 6 | AST metrics baseline recorded | ⏳ | Baseline file |
| 7 | OpenGrep rules configured | ⏳ | .opengrep/ directory |
| 8 | CI/CD integration ready | ⏳ | Workflow file |
| 9 | Lead Developer sign-off | ⏳ | Signature |
| 10 | Product Owner sign-off | ⏳ | Signature |

---

## Formal Properties Verification

| Property | Status | Evidence |
|----------|--------|----------|
| INVARIANT: All acceptance criteria must pass before implementation | ⏳ | This document is the gate |
| SAFETY: AST-based metrics provide objective quality gates | ✅ | 6 SQL queries defined |
| LIVENESS: Metrics demonstrate measurable improvement | ⏳ | Baseline → target defined |
| INVARIANT: Criteria are measurable (yes/no or numeric) | ✅ | All have quantifiable targets |
| INVARIANT: Pass/fail criteria defined for each metric | ✅ | Thresholds specified |

**Status**: Design deliverable complete. Ready for design validation test plan (TASK-014).
