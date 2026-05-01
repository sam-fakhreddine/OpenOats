# OpenOats Architecture Validation Tools Summary

## Tool Stack Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    PRIMARY TOOL: EEDOM                      │
│  (Full AST analysis + OpenGrep built-in + SQL metrics)      │
│                                                             │
│  • SQL queries for exact metrics (blast radius, coupling)  │
│  • Integrated OpenGrep for pattern matching                 │
│  • Database-backed for trend tracking                      │
│  • Best for: Migration tracking, deep analysis            │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ (has built-in)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              QUICK TOOL: Standalone OpenGrep                │
│         (Pattern matching without database)               │
│                                                             │
│  • Fast YAML-based rules                                   │
│  • No setup required (single binary)                       │
│  • CI/CD friendly (SARIF output)                          │
│  • Best for: Quick checks, pre-commit hooks, CI blocking    │
└─────────────────────────────────────────────────────────────┘
```

---

## When to Use Each Tool

### **Use EEDOM (Primary) When:**
- ✅ Measuring exact blast radius (how many dependents)
- ✅ Tracking coupling trends over time
- ✅ Finding circular dependencies at symbol level
- ✅ Detecting dead code (orphan symbols)
- ✅ Migration baseline → target comparisons
- ✅ Comprehensive architecture reports

**Example:**
```bash
# Index codebase
eedom index OpenOats/Sources/

# Run SQL query for exact blast radius
sqlite3 .eedom/code_graph.sqlite "SELECT s.name, COUNT(e.id) as deps 
FROM symbols s JOIN edges e ON e.target_id = s.id 
GROUP BY s.id HAVING deps > 10;"
```

### **Use Standalone OpenGrep (Quick) When:**
- ✅ Quick validation during development
- ✅ CI/CD blocking (fast feedback)
- ✅ Pre-commit hooks (no DB dependency)
- ✅ Layer violation detection (import patterns)
- ✅ Force unwrap detection
- ✅ Quick pattern matching without setup

**Example:**
```bash
# Install once
brew install opengrep

# Run anytime (no database needed)
opengrep scan --config .opengrep/layer-violation.yaml OpenOats/Sources/
```

---

## Workflow Recommendations

### **Daily Development Workflow:**
```bash
# 1. Quick validation before commit (OpenGrep - fast)
opengrep scan --config .opengrep/ OpenOats/Sources/

# 2. Fix any layer violations or force unwraps

# 3. Commit and push
```

### **Weekly Architecture Review:**
```bash
# 1. Deep analysis (EEDOM - comprehensive)
eedom index OpenOats/Sources/
eedom analyze --report

# 2. Review metrics
# - High fan-out functions
# - Blast radius trends
# - Circular dependencies

# 3. Update migration plan based on metrics
```

### **CI/CD Pipeline:**
```yaml
# Option A: Standalone OpenGrep (fast, no DB)
- opengrep scan --config .opengrep/ --error

# Option B: EEDOM integrated (if already set up)
- eedom scan --opengrep-rules .opengrep/
```

---

## Capabilities Matrix

| Capability | EEDOM | OpenGrep Standalone | Notes |
|------------|-------|---------------------|-------|
| **Layer Violations** | ✅ SQL + OpenGrep | ✅ OpenGrep | Both detect Domain→Infra imports |
| **Blast Radius** | ✅ Exact count | ❌ N/A | SQL: `COUNT(e.id)` |
| **Circular Deps** | ✅ Symbol-level | ⚠️ File-level | SQL: Self-join on edges |
| **God Functions** | ✅ Exact calls | ⚠️ Pattern | SQL: `e.kind = 'calls'` |
| **Large Classes** | ✅ Method count | ⚠️ Pattern | SQL: `COUNT(*) > 15` |
| **Dead Code** | ✅ Orphan symbols | ❌ N/A | SQL: `LEFT JOIN edges` |
| **Force Unwraps** | ✅ OpenGrep | ✅ OpenGrep | Pattern: `$VAR!` |
| **Setup Time** | ⚠️ Minutes | ✅ Seconds | DB indexing vs single binary |
| **CI/CD Speed** | ⚠️ Slower | ✅ Fast | Full analysis vs patterns |
| **Trend Tracking** | ✅ Database | ❌ Stateless | Historical comparisons |

---

## File Structure

```
OpenOats/
├── .eedom/                          # EEDOM database (created by tool)
│   └── code_graph.sqlite            # AST graph database
│
├── .opengrep/                       # OpenGrep rules (we create)
│   ├── layer-violation.yaml         # Domain→Infra import detection
│   ├── force-unwrap.yaml            # Force unwrap/try detection
│   ├── god-function.yaml            # High fan-out approximation
│   ├── large-class.yaml             # SRP violation detection
│   └── protocol-design.yaml         # Concrete dependency detection
│
├── .github/
│   └── workflows/
│       └── opengrep.yml             # CI/CD workflow (uses either tool)
│
└── .wfc/
    └── references/
        ├── eedom-code-graph-analysis.md      # SQL queries documentation
        ├── opengrep-integration.md           # OpenGrep setup guide
        └── opengrep-rules/                   # Example rule files
            ├── layer-violation.yaml
            ├── force-unwrap.yaml
            └── ...
