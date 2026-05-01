# OpenGrep Integration for OpenOats Architecture Validation

## Overview

**OpenGrep** is an open-source static code analysis engine (fork of Semgrep) that supports **30+ languages including Swift**. It can be used to enforce the 3-tier architecture rules and detect hotpoints automatically.

**Key Benefits:**
- ✅ **Swift Support** - Native Swift AST parsing
- ✅ **Custom Rules** - YAML-based pattern matching
- ✅ **CI/CD Integration** - JSON/SARIF output formats
- ✅ **Fast** - Analyzes large codebases quickly
- ✅ **Open Source** - LGPL 2.1 license (no commercial restrictions)

---

## Installation

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/opengrep/opengrep/main/install.sh | bash

# Or install via Homebrew (if available)
brew install opengrep

# Verify installation
opengrep --version
```

---

## Tool Hierarchy: EEDOM + OpenGrep

**Primary Tool: EEDOM** (has OpenGrep built-in)
- Full AST graph analysis (SQL queries)
- Integrated OpenGrep for pattern matching
- Best for comprehensive analysis and metrics

**Quick Tool: Standalone OpenGrep**
- Fast pattern-based validation
- No database setup required
- Best for quick CI/CD checks and pre-commit hooks

### Comparison

| Feature | EEDOM (Primary) | OpenGrep Standalone (Quick) |
|---------|-----------------|------------------------------|
| **AST Graph** | ✅ Full SQL analysis | ❌ Not available |
| **OpenGrep** | ✅ Built-in | ✅ Standalone |
| **Setup** | Database + indexing | Single binary install |
| **Speed** | Slower (full analysis) | Fast (pattern matching) |
| **Use Case** | Deep metrics, trends | Quick validation, CI/CD |
| **Swift Support** | ⚠️ Needs indexing | ✅ Native support |

**Workflow**:
1. **Development**: Use standalone OpenGrep for quick checks (`opengrep scan`)
2. **CI/CD**: Use eedom's integrated OpenGrep or standalone for blocking rules
3. **Metrics/Reports**: Use eedom SQL queries for precise measurements
4. **Migration Tracking**: Use eedom for baseline → target comparisons

---

## OpenGrep Rules for 3-Tier Architecture

### Rule 1: Layer Violation Detection

**File**: `.opengrep/layer-violation.yaml`

```yaml
rules:
  - id: domain-imports-infrastructure
    pattern: |
      import MLX
      import WhisperKit
      import AssemblyAI
    languages: [swift]
    message: "Layer Violation: Domain layer must not import infrastructure frameworks"
    severity: ERROR
    paths:
      include:
        - "**/Domain/**/*.swift"
    metadata:
      category: architecture
      technology: [swift]

  - id: business-imports-infrastructure
    pattern: |
      import MLX
      import WhisperKit
      import AssemblyAI
    languages: [swift]
    message: "Layer Violation: Business layer should import via protocols, not concrete implementations"
    severity: WARNING
    paths:
      include:
        - "**/Business/**/*.swift"
    metadata:
      category: architecture
      technology: [swift]
```

### Rule 2: God Function Detection (High Fan-Out)

**File**: `.opengrep/god-function.yaml`

```yaml
rules:
  - id: god-function-detection
    pattern: |
      func $FUNC(...) {
        $CALL1
        $CALL2
        $CALL3
        $CALL4
        $CALL5
        $CALL6
        $CALL7
        $CALL8
        ...
      }
    languages: [swift]
    message: "God Function: Function calls >8 other functions (SRP violation). Consider splitting into use cases."
    severity: WARNING
    metadata:
      category: maintainability
      technology: [swift]
      references:
        - https://en.wikipedia.org/wiki/Single-responsibility_principle
```

### Rule 3: Large Class Detection (SRP Violation)

**File**: `.opengrep/large-class.yaml`

```yaml
rules:
  - id: large-class-srp-violation
    pattern: |
      class $CLASS {
        func $M1(...)
        func $M2(...)
        func $M3(...)
        func $M4(...)
        func $M5(...)
        func $M6(...)
        func $M7(...)
        func $M8(...)
        func $M9(...)
        func $M10(...)
        func $M11(...)
        func $M12(...)
        func $M13(...)
        func $M14(...)
        func $M15(...)
        func $M16(...)
        ...
      }
    languages: [swift]
    message: "Large Class: Class has >15 methods (SRP violation). Consider decomposition."
    severity: WARNING
    metadata:
      category: maintainability
      technology: [swift]
```

### Rule 4: Force Unwrap Detection

**File**: `.opengrep/force-unwrap.yaml`

```yaml
rules:
  - id: force-unwrap-unsafe
    pattern: $VAR!
    languages: [swift]
    message: "Force unwrap detected - potential crash risk. Use guard let or if let."
    severity: ERROR
    metadata:
      category: safety
      technology: [swift]

  - id: force-try-unsafe
    pattern: try!
    languages: [swift]
    message: "Force try detected - potential crash risk. Use proper error handling."
    severity: ERROR
    metadata:
      category: safety
      technology: [swift]
```

### Rule 5: Protocol-Oriented Design Enforcement

**File**: `.opengrep/protocol-design.yaml`

```yaml
rules:
  - id: concrete-dependency-injection
    pattern: |
      class $CLASS {
        let $SERVICE: ConcreteService
      }
    languages: [swift]
    message: "Use protocol-based dependency injection instead of concrete types"
    severity: WARNING
    metadata:
      category: architecture
      technology: [swift]

  - id: singleton-anti-pattern
    pattern: |
      static let shared = $CLASS()
    languages: [swift]
    message: "Singleton pattern detected. Consider dependency injection for testability."
    severity: INFO
    metadata:
      category: testability
      technology: [swift]
