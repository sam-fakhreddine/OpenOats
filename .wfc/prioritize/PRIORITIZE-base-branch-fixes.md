# Feature Prioritization: Base Branch Compilation Fixes

## Meta
- **Framework**: MoSCoW (scope boundary classification for compilation fixes)
- **Scope**: All compilation errors preventing clean build of feat/mlx-audio-and-model-storage
- **Goal**: Achieve zero compilation errors while preserving mlx-audio and meeting detection features
- **Date**: 2026-04-30
- **Source**: Discovery findings from wfc-ba parallel subagents

## Error Categories & Requirements

### MUST (Non-negotiable - Build Blockers)

| ID | Requirement | Acceptance Criteria | Source |
|----|-------------|---------------------|--------|
| MUST-001 | Restore missing AppSettings properties | `meetingAutoDetectEnabled`, `notesFolders`, `meetingFamilyPreferences`, `meetingHistoryAliasesByKey`, `canonicalMeetingHistoryKey` properties exist and compile | discovery |
| MUST-002 | Implement `setMeetingFamilyFolderPreference` method | Method signature matches View expectations, compiles without errors | discovery |
| MUST-003 | Fix AppSettings @Observable architecture | AppSettings uses @Observable macro, works with @Bindable in Views, Swift 6 compatible | research |
| MUST-004 | Restore deleted type definitions | AppSecretStore, CalendarEvent, SidecastPersona types exist and compile | discovery |
| MUST-005 | Fix ParakeetBackend API compatibility | Decoder state parameter added, Repo.parakeet symbol resolved, exhaustive switch includes tdtJa case | discovery |
| MUST-006 | Resolve SettingsStore vs AppSettings conflicts | Single source of truth for settings, no type mismatches in View initializers | discovery |

### SHOULD (Important but Build Can Survive Temporarily)

| ID | Requirement | Acceptance Criteria | Source |
|----|-------------|---------------------|--------|
| SHOULD-001 | Add comprehensive documentation | ADR documenting @Observable migration pattern, migration guide for developers | research |
| SHOULD-002 | Implement backward compatibility layer | Legacy ObservableObject patterns still work during transition | competitive |
| SHOULD-003 | Add regression tests | Tests verify AppSettings properties exist and are accessible | discovery |

### COULD (Desirable if Time Allows)

| ID | Requirement | Acceptance Criteria | Source |
|----|-------------|---------------------|--------|
| COULD-001 | Optimize @Observable performance | ObservationRegistrar efficiently tracks only necessary properties | research |
| COULD-002 | Add property validation | Settings properties validate inputs (e.g., folder paths exist) | discovery |
| COULD-003 | Create developer tooling | Script to detect missing properties between Views and AppSettings | competitive |

### WON'T (Explicitly Excluded)

| ID | Requirement | Reason |
|----|-------------|--------|
| WONT-001 | Full codebase refactor | Limited to compilation fixes, not architectural improvements |
| WONT-002 | Feature enhancements | Only fixing existing code, not adding new capabilities |
| WONT-003 | CI/CD pipeline changes | Out of scope for this fix session |

## Recommended Build Order

1. **MUST-004** - Restore deleted types (AppSecretStore, CalendarEvent, SidecastPersona) - Unblocks references
2. **MUST-003** - Fix @Observable architecture - Foundation for all other fixes
3. **MUST-001** - Add missing AppSettings properties - Resolves View compilation errors
4. **MUST-002** - Implement missing methods - Completes AppSettings API surface
5. **MUST-005** - Fix ParakeetBackend API - Resolves mlx-audio specific errors
6. **MUST-006** - Resolve SettingsStore conflicts - Final integration cleanup

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| MLX-audio feature regression | Medium | High | Coordinate with MLX owner, run MLX-specific tests |
| @Observable migration breaks runtime observation | Low | High | Test observation notifications, verify SwiftUI updates |
| Missing properties discovered late | Medium | Medium | Comprehensive View audit before declaring done |
| Swift 6 concurrency warnings | High | Low | Address with @MainActor, @preconcurrency as needed |

## Close-Call Decisions

**@Observable vs. ObservableObject**: Research suggests @Observable is the Swift 6 direction, but requires more coordination. Decision: Proceed with @Observable as the base branch already started this migration.

**Full migration vs. compatibility layer**: Competitive analysis shows most projects use compatibility layers. Decision: Minimal compatibility layer only where absolutely necessary to reduce complexity.

## Assumptions

- The mlx-audio feature owner is available for validation
- feat/meeting-detection branch can be rebased after base stabilization
- Swift 6 strict concurrency is a hard requirement
- Pinned dependencies (supply chain security) must be preserved

## Stakeholder Alignment

| Stakeholder | Concern | Status |
|-------------|---------|--------|
| Lead Developer | Preserve MLX audio features | Consulted - will validate |
| Meeting Detection Owner | Base stability blocking progress | Blocker - this work unblocks them |
| Build/CI System | Clean compilation required | Blocker - final gate |
