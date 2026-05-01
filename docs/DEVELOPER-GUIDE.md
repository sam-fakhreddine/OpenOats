# OpenOats Developer Guide

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Settings System Migration](#settings-system-migration)
3. [Swift 6 @Observable Pattern](#swift-6-observable-pattern)
4. [Working with SettingsStore](#working-with-settingsstore)
5. [Testing](#testing)
6. [Common Issues](#common-issues)

---

## Architecture Overview

OpenOats is a SwiftUI macOS application built with Swift 6.2. The codebase follows these architectural principles:

- **@Observable Pattern**: Uses Swift 6 Observation framework (not ObservableObject)
- **@MainActor**: All UI-related types are isolated to the main actor
- **Modular Design**: Separated into Domains, Services, and Views
- **Type Safety**: Heavy use of strong typing and compile-time checks

### Project Structure

```
OpenOats/
├── Sources/OpenOats/
│   ├── Settings/           # SettingsStore, AppSecretStore, SettingsTypes
│   ├── Domain/             # Core business logic and models
│   ├── Services/           # External service integrations
│   ├── Views/              # SwiftUI view layer
│   └── Transcription/      # Audio transcription backends
├── Tests/                  # Unit and integration tests
└── docs/                   # Documentation
```

---

## Settings System Migration

### Background

OpenOats recently consolidated its settings architecture. Previously, there were two competing settings classes:

1. **AppSettings** (~20 properties, `didSet` persistence)
2. **SettingsStore** (80+ properties, Observation pattern)

These have been unified via a typealias:

```swift
typealias AppSettings = SettingsStore
```

### What This Means for Developers

**The Good News**: Most code doesn't need changes. Views using `@Bindable var settings: AppSettings` continue to work because `AppSettings` now resolves to `SettingsStore`.

**Type Identity**:
```swift
AppSettings.self == SettingsStore.self  // true
let settings: AppSettings = SettingsStore(storage: .live())  // valid
```

### Migration Scenarios

#### Scenario 1: View Uses AppSettings

**Before**:
```swift
struct SettingsView: View {
    @Bindable var settings: AppSettings
    
    var body: some View {
        Toggle("Hide from Screen Share", isOn: $settings.hideFromScreenShare)
    }
}
```

**After**: No changes needed! The typealias ensures `AppSettings` now refers to `SettingsStore`.

#### Scenario 2: Creating Settings Instances

**Before**:
```swift
let settings = AppSettings()  // Called init()
```

**After** (with backward compatibility):
```swift
// Option 1: Convenience init (recommended for backward compatibility)
let settings = AppSettings()  // Still works via typealias

// Option 2: Explicit SettingsStore initialization
let settings = SettingsStore(storage: .live())

// Option 3: With custom storage (for testing)
let settings = SettingsStore(storage: .mock)
```

#### Scenario 3: Test Expectations

**Before**:
```swift
XCTAssertEqual(AppSettings.self, SettingsStore.self)  // Failed - different types
```

**After**:
```swift
XCTAssertEqual(AppSettings.self, SettingsStore.self)  // Passes - same type via typealias
```

---

## Swift 6 @Observable Pattern

OpenOats uses the modern Swift Observation framework. Understanding this pattern is essential for working with settings.

### How It Works

Instead of `ObservableObject` with `@Published` properties:

```swift
// Old Pattern (ObservableObject)
class OldSettings: ObservableObject {
    @Published var property: String
}
```

We use `@Observable` with explicit observation:

```swift
// New Pattern (@Observable)
@Observable
@MainActor
final class SettingsStore {
    // Private storage with @ObservationIgnored
    @ObservationIgnored nonisolated(unsafe) private var _property: String
    
    // Public accessor with observation
    var property: String {
        get {
            // Notify observation system of read
            access(keyPath: \.property)
            return _property
        }
        set {
            // Notify observation system of mutation
            withMutation(keyPath: \.property) {
                _property = newValue
                // Persistence happens here
                defaults.set(newValue, forKey: "propertyKey")
            }
        }
    }
}
```

### Key Components

1. **`@ObservationIgnored`**: Prevents automatic observation of private storage
2. **`access(keyPath:)`**: Registers that a property was read (for SwiftUI dependency tracking)
3. **`withMutation(keyPath:)`**: Registers that a property was modified (triggers UI updates)
4. **`nonisolated(unsafe)`**: Required for stored properties in `@MainActor` classes

### Why This Pattern?

- **Performance**: Granular tracking (only changed properties trigger updates)
- **Concurrency**: Works correctly with Swift 6 concurrency checking
- **Flexibility**: Allows custom persistence logic within setters

---

## Working with SettingsStore

### Available Properties

SettingsStore includes all properties from the legacy AppSettings, plus additional ones:

**Core Settings** (from legacy AppSettings):
- `kbFolderPath: String` - Knowledge base folder path
- `notesFolderPath: String` - Notes/transcripts folder
- `selectedModel: String` - Active LLM model identifier
- `transcriptionLocale: String` - Speech recognition locale
- `inputDeviceID: AudioDeviceID` - Audio input device
- `openRouterApiKey: String` - OpenRouter API key (Keychain-stored)
- `voyageApiKey: String` - Voyage AI API key (Keychain-stored)
- `llmProvider: LLMProvider` - LLM provider selection
- `embeddingProvider: EmbeddingProvider` - Embedding provider selection
- `ollamaBaseURL: String` - Ollama server URL
- `ollamaLLMModel: String` - Ollama LLM model
- `ollamaEmbedModel: String` - Ollama embedding model
- `openAIEmbedBaseURL: String` - OpenAI-compatible embeddings endpoint
- `openAIEmbedApiKey: String` - Embeddings API key (Keychain-stored)
- `openAIEmbedModel: String` - Embeddings model name
- `hasAcknowledgedRecordingConsent: Bool` - Recording consent acknowledgment
- `hideFromScreenShare: Bool` - Window sharing visibility

**Computed Properties**:
- `kbFolderURL: URL?` - Knowledge base as URL
- `locale: Locale` - Transcription locale object
- `activeModelDisplay: String` - Human-readable model name

**Additional SettingsStore Properties**:
- `mlx*` - MLX audio-related settings
- `webhook*` - Webhook integration settings
- `sidecastPersonas: [SidecastPersona]` - Sidecast personas
- `meetingAutoDetectEnabled: Bool` - Automatic meeting detection
- `notesFolders: [NotesFolderDefinition]` - Multiple notes folders
- `meetingHistoryAliasesByKey: [String: String]` - Meeting history aliases

### Adding New Properties

When adding properties to SettingsStore, follow this pattern:

```swift
@ObservationIgnored nonisolated(unsafe) private var _newProperty: PropertyType

var newProperty: PropertyType {
    get {
        access(keyPath: \.newProperty)
        return _newProperty
    }
    set {
        withMutation(keyPath: \.newProperty) {
            _newProperty = newValue
            defaults.set(newValue, forKey: "newPropertyKey")
        }
    }
}
```

Initialize in `init(storage:)`:

```swift
self._newProperty = defaults.object(forKey: "newPropertyKey") as? PropertyType ?? defaultValue
```

### Secret (Keychain) Properties

For sensitive values stored in Keychain:

```swift
@ObservationIgnored nonisolated(unsafe) private var _apiKey: String

var apiKey: String {
    get {
        access(keyPath: \.apiKey)
        // Lazy loading from Keychain
        return loadSecretIfNeeded(key: "apiKey", currentValue: _apiKey) {
            _apiKey = $0
        }
    }
    set {
        withMutation(keyPath: \.apiKey) {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            _apiKey = trimmed
            markSecretLoaded("apiKey")
            secretStore.save(key: "apiKey", value: trimmed)
        }
    }
}
```

---

## Testing

### Mock Settings

For tests, use `SettingsStorage.mock`:

```swift
let settings = SettingsStore(storage: .mock)
```

This uses in-memory storage that doesn't persist to UserDefaults or Keychain.

### Verifying Observation

To test that observation works:

```swift
func testPropertyObservation() {
    let settings = SettingsStore(storage: .mock)
    var observedCount = 0
    
    // Create observation
    let observation = observe(settings) { settings in
        _ = settings.someProperty
    } onChange: {
        observedCount += 1
    }
    
    // Change should trigger observation
    settings.someProperty = "new value"
    XCTAssertEqual(observedCount, 1)
}
```

### Type Alias Verification

Verify the typealias works correctly:

```swift
func testAppSettingsIsSettingsStore() {
    XCTAssertTrue(AppSettings.self == SettingsStore.self)
    
    let settings = AppSettings()
    XCTAssertTrue(type(of: settings) == SettingsStore.self)
}
```

---

## Common Issues

### Issue: "Type 'AppSettings' has no member 'someProperty'"

**Cause**: The property exists only in the old AppSettings implementation, not in SettingsStore.

**Solution**: Check if the property was added to SettingsStore. The ADR lists properties that must exist - verify them in SettingsStore.swift.

### Issue: "Cannot convert value of type 'SettingsStore' to 'AppSettings'"

**Cause**: Typealias not properly resolved.

**Solution**: Verify the typealias exists at the bottom of SettingsStore.swift:

```swift
typealias AppSettings = SettingsStore
```

### Issue: Observation not triggering UI updates

**Cause**: Missing `access()` or `withMutation()` calls.

**Solution**: Ensure the property getter calls `access(keyPath:)` and setter calls `withMutation(keyPath:)`.

### Issue: Keychain values not loading

**Cause**: Secret not marked as loaded, or Keychain access issues.

**Solution**: 
1. Verify `markSecretLoaded()` is called after saving
2. Check Keychain entitlements in Debug/Release builds
3. Look for migration issues (old service name vs new)

---

## Additional Resources

- [ADR 001: Consolidate AppSettings and SettingsStore](docs/adr/001-consolidate-appsettings-settingsstore.md)
- [CHANGELOG.md](../CHANGELOG.md)
- [Swift Observation Documentation](https://developer.apple.com/documentation/observation)
- [Swift Concurrency Guide](https://developer.apple.com/documentation/swift/concurrency)

---

*Last updated: 2026-04-30*
