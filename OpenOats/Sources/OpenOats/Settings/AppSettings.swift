import AppKit
import Foundation
import Observation
import Security
import CoreAudio

enum LLMProvider: String, CaseIterable, Identifiable {
    case openRouter
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama"
        }
    }
}

enum EmbeddingProvider: String, CaseIterable, Identifiable {
    case voyageAI
    case ollama
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .voyageAI: "Voyage AI"
        case .ollama: "Ollama"
        case .openAICompatible: "OpenAI Compatible"
        }
    }
}

enum ASRProviderKind: String, CaseIterable, Identifiable {
    case parakeetV3 = "parakeetV3"
    case whisperLargeV3Turbo = "whisperLargeV3Turbo"

    var id: String { rawValue }

    var isExperimental: Bool { self != .parakeetV3 }

    var displayName: String {
        switch self {
        case .parakeetV3: return "Parakeet TDT v3 (default)"
        case .whisperLargeV3Turbo: return "Whisper large-v3-turbo"
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    var kbFolderPath: String {
        didSet { UserDefaults.standard.set(kbFolderPath, forKey: "kbFolderPath") }
    }

    var notesFolderPath: String {
        didSet { UserDefaults.standard.set(notesFolderPath, forKey: "notesFolderPath") }
    }

    var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }

    var transcriptionLocale: String {
        didSet { UserDefaults.standard.set(transcriptionLocale, forKey: "transcriptionLocale") }
    }

    /// Stored as the AudioDeviceID integer. 0 means "use system default".
    var inputDeviceID: AudioDeviceID {
        didSet { UserDefaults.standard.set(Int(inputDeviceID), forKey: "inputDeviceID") }
    }

    // Debounce Tasks keyed by Keychain key name. Cancelled and rescheduled on each keystroke.
    private var keychainDebounceTimers: [String: Task<Void, Never>] = [:]

    private func saveKeychainDebounced(key: String, value: String) {
        keychainDebounceTimers[key]?.cancel()
        keychainDebounceTimers[key] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            KeychainHelper.save(key: key, value: value)
        }
    }

    var openRouterApiKey: String {
        didSet { saveKeychainDebounced(key: "openRouterApiKey", value: openRouterApiKey) }
    }

    var voyageApiKey: String {
        didSet { saveKeychainDebounced(key: "voyageApiKey", value: voyageApiKey) }
    }

    var llmProvider: LLMProvider {
        didSet { UserDefaults.standard.set(llmProvider.rawValue, forKey: "llmProvider") }
    }

    var embeddingProvider: EmbeddingProvider {
        didSet { UserDefaults.standard.set(embeddingProvider.rawValue, forKey: "embeddingProvider") }
    }

