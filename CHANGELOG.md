# Changelog

All notable changes to OpenOats will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking Changes

#### AppSettings Consolidation with SettingsStore (2026-04-30)

**Summary**: The `AppSettings` and `SettingsStore` classes have been consolidated into a single type using a typealias. This is a breaking change for any code that depends on the legacy `AppSettings` implementation.

**What Changed**:
- `AppSettings` is now a `typealias` for `SettingsStore`
- Both names refer to the same underlying type
- All properties from both classes are now available via the unified `SettingsStore` API
- The legacy `AppSettings` implementation (with `didSet` persistence) is deprecated

**Migration Guide**:

1. **Type References**: Any code referencing `AppSettings` will now automatically reference `SettingsStore`. No type signature changes needed:
   ```swift
   // Before and After - both work the same
   @Bindable var settings: AppSettings
   // Internally resolves to: @Bindable var settings: SettingsStore
   ```

2. **Initialization**: A convenience initializer has been added for backward compatibility:
   ```swift
   // Old way (still works via typealias)
   let settings = AppSettings()
   
   // New way (explicit SettingsStore initialization)
   let settings = SettingsStore(storage: .live())
   ```

3. **Persistence Pattern**: The persistence mechanism has changed:
   - **Old**: Used `didSet` observers on each property
   - **New**: Uses Swift 6 `@Observable` with `access`/`withMutation` pattern
   - **Impact**: Properties automatically persist via `SettingsStorage` abstraction

4. **Property API Changes**: SettingsStore has 80+ properties vs AppSettings' ~20:
   - All original AppSettings properties are preserved
   - Additional properties available: `mlx*`, `webhook*`, `sidecast*`, etc.
   - See `SettingsStore.swift` for complete property list

5. **Keychain Service Name**:
   - **Old**: Used hardcoded `'com.opengranola.app'`
   - **New**: Uses injected `secretStore` (configurable)
   - **Migration**: Keychain entries are automatically migrated on first run

**Swift 6 @Observable Pattern**:

The new standard uses the Observation framework:
```swift
@Observable
@MainActor
final class SettingsStore {
    @ObservationIgnored nonisolated(unsafe) private var _property: Type
    var property: Type {
        get { 
            access(keyPath: \.property)
            return _property 
        }
        set {
            withMutation(keyPath: \.property) {
                _property = newValue
                defaults.set(newValue, forKey: "propertyKey")
            }
        }
    }
}
```

**Benefits**:
- Single source of truth for all settings
- Proper Swift 6 Observation patterns
- Comprehensive API with all settings in one place
- Test and View compatibility unified

**Verification Steps**:
1. Build the project: `swift build`
2. Run tests: `swift test`
3. Verify View bindings work: `@Bindable var settings: AppSettings`
4. Check property access: All original AppSettings properties accessible

**Related**:
- ADR: `docs/adr/001-consolidate-appsettings-settingsstore.md`
- Implementation: `OpenOats/Sources/OpenOats/Settings/SettingsStore.swift`

## [1.0.0] - 2026-04-XX

### Added
- Initial stable release with mlx-audio integration
- Local transcription via MLX Whisper
- Real-time meeting suggestions
- Knowledge base search with embeddings
- Settings consolidation for improved architecture

### Changed
- Migrated to Swift 6 @Observable pattern for settings
- Consolidated AppSettings and SettingsStore

### Deprecated
- Legacy AppSettings class (replaced by typealias to SettingsStore)
