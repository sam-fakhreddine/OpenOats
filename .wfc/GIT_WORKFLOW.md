# Git Workflow: OpenOats 3-Tier Architecture

**Effective Date**: 2026-05-01  
**Owner**: VP of Engineering  
**Status**: ACTIVE

---

## Core Principles

1. **NO SQUASH EVER** — Preserve full commit history
2. **REBASE TO MAIN ONLY** — Linear history, no merge commits
3. **WORKTREE PARALLEL DEVELOPMENT** — Isolated branches, simultaneous work
4. **CONVENTIONAL COMMITS** — `fix/`, `perf/`, `refactor/`, `feat/`

---

## Branch Structure

```
main (upstream yazinsai/OpenOats)
  │
  └── feat!/3tier-clean-architecture (integration branch on fork)
        │
        ├── fix/swift6-compilation-errors  ← Slice 1 (MERGED)
        ├── fix/security-url-injection-keys  ← Slice 2 (READY)
        ├── perf/vdsp-circular-buffer  ← Slice 3 (READY)
        └── refactor/complexity-ccn-reduction  ← Slice 4 (READY)
```

---

## Workflow Rules

### 1. NEVER SQUASH

```bash
# ❌ FORBIDDEN
git merge --squash ...
git rebase -i (with squash)

# ✅ REQUIRED
git merge --no-ff --no-squash ...
git rebase main (linear history)
```

### 2. REBASE TO MAIN ONLY

```bash
# When integrating to main:
git checkout feat!/3tier-clean-architecture
git rebase origin/main
git push fork feat!/3tier-clean-architecture --force-with-lease

# Then PR to upstream:
gh pr create --base main --head feat!/3tier-clean-architecture
```

### 3. WORKTREE DEVELOPMENT

```bash
# Create worktree for parallel development
git worktree add .worktrees/fix-swift6 fix/swift6-compilation-errors

# Work in isolation
cd .worktrees/fix-swift6
# ... make changes ...
git commit -m "fix: ..."

# Push to fork
git push fork fix/swift6-compilation-errors
```

### 4. SLICE MERGE SEQUENCE

| Order | Branch | Status | Merge Command |
|-------|--------|--------|---------------|
| 1 | `fix/swift6-compilation-errors` | ✅ MERGED | `git merge --no-ff --no-squash` |
| 2 | `fix/security-url-injection-keys` | 🔄 READY | `git merge --no-ff --no-squash` |
| 3 | `perf/vdsp-circular-buffer` | 🔄 READY | `git merge --no-ff --no-squash` |
| 4 | `refactor/complexity-ccn-reduction` | 🔄 READY | `git merge --no-ff --no-squash` |

---

## Merge Commands (Copy-Paste)

### Merge Slice to Integration Branch

```bash
# 1. Checkout integration branch
git checkout feat!/3tier-clean-architecture

# 2. Merge slice (NO SQUASH)
git merge --no-ff --no-squash fix/security-url-injection-keys

# 3. Verify no squash happened
git log --oneline --graph -10

# 4. Push to fork
git push fork feat!/3tier-clean-architecture
```

### Rebase Integration to Main

```bash
# 1. Fetch latest main
git fetch origin main

# 2. Checkout integration
git checkout feat!/3tier-clean-architecture

# 3. Rebase onto main (LINEAR HISTORY)
git rebase origin/main

# 4. Force push (safe with lease)
git push fork feat!/3tier-clean-architecture --force-with-lease

# 5. Create PR to upstream
gh pr create --repo yazinsai/OpenOats \
  --base main \
  --head sam-fakhreddine:feat!/3tier-clean-architecture \
  --title "feat!: 3-tier Clean Architecture with Swift 6 compliance"
```

---

## Tracking Dashboard

### Current State (2026-05-01)

| Slice | Branch | Commit | Status | Tests | Review |
|-------|--------|--------|--------|-------|--------|
| Swift 6 Compilation | `fix/swift6-compilation-errors` | `48c5e47` | ✅ MERGED | Pass | Approved |
| Security Fixes | `fix/security-url-injection-keys` | `4fe5d4a` | 🔄 READY | Pass | Pending |
| Performance | `perf/vdsp-circular-buffer` | `b176508` | 🔄 READY | Pass | Pending |
| Complexity | `refactor/complexity-ccn-reduction` | `59131cc` | 🔄 READY | Pass | Pending |

### Integration Branch Status

```bash
# Check current integration state
git checkout feat!/3tier-clean-architecture
git log --oneline --graph -20

# Verify no squash in history
git log --oneline --merges -10  # Should show merge commits with full history
```

---

## Commit Message Format

```
<type>(<scope>): <subject>

<body>

Fixes: <issue numbers>
Refs: <related PRs>
```

### Types
- `fix/` — Bug fixes, compilation errors, security issues
- `perf/` — Performance optimizations
- `refactor/` — Code restructuring, complexity reduction
- `feat/` — New features (rare in this workflow)

### Examples

```
fix(swift6): resolve 7 compilation errors in TranscriptionEngine

- Change let to var for mutable actor state
- Create FluidVadManager actor for protocol instantiation
- Create SyncDouble actor for thread-safe accumulation
- Add missing await keywords

Fixes: TranscriptionEngine.swift compilation
Refs: #1
```

```
perf(audio): optimize 4 hot paths with vDSP and circular buffers

- Add CircularAudioBuffer for O(1) vs O(n) array operations
- Add ChunkedSpeechBuffer for bounded memory (768KB vs 2.6GB)
- Use vDSP_deqinter for stereo deinterleave (4-8x speedup)
- Use vDSP_vadd/vsmul for mixToMono (4-6x speedup)

Performance: 10-50x speedup on hot paths
Refs: #3
```

---

## Anti-Patterns (FORBIDDEN)

| Pattern | Why Forbidden | Alternative |
|---------|-------------|-------------|
| `git merge --squash` | Destroys commit history | `git merge --no-ff --no-squash` |
| `git rebase -i` with squash | Loses individual commits | `git rebase main` only |
| `git commit --amend` after push | Rewrites published history | New commit with `git revert` if needed |
| Force push to main | Dangerous | PR + merge only |

---

## Emergency Procedures

### If Squash Happens Accidentally

```bash
# 1. Stop immediately
git merge --abort

# 2. Reset to pre-merge state
git reset --hard HEAD@{1}

# 3. Re-merge correctly
git merge --no-ff --no-squash <branch>
```

### If Rebase Goes Wrong

```bash
# 1. Abort rebase
git rebase --abort

# 2. Reset to origin state
git reset --hard fork/feat!/3tier-clean-architecture

# 3. Start over
git rebase origin/main
```

---

## Verification Checklist

Before each merge:
- [ ] Branch is rebased to latest integration
- [ ] All tests pass
- [ ] No squash in merge command
- [ ] Commit history preserved
- [ ] Conventional commit format
- [ ] PR description includes "NO SQUASH"

After each merge:
- [ ] `git log --oneline --graph` shows linear history
- [ ] All commits from slice visible in integration
- [ ] No "squash" or "SQUASH" in commit messages
- [ ] Integration branch pushed to fork

---

## Contact

**Git Workflow Questions**: VP of Engineering (`wfc-engineer`)  
**Emergency Escalation**: Chief of Staff (`wfc-pm`)

---

**Last Updated**: 2026-05-01  
**Next Review**: After all 4 slices merged to integration
