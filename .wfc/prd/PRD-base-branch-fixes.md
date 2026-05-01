# PRD: Base Branch Compilation Fixes

**Author:** WFC:PRD | **Date:** 2026-04-30 | **Status:** Draft  
**Source:** PRIORITIZE-base-branch-fixes.md (wfc-prioritize output from wfc-ba discovery)

## 1. Overview

### Problem Statement
The `feat/mlx-audio-and-model-storage` branch has approximately 20 Swift compilation errors preventing a clean build. These errors block development progress for multiple dependent features including meeting detection. The errors stem from:
- Missing AppSettings properties that Views expect
- Deleted type definitions (AppSecretStore, CalendarEvent, SidecastPersona) still referenced
- @Observable architecture mismatches between AppSettings and Views using @Bindable
- API changes in ParakeetBackend requiring decoder state parameters

**Cost of inaction**: Meeting detection feature cannot merge, mlx-audio development stalls, CI/CD pipeline remains broken.

### Proposed Solution
Restore and align the AppSettings architecture with View expectations by:
1. Re-implementing missing @Observable AppSettings with all required properties
2. Restoring deleted type definitions
3. Fixing ParakeetBackend API compatibility
4. Ensuring Swift 6 concurrency compliance

### Success Metrics
| Metric | Target | Measurement Method |
|--------|--------|---------------------|
| Compilation errors | 0 | `swift build` exits with code 0 |
| Test pass rate | 100% | `swift test` all tests pass |
| Feature preservation | 100% | mlx-audio and meeting detection features functional |
| CI build time | < 60s | GitHub Actions build duration |

## 2. Context & Background

**Business Context**: OpenOats is a macOS meeting transcription app with multiple concurrent feature branches. The base branch (`feat/mlx-audio-and-model-storage`) introduced mlx-audio capabilities but broke compilation due to architectural changes in AppSettings.

**Prior Attempts**: Previous fixes (commit `2d18d4e`) resolved ~35 errors but left ~20 remaining. The fixes created a hybrid state where AppSettings partially uses @Observable but lacks required properties.

**Market Landscape**: Swift 6 adoption requires @Observable macro for modern SwiftUI apps. Migration patterns exist but require careful coordination.

**Related Documents**:
- `.wfc/prioritize/PRIORITIZE-base-branch-fixes.md` - Prioritization analysis
- `.wfc/pipeline/discovery-findings.json` - Pain point analysis
- `.wfc/pipeline/research-packet.json` - Technical research

## 3. User Stories

### Primary Persona: Lead Developer (Sam Fakhreddine)
- **US-001**: As the lead developer, I want a clean compiling base branch so that I can merge meeting detection features.
  - Acceptance: `swift build` completes with zero errors

- **US-002**: As the lead developer, I want AppSettings to work with @Bindable in Views so that SwiftUI bindings function correctly.
  - Acceptance: Views using `@Bindable var settings: AppSettings` compile and run without runtime errors

- **US-003**: As the lead developer, I want mlx-audio features preserved so that the Whisper transcription backend continues working.
  - Acceptance: MLXWhisperBackend initializes and transcribes audio successfully

### Secondary Persona: Feature Developer (Meeting Detection Owner)
- **US-004**: As a feature developer, I want the base branch stabilized so that I can rebase my feature branch without conflicts.
  - Acceptance: `feat/meeting-detection` rebases cleanly onto fixed base branch

- **US-005**: As a feature developer, I want meeting detection settings accessible via AppSettings so that the UI toggle works.
  - Acceptance: `settings.meetingAutoDetectEnabled` property exists and is observable

### Tertiary Persona: Build/CI System
- **US-006**: As the CI system, I want automated builds to pass so that merge gates function correctly.
  - Acceptance: GitHub Actions workflow completes successfully

## 4. Requirements

### P0 — Must Have (Launch Blockers)
| ID | Requirement | Rationale | Acceptance Criteria |
|----|-------------|-----------|---------------------|
| R-001 | Restore AppSecretStore type | Referenced by SettingsStore | Type exists, compiles, Keychain integration works |
| R-002 | Restore CalendarEvent type | Referenced by meeting detection | Type exists with all required properties |
| R-003 | Restore SidecastPersona type | Referenced by AppSettings | Type exists, Codable conformance |
| R-004 | Add `meetingAutoDetectEnabled` property | Used by MenuBarPopoverView | Bool property with @ObservationIgnored or proper observation |
| R-005 | Add `notesFolders` property | Used by IdleHomeDashboardView | Array of NotesFolderDefinition, observable |
| R-006 | Add `meetingFamilyPreferences` method | Used by IdleHomeDashboardView | Method signature matches call sites |
| R-007 | Add `meetingHistoryAliasesByKey` property | Used by IdleHomeDashboardView | Dictionary [String: String], observable |
| R-008 | Add `canonicalMeetingHistoryKey` method | Used by IdleHomeDashboardView | Returns String, accepts CalendarEvent parameter |
| R-009 | Add `setMeetingFamilyFolderPreference` method | Used by IdleHomeDashboardView | Void return, accepts folderPath and historyKey |
| R-010 | Fix ParakeetBackend decoder state | API change in mlx-audio | Decoder state parameter added, compiles |
| R-011 | Fix exhaustive switch for tdtJa case | Missing enum case | Switch statement includes tdtJa case |
| R-012 | Resolve SettingsStore/AppSettings conflicts | Type mismatches in Views | Single consistent type used throughout |

