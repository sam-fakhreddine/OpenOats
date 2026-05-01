# ADR 001: Consolidate AppSettings and SettingsStore via Typealias

**Status**: Accepted  
**Date**: 2026-04-30  
**Deciders**: Chief Architect (wfc-architect)  
**Context**: Base branch compilation fixes for feat/mlx-audio-and-model-storage

## Context and Problem Statement

The OpenOats codebase has two competing settings classes:

1. **AppSettings** (`OpenOats/Sources/OpenOats/Settings/AppSettings.swift`)
   - ~20 properties
   - Uses `didSet` for persistence
   - Simple implementation
   - Views reference this type directly via `@Bindable var settings: AppSettings`

2. **SettingsStore** (`OpenOats/Sources/OpenOats/Settings/SettingsStore.swift`)
   - 80+ properties
   - Uses manual `access`/`withMutation` Observation pattern
   - Comprehensive implementation with lazy secret loading
   - Tests expect `AppSettings.Type = SettingsStore.self`

**Problem**: 
- Views expect `AppSettings` but tests expect `SettingsStore`
- No typealias exists to unify them
- Both classes are `@Observable @MainActor` but have different APIs
- This causes compilation errors and confusion

## Decision

We will **consolidate to SettingsStore** and create a typealias:

```swift
typealias AppSettings = SettingsStore
```

This makes `AppSettings` and `SettingsStore` the same type, resolving:
- View compilation errors (`@Bindable var settings: AppSettings` now works)
- Test expectations (`AppSettings.self` resolves to `SettingsStore.self`)
- API consistency (single source of truth)

## Consequences

### Positive
- **Single source of truth**: One settings class to maintain
- **Comprehensive API**: SettingsStore has all needed properties (mlx*, webhook*, sidecast*, etc.)
- **Better architecture**: SettingsStore uses proper Observation patterns with `access`/`withMutation`
- **Test compatibility**: Tests expecting `AppSettings = SettingsStore` now pass
- **View compatibility**: All 15+ Views using `@Bindable var settings: AppSettings` work without changes

### Negative
- **Breaking change for AppSettings users**: Any code depending on AppSettings-specific behavior (didSet persistence) must adapt
- **Property API differences**: SettingsStore has many more properties; some may have different defaults
- **Keychain service name**: AppSettings uses 'com.opengranola.app', SettingsStore uses injected secretStore
- **Initialization differences**: SettingsStore requires `init(storage:)` vs AppSettings `init()`

### Mitigations
1. Add convenience initializer: `extension SettingsStore { convenience init() { self.init(storage: .live()) } }`
2. Audit all AppSettings properties for type parity with SettingsStore
3. Verify Keychain service name compatibility
4. Test all View bindings work correctly with SettingsStore

## Alternatives Considered

### Option 1: Keep Both Classes (Status Quo)
- **Pros**: No breaking changes
- **Cons**: Continued confusion, dual maintenance, compilation errors persist
- **Rejected**: Doesn't solve the immediate problem

### Option 2: Make AppSettings Wrap SettingsStore
```swift
@Observable class AppSettings {
    private let store: SettingsStore
    // Forward all properties to store
}
```
- **Pros**: Preserves AppSettings type, can customize behavior
- **Cons**: More complex, property forwarding boilerplate, potential observation issues
- **Rejected**: Unnecessary complexity; typealias is simpler

### Option 3: Delete SettingsStore, Keep AppSettings
- **Pros**: Simpler class, fewer properties to understand
- **Cons**: Lose mlx-audio settings, webhook settings, sidecast personas, etc.
- **Rejected**: Would break mlx-audio feature

### Option 4: Typealias AppSettings = SettingsStore (Selected)
- **Pros**: Simple, solves all compilation issues, preserves all features
- **Cons**: Requires verifying property compatibility
- **Accepted**: Best balance of simplicity and functionality

## Implementation Notes

1. Add typealias at end of SettingsStore.swift:
   ```swift
   typealias AppSettings = SettingsStore
   ```

2. Add convenience initializer:
   ```swift
   extension SettingsStore {
       convenience init() {
           self.init(storage: .live())
       }
   }
   ```

3. Remove or deprecate AppSettings.swift after verification

4. Verify these properties exist in SettingsStore:
   - kbFolderPath, notesFolderPath, selectedModel
   - transcriptionLocale, inputDeviceID
   - openRouterApiKey, voyageApiKey
   - llmProvider, embeddingProvider
   - ollamaBaseURL, ollamaLLMModel, ollamaEmbedModel
   - openAIEmbedBaseURL, openAIEmbedApiKey, openAIEmbedModel
   - hasAcknowledgedRecordingConsent, hideFromScreenShare

5. Verify computed properties:
   - kbFolderURL, locale, activeModelDisplay

## Related

- PRD: `.wfc/prd/PRD-base-branch-fixes.md`
- TASKS: `.wfc/plans/plan_base-branch-fixes_20260430_221736/TASKS.md`
- Architecture findings: `.wfc/pipeline/architecture-findings.json`