```

### Rule 6: Swift 6.2 Concurrency Safety

**File**: `.opengrep/swift-concurrency.yaml`

```yaml
rules:
  - id: non-sendable-capture
    pattern: |
      Task {
        $VAR.mutatingMethod()
      }
    languages: [swift]
    message: "Potential data race: Captured variable may not be Sendable-safe"
    severity: ERROR
    metadata:
      category: concurrency
      technology: [swift]

  - id: mainactor-blocking
    pattern: |
      @MainActor
      func $FUNC(...) async {
        await longRunningOperation()
      }
    languages: [swift]
    message: "MainActor function performing blocking async work - may freeze UI"
    severity: WARNING
    metadata:
      category: concurrency
      technology: [swift]
```

---

## Running OpenGrep

### Local Development

```bash
# Scan entire project
opengrep scan --config .opengrep/ .

# Scan specific directory
opengrep scan --config .opengrep/layer-violation.yaml OpenOats/Sources/

# Output as JSON for CI integration
opengrep scan --config .opengrep/ --json OpenOats/Sources/ > opengrep-results.json

# Output as SARIF for GitHub integration
opengrep scan --config .opengrep/ --sarif-output=results.sarif OpenOats/Sources/

# Scan only changed files (git diff)
ogengrep scan --config .opengrep/ --diff-aware OpenOats/Sources/
```

### CI/CD Integration (GitHub Actions)

**File**: `.github/workflows/opengrep.yml`

```yaml
name: OpenGrep Analysis

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  opengrep:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install OpenGrep
        run: |
          curl -fsSL https://raw.githubusercontent.com/opengrep/opengrep/main/install.sh | bash
          echo "$HOME/.opengrep/bin" >> $GITHUB_PATH
      
      - name: Run OpenGrep
        run: |
          opengrep scan \
            --config .opengrep/ \
            --sarif-output=opengrep-results.sarif \
            --error \
            OpenOats/Sources/
      
      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: opengrep-results.sarif
        if: always()
```

---

## Pre-Commit Hook

**File**: `.pre-commit-config.yaml`

```yaml
repos:
  - repo: local
    hooks:
      - id: opengrep
        name: OpenGrep Architecture Check
        entry: opengrep scan --config .opengrep/ --error
        language: system
        files: \.swift$
        pass_filenames: false
```

---

## Integration with TASK-012 (Design Review Checklist)

### Updated Acceptance Criteria

Add to TASK-012:

```markdown
**OpenGrep Rule Validation:**
- [ ] OpenGrep installed and configured (`.opengrep/` directory)
- [ ] Layer violation rules active (Domain → Infrastructure imports)
- [ ] God function detection rules active (>8 calls)
- [ ] Large class detection rules active (>15 methods)
- [ ] Force unwrap detection rules active (ERROR severity)
- [ ] Protocol design rules active (concrete dependencies flagged)
- [ ] Swift 6.2 concurrency rules active (Sendable safety)
- [ ] CI/CD pipeline runs OpenGrep on PRs
- [ ] Pre-commit hooks block commits with ERROR severity findings

**OpenGrep Success Criteria:**
- [ ] Zero ERROR severity findings in migrated code
- [ ] Zero layer violations in protocol graph
- [ ] Zero force unwraps in production code
- [ ] All WARNING findings documented with justification
```

---

## Integration with TEST-PLAN.md (TC-011)

### Updated TC-011: AST-Based Hotpoint Detection

Add OpenGrep as complementary tool:

```markdown
**OpenGrep Validation:**
Run OpenGrep rules to enforce architectural patterns:

```bash
# Layer violations
opengrep scan --config .opengrep/layer-violation.yaml

# God functions
opengrep scan --config .opengrep/god-function.yaml

# Large classes
opengrep scan --config .opengrep/large-class.yaml
```

**Pass Criteria:**
- ✅ Zero layer violations (Domain importing Infrastructure)
- ✅ Zero force unwraps in production code
- ✅ All god functions flagged for refactoring
- ✅ All large classes flagged for decomposition
```

---

## Comparison: OpenGrep vs SQL AST Queries

| Metric | OpenGrep (Pattern Matching) | EEDOM (SQL AST Queries) |
|--------|------------------------------|-------------------------|
| **Layer Violations** | ✅ Can detect imports | ✅ Can detect imports |
| **God Functions** | ⚠️ Approximate (pattern) | ✅ Exact (call graph) |
| **Blast Radius** | ❌ Cannot measure | ✅ Exact (dependency count) |
| **Circular Deps** | ⚠️ File-level only | ✅ Symbol-level analysis |
| **Large Classes** | ⚠️ Approximate (pattern) | ✅ Exact (method count) |
| **Dead Code** | ❌ Cannot detect | ✅ Orphan symbol detection |

**Recommendation**: Use **OpenGrep for enforcement** (CI/CD blocking) and **EEDOM for metrics** (trends, reports).

---

## Action Items

1. **Install OpenGrep** locally for development
2. **Create `.opengrep/` directory** with rule files
3. **Run baseline scan** on current codebase to measure violations
4. **Set up CI/CD** integration (GitHub Actions)
5. **Configure pre-commit hooks** to catch issues early
6. **Document findings** in TASK-012 baseline metrics

---

## References

- **OpenGrep**: https://github.com/opengrep/opengrep
- **Documentation**: https://github.com/opengrep/opengrep/wiki
- **Swift Support**: Included in 30+ languages
- **Rule Syntax**: https://semgrep.dev/docs/writing-rules/overview

---

**Conclusion**: OpenGrep provides an excellent **enforcement layer** for our 3-tier architecture rules, complementing the **measurement capabilities** of EEDOM/GitNexus AST analysis. Use both tools together for comprehensive architecture validation.