### P1 — Should Have (High Value)
| ID | Requirement | Rationale |
|----|-------------|-----------|
| R-013 | Document @Observable migration pattern | Help future developers | ADR created with migration guide |
| R-014 | Add regression tests for AppSettings | Prevent future breakage | Tests verify all properties exist |
| R-015 | Implement minimal compatibility layer | Support legacy patterns | ObservableObject wrapper if needed |

### P2 — Nice to Have (Future Consideration)
| ID | Requirement | Rationale |
|----|-------------|-----------|
| R-016 | Optimize ObservationRegistrar usage | Performance | Only track necessary properties |
| R-017 | Add property validation | Data integrity | Validate folder paths exist |
| R-018 | Create property sync detection tool | Developer experience | Script to detect View/AppSettings mismatches |

### Non-Functional Requirements
| Category | Requirement | Target |
|----------|-------------|--------|
| Performance | Build time | < 60 seconds for clean build |
| Security | Supply chain | All dependencies pinned to git hashes |
| Reliability | Zero warnings | No Swift 6 concurrency warnings |
| Maintainability | Code clarity | All properties documented |

## 5. Design & UX

**No UI changes** - This is a compilation fix effort. All View code remains unchanged; only the underlying AppSettings implementation is modified to match View expectations.

**Key Interaction Flows**:
1. App launches → AppSettings initializes with @Observable → Views bind via @Bindable
2. User toggles meeting detection → `meetingAutoDetectEnabled` updates → Observation notifies listeners
3. User selects notes folder → `notesFolders` updates → UI reflects change

**UI States**: No new UI states introduced. Existing states must continue functioning.

## 6. Technical Considerations

**Known Constraints**:
- Swift 6 strict concurrency checking enabled
- Must use @Observable macro (not ObservableObject)
- Must preserve pinned dependency versions
- MLX-audio feature uses Metal GPU (runtime constraint, not compilation)

**Integration Points**:
- SettingsStore → AppSettings (storage layer)
- Views → AppSettings (@Bindable bindings)
- MeetingDetectionEngine → AppSettings (observation)
- ParakeetBackend → MLXAudioSTT (API dependency)

**Migration Needs**:
- Deleted files need restoration from git history or re-implementation
- @Observable requires different property patterns than @Published
- Bindable usage may need adjustment for read-only vs. read-write access

## 7. Implementation Plan

### Phase 1: Foundation (Days 1-2)
- Restore deleted type definitions (R-001, R-002, R-003)
- Fix ParakeetBackend API issues (R-010, R-011)
- **Exit criteria**: Type-level compilation errors resolved

### Phase 2: AppSettings Architecture (Days 3-4)
- Implement @Observable AppSettings with all required properties (R-004 through R-009)
- Resolve SettingsStore/AppSettings conflicts (R-012)
- **Exit criteria**: All View compilation errors resolved

### Phase 3: Validation (Day 5)
- Run full test suite
- Verify mlx-audio feature still functional
- Verify meeting detection integration
- **Exit criteria**: `swift build && swift test` passes, zero errors

### Phase 4: Documentation (Day 6)
- Create ADR for @Observable migration
- Document any compatibility patterns used
- **Exit criteria**: Documentation complete, PR ready

## 8. Open Questions

| # | Question | Owner | Due Date |
|---|----------|-------|----------|
| 1 | Should we restore deleted files from git or re-implement? | Lead Developer | Day 1 |
| 2 | Is @Observable the final architecture or temporary? | Lead Developer | Day 1 |
| 3 | Do we need ObservableObject compatibility layer? | Lead Developer | Day 2 |
| 4 | Which MLX-audio tests validate the feature? | MLX Owner | Day 3 |

## 9. Appendix

### Glossary
- **@Observable**: Swift 6 macro for observation without ObservableObject protocol
- **@Bindable**: Property wrapper for creating bindings to @Observable types
- **MLX**: Machine Learning framework for Apple Silicon
- **Parakeet**: Speech recognition model used by MLX-audio

### Related BA Documents
- `.wfc/pipeline/discovery-findings.json` - 12 pain points identified
- `.wfc/pipeline/research-packet.json` - @Observable migration research
- `.wfc/pipeline/competitive-findings.json` - Industry migration patterns
- `.wfc/pipeline/stakeholder-findings.json` - Stakeholder alignment

### Prior Art
- Swift Evolution proposal for @Observable
- Point-Free's @ObservableState for TCA
- Apple's SwiftUI documentation on @Observable