```

---

## Quick Start Commands

### **EEDOM (Primary - Full Analysis):**
```bash
# Install (if not already)
# (Assuming eedom is installed)

# Index codebase
eedom index OpenOats/Sources/

# Run SQL queries
sqlite3 .eedom/code_graph.sqlite "SELECT * FROM checks;"

# Generate report
eedom analyze --format markdown --output architecture-report.md
```

### **OpenGrep Standalone (Quick - Pattern Matching):**
```bash
# Install
brew install opengrep

# Create rules
mkdir -p .opengrep
cat > .opengrep/layer-violation.yaml << 'EOF'
rules:
  - id: domain-imports-infrastructure
    pattern: |
      import MLX
    languages: [swift]
    message: "Layer violation detected"
    severity: ERROR
    paths:
      include: ["**/Domain/**/*.swift"]
EOF

# Run
opengrep scan --config .opengrep/ OpenOats/Sources/

# CI/CD with blocking
opengrep scan --config .opengrep/ --error OpenOats/Sources/
```

---

## Success Criteria Summary

### **EEDOM Success Metrics (SQL-based):**
- [ ] Zero symbols with >10 dependents (blast radius)
- [ ] Zero functions with >8 calls (god functions)
- [ ] Zero circular dependencies (import cycles)
- [ ] All classes have <15 methods (SRP)
- [ ] All orphan symbols documented (dead code)

### **OpenGrep Success Metrics (Pattern-based):**
- [ ] Zero layer violations (Domain importing Infrastructure)
- [ ] Zero force unwraps in production code
- [ ] Zero force try in production code
- [ ] All concrete dependencies flagged (should use protocols)

---

## Integration with Design Plan

### **TASK-012: Design Review Checklist**
- ✅ EEDOM SQL queries documented (6 hotpoint detectors)
- ✅ OpenGrep rules documented (5 rule categories)
- ✅ Tool hierarchy defined (EEDOM primary, OpenGrep quick)
- ✅ CI/CD integration plan for both tools

### **TASK-013: Acceptance Criteria**
- ✅ EEDOM metrics: Baseline vs target documented
- ✅ OpenGrep metrics: Zero violations target
- ✅ Both tools: CI/CD integration defined

### **TEST-PLAN.md: TC-011**
- ✅ EEDOM SQL validation steps
- ✅ OpenGrep pattern validation steps
- ✅ Comparison matrix documented
- ✅ Workflow recommendations

---

## Next Steps

1. **Install Tools:**
   - EEDOM (primary) - already installed
   - OpenGrep standalone: `brew install opengrep`

2. **Create OpenGrep Rules:**
   - Copy examples from `.wfc/references/opengrep-integration.md`
   - Customize for OpenOats specific patterns

3. **Run Baseline Analysis:**
   - EEDOM: Index and run SQL queries
   - OpenGrep: Run rules on current codebase
   - Document findings in TASK-012

4. **Set Up CI/CD:**
   - GitHub Actions workflow
   - Pre-commit hooks (optional)

5. **Track Migration:**
   - Re-run analysis after each migration phase
   - Compare baseline → current → target

---

## References

- **EEDOM Analysis**: `.wfc/references/eedom-code-graph-analysis.md`
- **OpenGrep Integration**: `.wfc/references/opengrep-integration.md`
- **Design Plan**: `.wfc/plans/plan_3tier-architecture-design_*/TASKS.md`
- **Test Plan**: `.wfc/plans/plan_3tier-architecture-design_*/TEST-PLAN.md`

---

**Summary**: Use **EEDOM** for deep metrics and migration tracking, **OpenGrep standalone** for quick validation and CI/CD blocking. Both tools together provide comprehensive architecture validation.