    var ollamaBaseURL: String {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: "ollamaBaseURL") }
    }

    var ollamaLLMModel: String {
        didSet { UserDefaults.standard.set(ollamaLLMModel, forKey: "ollamaLLMModel") }
    }

    var ollamaEmbedModel: String {
        didSet { UserDefaults.standard.set(ollamaEmbedModel, forKey: "ollamaEmbedModel") }
    }

    var openAIEmbedBaseURL: String {
        didSet { UserDefaults.standard.set(openAIEmbedBaseURL, forKey: "openAIEmbedBaseURL") }
    }

    var openAIEmbedApiKey: String {
        didSet { saveKeychainDebounced(key: "openAIEmbedApiKey", value: openAIEmbedApiKey) }
    }

    var openAIEmbedModel: String {
        didSet { UserDefaults.standard.set(openAIEmbedModel, forKey: "openAIEmbedModel") }
    }

    /// Bundle ID of the app to capture system audio from. Empty string = capture all apps.
    var captureAppBundleID: String {
        didSet { UserDefaults.standard.set(captureAppBundleID, forKey: "captureAppBundleID") }
    }

    /// Whether real-time AI suggestions are enabled.
    /// When true, conversation excerpts are sent to the configured LLM/embedding provider
    /// automatically after each "them" utterance.
    var aiAssistEnabled: Bool {
        didSet { UserDefaults.standard.set(aiAssistEnabled, forKey: "aiAssistEnabled") }
    }

    /// Whether speaker diarization is enabled for the system audio ("them") channel.
    /// When true, DiarizerManager is initialized and each "them" utterance is labeled
    /// "Speaker 1", "Speaker 2", etc. instead of the undifferentiated "Them".
    var distinguishSpeakers: Bool {
        didSet { UserDefaults.standard.set(distinguishSpeakers, forKey: "distinguishSpeakers") }
    }

    var showExperimentalFeatures: Bool {
        didSet { UserDefaults.standard.set(showExperimentalFeatures, forKey: "showExperimentalFeatures") }
    }

    var asrProvider: ASRProviderKind {
        didSet { UserDefaults.standard.set(asrProvider.rawValue, forKey: "asrProvider") }
    }

    /// Whether the user has acknowledged their obligation to comply with recording consent laws.
    var hasAcknowledgedRecordingConsent: Bool {
        didSet { UserDefaults.standard.set(hasAcknowledgedRecordingConsent, forKey: "hasAcknowledgedRecordingConsent") }
    }

    /// When true, all app windows are invisible to screen sharing / recording.
    var hideFromScreenShare: Bool {
        didSet {
            UserDefaults.standard.set(hideFromScreenShare, forKey: "hideFromScreenShare")
            applyScreenShareVisibility()
        }
    }

    init() {
        let defaults = UserDefaults.standard

        // One-time migrations from previous bundle IDs
        Self.migrateFromOldBundleIfNeeded(defaults: defaults)
        Self.migrateFromOpenGranolaIfNeeded(defaults: defaults)

        self.kbFolderPath = defaults.string(forKey: "kbFolderPath") ?? ""

        let defaultNotesPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/OpenOats").path
        self.notesFolderPath = defaults.string(forKey: "notesFolderPath") ?? defaultNotesPath
        self.selectedModel = defaults.string(forKey: "selectedModel") ?? "google/gemini-3-flash-preview"
        self.transcriptionLocale = defaults.string(forKey: "transcriptionLocale") ?? "en-US"
        self.inputDeviceID = AudioDeviceID(defaults.integer(forKey: "inputDeviceID"))
        self.openRouterApiKey = KeychainHelper.load(key: "openRouterApiKey") ?? ""
        self.voyageApiKey = KeychainHelper.load(key: "voyageApiKey") ?? ""
        self.llmProvider = LLMProvider(rawValue: defaults.string(forKey: "llmProvider") ?? "") ?? .openRouter
        self.embeddingProvider = EmbeddingProvider(rawValue: defaults.string(forKey: "embeddingProvider") ?? "") ?? .voyageAI
        self.ollamaBaseURL = defaults.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        self.ollamaLLMModel = defaults.string(forKey: "ollamaLLMModel") ?? "qwen3:8b"
        self.ollamaEmbedModel = defaults.string(forKey: "ollamaEmbedModel") ?? "nomic-embed-text"
        self.openAIEmbedBaseURL = defaults.string(forKey: "openAIEmbedBaseURL") ?? "http://localhost:8080"
        self.openAIEmbedApiKey = KeychainHelper.load(key: "openAIEmbedApiKey") ?? ""
        self.openAIEmbedModel = defaults.string(forKey: "openAIEmbedModel") ?? "text-embedding-3-small"
        self.captureAppBundleID = defaults.string(forKey: "captureAppBundleID") ?? ""
        // Default to true so existing users keep current behaviour; they can disable in Settings
        self.aiAssistEnabled = defaults.object(forKey: "aiAssistEnabled") == nil
            ? true
            : defaults.bool(forKey: "aiAssistEnabled")
        self.hasAcknowledgedRecordingConsent = defaults.bool(forKey: "hasAcknowledgedRecordingConsent")
        self.distinguishSpeakers = defaults.bool(forKey: "distinguishSpeakers")  // default false
        self.showExperimentalFeatures = defaults.bool(forKey: "showExperimentalFeatures")
        let rawProvider = defaults.string(forKey: "asrProvider") ?? ASRProviderKind.parakeetV3.rawValue
        self.asrProvider = ASRProviderKind(rawValue: rawProvider) ?? .parakeetV3

        // Default to true (hidden) if key has never been set
        if defaults.object(forKey: "hideFromScreenShare") == nil {
            self.hideFromScreenShare = true
        } else {
            self.hideFromScreenShare = defaults.bool(forKey: "hideFromScreenShare")
        }

        // Ensure notes folder exists
        try? FileManager.default.createDirectory(
            atPath: notesFolderPath,
            withIntermediateDirectories: true
        )
    }

    /// Migrate settings from the old "On The Spot" (com.onthespot.app) bundle.
    /// Copies UserDefaults and Keychain entries to the current bundle, then marks migration as done.
    private static func migrateFromOldBundleIfNeeded(defaults: UserDefaults) {
        let migrationKey = "didMigrateFromOnTheSpot"
        guard !defaults.bool(forKey: migrationKey) else { return }
        defer { defaults.set(true, forKey: migrationKey) }

        // Migrate UserDefaults from old bundle
        guard let oldDefaults = UserDefaults(suiteName: "com.onthespot.app") else { return }

        let keysToMigrate = [
            "kbFolderPath", "selectedModel", "transcriptionLocale", "inputDeviceID",
            "llmProvider", "embeddingProvider", "ollamaBaseURL", "ollamaLLMModel",
            "ollamaEmbedModel", "hideFromScreenShare",
            "isTranscriptExpanded", "hasCompletedOnboarding"
        ]
        for key in keysToMigrate {
            if let value = oldDefaults.object(forKey: key), defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        // Migrate Keychain entries from old service
        let oldService = "com.onthespot.app"
        let keychainKeys = ["openRouterApiKey", "voyageApiKey"]
        for key in keychainKeys {
            if KeychainHelper.load(key: key) == nil,
               let oldValue = Self.loadKeychain(service: oldService, key: key) {
                KeychainHelper.save(key: key, value: oldValue)
            }
        }
    }

    /// Migrate settings from the previous "OpenGranola" (com.opengranola.app) bundle.
    private static func migrateFromOpenGranolaIfNeeded(defaults: UserDefaults) {
        let migrationKey = "didMigrateFromOpenGranola"
        guard !defaults.bool(forKey: migrationKey) else { return }
        defer { defaults.set(true, forKey: migrationKey) }

        // --- Migrate UserDefaults ---
        guard let oldDefaults = UserDefaults(suiteName: "com.opengranola.app") else {
            // Even without old defaults, migrate file-backed state
            migrateFilesFromOpenGranola(defaults: defaults)
            return
        }

        let keysToMigrate = [
            "kbFolderPath", "selectedModel", "transcriptionLocale", "inputDeviceID",
            "llmProvider", "embeddingProvider", "ollamaBaseURL", "ollamaLLMModel",
            "ollamaEmbedModel", "hideFromScreenShare",
            "isTranscriptExpanded", "hasCompletedOnboarding",
            "hasAcknowledgedRecordingConsent"
        ]
        for key in keysToMigrate {
            if let value = oldDefaults.object(forKey: key), defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        // --- Migrate Keychain ---
        let oldService = "com.opengranola.app"
        let keychainKeys = ["openRouterApiKey", "voyageApiKey"]
        for key in keychainKeys {
            if KeychainHelper.load(key: key) == nil,
               let oldValue = Self.loadKeychain(service: oldService, key: key) {
                KeychainHelper.save(key: key, value: oldValue)
            }
        }

        // --- Migrate file-backed state ---
        migrateFilesFromOpenGranola(defaults: defaults)
    }

    /// Migrate file-backed state (sessions, templates, KB cache, transcripts)
    /// from ~/Library/Application Support/OpenGranola/ to OpenOats/ and
    /// handle the implicit KB folder default.
    private static func migrateFilesFromOpenGranola(defaults: UserDefaults) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        let oldAppSupportDir = appSupport.appendingPathComponent("OpenGranola")
        let newAppSupportDir = appSupport.appendingPathComponent("OpenOats")

        // Migrate Application Support: sessions/, templates.json, kb_cache.json
        if fm.fileExists(atPath: oldAppSupportDir.path) {
            try? fm.createDirectory(at: newAppSupportDir, withIntermediateDirectories: true)

            // Sessions directory (JSONL files + sidecars)
            let oldSessions = oldAppSupportDir.appendingPathComponent("sessions")
            let newSessions = newAppSupportDir.appendingPathComponent("sessions")
            if fm.fileExists(atPath: oldSessions.path) && !fm.fileExists(atPath: newSessions.path) {
                try? fm.moveItem(at: oldSessions, to: newSessions)
            }

            // Templates
            let oldTemplates = oldAppSupportDir.appendingPathComponent("templates.json")
            let newTemplates = newAppSupportDir.appendingPathComponent("templates.json")
            if fm.fileExists(atPath: oldTemplates.path) && !fm.fileExists(atPath: newTemplates.path) {
                try? fm.moveItem(at: oldTemplates, to: newTemplates)
            }

            // KB embedding cache
            let oldCache = oldAppSupportDir.appendingPathComponent("kb_cache.json")
            let newCache = newAppSupportDir.appendingPathComponent("kb_cache.json")
            if fm.fileExists(atPath: oldCache.path) && !fm.fileExists(atPath: newCache.path) {
                try? fm.moveItem(at: oldCache, to: newCache)
            }
        }

        // KB folder: leave unset by default. Only preserve an explicitly-set path
        // that pointed at the old OpenGranola directory (user chose it themselves).
        let oldDocDir = home.appendingPathComponent("Documents/OpenGranola")
        let newDocDir = home.appendingPathComponent("Documents/OpenOats")

        // Migrate notes folder: if the old default directory has content,
        // use it as the notes folder so transcript archives stay accessible.
        if defaults.string(forKey: "notesFolderPath") == nil {
            if fm.fileExists(atPath: oldDocDir.path) {
                let contents = (try? fm.contentsOfDirectory(atPath: oldDocDir.path)) ?? []
                if !contents.isEmpty {
                    defaults.set(oldDocDir.path, forKey: "notesFolderPath")
                }
            }
        }

        // Migrate transcript archives: move files from ~/Documents/OpenGranola/
        // into ~/Documents/OpenOats/ so new sessions and old archives coexist.
        // Skip if the old dir is the active KB folder or notes folder (files stay in place).
        let activeKB = defaults.string(forKey: "kbFolderPath") ?? ""
        let activeNotes = defaults.string(forKey: "notesFolderPath") ?? ""
        if fm.fileExists(atPath: oldDocDir.path) && oldDocDir.path != activeKB && oldDocDir.path != activeNotes {
            try? fm.createDirectory(at: newDocDir, withIntermediateDirectories: true)
            if let files = try? fm.contentsOfDirectory(at: oldDocDir, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension == "txt" {
                    let dest = newDocDir.appendingPathComponent(file.lastPathComponent)
                    if !fm.fileExists(atPath: dest.path) {
                        try? fm.moveItem(at: file, to: dest)
                    }
                }
            }
        }
    }

    /// Read a keychain entry from a specific service (used for migration only).
    private static func loadKeychain(service: String, key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Apply current screen-share visibility to all app windows.
    func applyScreenShareVisibility() {
        let type: NSWindow.SharingType = hideFromScreenShare ? .none : .readOnly
        for window in NSApp.windows {
            window.sharingType = type
        }
    }

    var kbFolderURL: URL? {
        guard !kbFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: kbFolderPath)
    }

    var locale: Locale {
        Locale(identifier: transcriptionLocale)
    }

    /// The model name to display in the UI, respecting the active LLM provider.
    var activeModelDisplay: String {
        let raw: String
        switch llmProvider {
        case .openRouter: raw = selectedModel
        case .ollama: raw = ollamaLLMModel
        }
        return raw.split(separator: "/").last.map(String.init) ?? raw
    }

}

// MARK: - Keychain Helper

enum KeychainHelper {
    private static let service = "com.openoats.app"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
