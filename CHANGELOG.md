# Changelog

All notable changes to OpenOats will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Swift 6.2 Strict Concurrency Support** - Full compliance with Swift 6.2 strict concurrency checking
  - Actor-based UseCases (`ExportTranscriptUseCase`, `GenerateNotesUseCase`, `ImportAudioUseCase`, `StartSessionUseCase`, `StopSessionUseCase`, `SwitchBackendUseCase`)
  - Sendable conformance for all Domain entities and ValueObjects
  - Actor-isolated infrastructure services (MLX, WhisperKit, AssemblyAI transcription)
  - Protocol-based Dependency Injection with `DIContainer`, `UseCaseFactory`, and `ViewModelFactory`
- **Clean Architecture Implementation** - 5-layer architecture following Clean Architecture principles
  - Domain layer: Entities, Errors, ValueObjects (zero external dependencies)
  - Business layer: UseCases with actor-based state isolation
  - Infrastructure layer: Services, Protocols, Actors for external concerns
  - Presentation layer: ViewModels with `@MainActor` isolation
  - DI layer: Container and Factories for composition root
- **Multi-Backend Transcription Abstraction** - Runtime backend switching
  - MLX (local, Apple Silicon optimized)
  - WhisperKit (local, CoreML)
  - AssemblyAI (cloud)
  - Backend fallback chain for reliability

### Fixed
- **Swift 6 Concurrency Issues**
  - Fixed `[weak self]` anti-pattern in `ImportAudioUseCase` actor context
  - Documented `@unchecked Sendable` in `MLXTranscriptionService` with safety rationale
  - Removed redundant `@unchecked Sendable` from `WhisperKitTranscriptionService` actor
  - Fixed `Error?` not Sendable in `NonBlockingProtocols.TranscriptionResult`
  - Fixed `defer` with async calls in `StreamingBufferProtocols`
  - Fixed nonisolated actor state access in `ExportTranscriptUseCase`
- **Security Issues**
  - Fixed URL injection vulnerability in `AssemblyAITranscriptionService` (percent-encoding)
  - API key handling improvements in cloud transcription services
- **Performance Issues**
  - Non-blocking transcription with `TranscriptionTaskManager` actor
  - vDSP-accelerated audio processing in `DSPAudioProcessor`
  - Structured concurrency with proper cancellation in `AudioCaptureTask`

### Changed
- Migrated from monolithic architecture to Clean Architecture with strict layer separation
- All transcription services now implement `TranscriptionService` protocol with `Sendable` conformance
- ViewModels refactored to use protocol-based DI instead of direct dependencies
- Repository protocols now require `Sendable` conformance for Swift 6.2 compatibility

### Documentation
- Added ADR-002: 3-Tier Clean Architecture
- Added ADR-003: Protocol-Based Dependency Injection
- Added ADR-004: Swift 6.2 Strict Concurrency Strategy
- Added ADR-005: Multi-Backend Transcription Abstraction
- Added Architecture Implementation Principles (ARCHITECTURE_PRINCIPLES.md)

## [1.0.0] - 2024-XX-XX

### Added
- Initial release of OpenOats
- Local transcription using Apple Speech framework
- Knowledge base search with embeddings
- Live transcript display
- Auto-saved sessions
- LLM-powered suggestions via OpenRouter or Ollama
- Screen sharing exclusion (invisible to other participants)
- macOS 15+ support with SwiftUI interface

### Security
- On-device transcription (no audio leaves device)
- API key storage in macOS Keychain
- Local file storage in `~/Documents/OpenOats/`

