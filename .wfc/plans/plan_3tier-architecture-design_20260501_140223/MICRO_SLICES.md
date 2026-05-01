# Parallel Implementation - Smaller Slices

## Problem
Original slices were too large (6 use cases in one agent, 4 ViewModels in one agent).

## Solution
Break down into **micro-slices** - one concern per agent.

## New Structure

### Stream 2: Business Logic (6 Micro-Slices)
Instead of 1 agent for all 6 use cases:
- **Slice 2A**: StartSessionUseCase (1 use case)
- **Slice 2B**: StopSessionUseCase (1 use case)
- **Slice 2C**: GenerateNotesUseCase (1 use case)
- **Slice 2D**: ExportTranscriptUseCase (1 use case)
- **Slice 2E**: ImportAudioUseCase (1 use case)
- **Slice 2F**: SwitchBackendUseCase (1 use case)

### Stream 3: Infrastructure (5 Micro-Slices)
Instead of 1 agent for all services:
- **Slice 3A**: TranscriptionService protocol + mock
- **Slice 3B**: AudioCaptureService implementation
- **Slice 3C**: SessionRepository (CoreData/SwiftData)
- **Slice 3D**: TranscriptRepository
- **Slice 3E**: SettingsRepository

### Stream 4: Presentation (4 Micro-Slices)
Instead of 1 agent for all ViewModels:
- **Slice 4A**: SessionViewModel
- **Slice 4B**: TranscriptViewModel
- **Slice 4C**: SettingsViewModel
- **Slice 4D**: IdleDashboardViewModel

### Stream 5: Critical Fixes (Already granular)
- **Slice 5A**: Data races (already separate)
- **Slice 5B**: Memory management (already separate)
- **Slice 5C**: Performance (already separate)

## Benefits of Smaller Slices

1. **Faster Feedback**: Each slice completes in minutes, not hours
2. **Easier Review**: 1 concern = 1 PR
3. **Better Isolation**: Failures don't block other slices
4. **Parallelizable**: 20+ agents can run simultaneously
5. **Clear Handoffs**: Each slice has explicit input/output

## Execution Order

### Phase 1: Foundation (Sequential)
1. Slice 2A: StartSessionUseCase (foundation for others)

### Phase 2: Parallel Core (All at once)
2. Slices 2B-2F: Other use cases (parallel)
3. Slices 3A-3E: Infrastructure (parallel)
4. Slices 4A-4D: ViewModels (parallel)
5. Slices 5A-5C: Critical fixes (parallel)

### Phase 3: Integration (After all above)
6. Slice 6A: DI Container
7. Slice 6B: Backend implementations (MLX, WhisperKit, etc.)

## TDD Per Micro-Slice

Each micro-slice still follows 3-phase TDD:
1. **RED**: Write tests for this ONE concern
2. **GREEN**: Implement to pass tests
3. **REFACTOR**: Run EEDOM + fix issues

## Example: Slice 2A (StartSessionUseCase)

**Agent A (Test)**:
- Write 15 property-based tests for StartSessionUseCase
- Test: idempotency, error handling, cancellation
- Output: Failing tests

**Agent B (Implement)**:
- Implement StartSessionUseCase
- Make 15 tests pass
- Output: Working implementation

**Agent C (Refactor)**:
- Run EEDOM on StartSessionUseCase
- Fix any issues
- Output: Clean code + EEDOM report

**Total time**: ~30 minutes vs 3 hours for all 6 use cases
