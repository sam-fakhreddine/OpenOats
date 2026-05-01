# macOS Design Patterns & Resources for OpenOats

> **Reference Document**: Apple Design Guidelines for OpenOats Transcription App  
> **Source**: https://developer.apple.com/design/resources/  
> **Last Updated**: 2026-05-01  
> **macOS Version**: macOS 26 (with Liquid Glass), macOS Sequoia compatibility

---

## Table of Contents

1. [macOS UI Patterns](#1-macos-ui-patterns)
2. [SF Symbols Usage](#2-sf-symbols-usage)
3. [Typography & Layout](#3-typography--layout)
4. [Color & Appearance](#4-color--appearance)
5. [Icon Design](#5-icon-design)
6. [Accessibility](#6-accessibility)
7. [OpenOats-Specific Recommendations](#7-openoats-specific-recommendations)

---

## 1. macOS UI Patterns

### 1.1 Menu Bar App Design Guidelines

**Menu Bar Extra (Status Bar Apps)**
- Use `MenuBarExtra` in SwiftUI or `NSStatusBar` in AppKit
- Menu bar icons should be **template images** (monochrome, single color)
- Recommended icon size: **18×18 points** (36×36 pixels @2x)
- Icons should be visible in both Light and Dark modes
- Provide clear visual feedback for active states (e.g., recording indicator)

**Key Principles:**
- Menu bar apps should be glanceable and non-intrusive
- Critical status information should be visible at a glance
- Use dropdown menus for additional controls and settings
- Consider using the new **Live Activities** support (macOS 26) for real-time transcription status

**Implementation for OpenOats:**
```swift
// SwiftUI MenuBarExtra example
MenuBarExtra("OpenOats", systemImage: "waveform") {
    ContentView()
}
```

### 1.2 Window Management Patterns

**Primary Window Types:**
- **Standard Windows**: Document-based or utility windows
- **Floating Panels**: For tools or secondary controls
- **Popovers**: For contextual information and quick actions

**Window Behavior Guidelines:**
- Support **resizable windows** (modern macOS apps should be adaptive)
- Implement proper **window restoration** for user session continuity
- Use **tabbed interfaces** for multiple transcription sessions
- Support **split view** for comparing transcriptions side-by-side

**Liquid Glass Considerations (macOS 26+):**
- New dynamic material combining glass optical properties with fluidity
- Refracts content from below, reflects ambient light
- Use for elevated UI elements with subtle depth
- **Recommendation**: Use Liquid Glass materials for transcription player controls and waveform display containers

### 1.3 Settings/Preferences UI Patterns

**Settings Window Structure:**
- Use **toolbar-based navigation** for settings categories
- Organize into logical sections:
  - General (default audio device, output folder)
  - Recording (quality, auto-start, shortcuts)
  - Transcription (AI model, language, formatting)
  - Shortcuts (keyboard bindings)
  - Account (API keys, usage)

**Best Practices:**
- Use **descriptive labels** with concise helper text
- Implement **search** in settings (standard macOS pattern)
- Use **toggles** for binary settings, **pop-up buttons** for multiple choices
- Provide **default values** and "Reset to Defaults" option

**SwiftUI Implementation:**
```swift
Settings {
    TabView {
        GeneralSettingsView()
            .tabItem { Label("General", systemImage: "gear") }
        RecordingSettingsView()
            .tabItem { Label("Recording", systemImage: "mic") }
    }
}
```

### 1.4 Toolbar and Sidebar Patterns

**Toolbar Guidelines:**
- Use **SF Symbols** for toolbar icons
- Group related actions with **spacers**
- Include **search fields** when appropriate
- Support **customization** via View > Customize Toolbar

**Sidebar (Navigation Split View):**
- Use for organizing transcription files/folders
- Support **collapsible sections**
- Include **badges** for status indicators (e.g., "Recording...", "Processing")
- Use **contextual menus** for right-click actions

**Recommended Toolbar Items for OpenOats:**
```
[Record Button] [Stop Button] | [Search Field] | [Settings] [Share]
```

### 1.5 Modal vs Non-Modal Windows

**Use Modal Windows (Sheets/Alerts) For:**
- Critical user confirmations (delete transcription, stop recording)
- First-run setup or onboarding
- Authentication dialogs
- Export/save location selection

**Use Non-Modal For:**
- Real-time transcription display
- Audio playback controls
- Settings adjustments
- File management

**Best Practices:**
- Keep modal interruptions minimal - transcription is a continuous workflow
- Use **sheets** attached to parent windows rather than standalone dialogs
- Provide **keyboard shortcuts** to dismiss modals (⌘. or Escape)

---

## 2. SF Symbols Usage

### 2.1 Recording-Related Symbols

| Symbol Name | Usage Context | macOS Availability |
|-------------|---------------|-------------------|
| `mic` | Start recording / recording source | 11.0+ |
| `mic.fill` | Active recording state | 11.0+ |
| `mic.slash` | Microphone muted/disabled | 11.0+ |
| `stop.circle` | Stop recording | 11.0+ |
| `stop.fill` | Stop button (active) | 11.0+ |
| `record.circle` | Record button | 11.0+ |
| `record.circle.fill` | Recording in progress | 11.0+ |
| `waveform` | Audio waveform indicator | 14.0+ |
| `waveform.circle` | Waveform display | 14.0+ |
| `waveform.path` | Audio signal indicator | 14.0+ |
| `waveform.badge.mic` | Recording with waveform | 14.0+ |
| `waveform.badge.plus` | Add audio | 14.0+ |

**OpenOats Recommendations:**
```swift
// Menu bar icon for recording state
Image(systemName: isRecording ? "waveform.badge.mic" : "mic")

// Toolbar record button
Button(action: startRecording) {
    Label("Record", systemImage: "record.circle")
}
```

### 2.2 Meeting/Transcription Symbols

| Symbol Name | Usage Context | macOS Availability |
|-------------|---------------|-------------------|
| `doc.text` | Transcription document | 11.0+ |
| `doc.text.fill` | Active transcription | 11.0+ |
| `doc.on.doc` | Duplicate/copy transcription | 11.0+ |
| `text.bubble` | Speaker identification | 11.0+ |
| `quote.bubble` | Quote/highlight | 11.0+ |
| `person.wave.2` | Speaker diarization | 14.0+ |
| `person.2` | Multiple speakers | 11.0+ |
| `person.2.fill` | Speaker count | 11.0+ |
| `clock` | Timestamp | 11.0+ |
| `calendar` | Meeting date | 11.0+ |
| `text.alignleft` | Transcript view | 11.0+ |
| `text.quote` | Quote formatting | 14.0+ |

### 2.3 Status Indicators

| Symbol Name | Usage Context | Weight/Style |
|-------------|---------------|--------------|
| `circle.fill` | Recording dot (red) | Fill + Red |
| `ellipsis` | Processing | Regular |
| `ellipsis.circle` | Processing detailed | Regular |
| `checkmark.circle.fill` | Complete | Fill + Green |
| `checkmark` | Done | Regular |
| `exclamationmark.triangle.fill` | Warning | Fill + Yellow |
| `xmark.circle.fill` | Error/Failed | Fill + Red |
| `arrow.down.circle.fill` | Downloading | Fill |
| `arrow.up.circle.fill` | Uploading | Fill |
| `sparkles` | AI processing | Regular |
| `wand.and.stars` | AI enhancement | Regular |

**Processing State Animations (SF Symbols 7):**
```swift
// Use Draw animations for loading states
Image(systemName: "ellipsis")
    .symbolEffect(.variableColor.iterative.reversing)
```

### 2.4 Navigation Symbols

| Symbol Name | Usage Context |
|-------------|---------------|
| `sidebar.left` | Toggle sidebar |
| `play` | Play audio |
| `pause` | Pause audio |
| `gobackward` | Skip backward 10s |
| `goforward` | Skip forward 10s |
| `speaker.wave.1` | Low volume |
| `speaker.wave.2` | Medium volume |
| `speaker.wave.3` | High volume |
| `speaker.slash` | Muted |
| `gear` | Settings |
| `square.and.arrow.up` | Share/Export |
| `magnifyingglass` | Search |
| `trash` | Delete |
| `folder` | Open folder |
| `arrow.clockwise` | Refresh/Reload |

### 2.5 SF Symbols Implementation Guidelines

**Rendering Modes:**
- **Monochrome**: Single color (default for macOS)
- **Hierarchical**: Multiple shades of one color
- **Palette**: Multiple distinct colors
- **Multicolor**: Predefined semantic colors

**Animation Support (SF Symbols 7):**
- **Draw On/Draw Off**: Calligraphic-style entry/exit animations
- **Wiggle**: Attention-grabbing animation
- **Rotate**: Continuous rotation
- **Breathe**: Subtle pulsing
- **Pulse**: Stronger pulsing effect
- **Variable Color**: Progress/level indication

**Best Practices:**
```swift
// Use appropriate weights for context
Image(systemName: "mic")
    .font(.system(size: 16, weight: .semibold))

// Template rendering for toolbar/menu bar
Image(systemName: "waveform")
    .renderingMode(.template)

// Animated recording indicator
Image(systemName: "waveform.badge.mic")
    .symbolEffect(.variableColor)
```

---

## 3. Typography & Layout

### 3.1 SF Pro Font Usage Guidelines

**System Font:** SF Pro is the system font for macOS
- **9 weights**: Ultralight, Light, Thin, Regular, Medium, Semibold, Bold, Heavy, Black
- **Variable optical sizes**: Automatically adjusts spacing/proportion based on point size
- **Supports 150+ languages**: Latin, Greek, Cyrillic scripts

**Font Selection for OpenOats:**

| UI Element | Font | Size | Weight |
|------------|------|------|--------|
| Window Title | SF Pro | 13pt | Semibold |
| Toolbar | SF Pro | 11pt | Regular |
| Sidebar Items | SF Pro | 12pt | Regular |
| Transcription Text | SF Pro | 13pt | Regular |
| Speaker Labels | SF Pro | 11pt | Medium |
| Timestamps | SF Pro | 10pt | Regular |
| Status Text | SF Pro | 11pt | Regular |
| Buttons | SF Pro | 12pt | Medium |
| Headings | SF Pro | 15pt | Semibold |

### 3.2 Dynamic Type Support

**Why Dynamic Type Matters:**
- Users can change text size in System Settings > Display > Text
- Essential for accessibility
- Apps should respond to `UIContentSizeCategory` changes

**Implementation:**
```swift
// SwiftUI automatically supports Dynamic Type
Text("Transcription text")
    .font(.body)

// Custom sizing with Dynamic Type support
Text("Speaker Name")
    .font(.system(.subheadline, design: .default, weight: .medium))
```

**Size Categories:**
| Category | Multiplier | Use Case |
|----------|-----------|----------|
| xSmall | -3 | Compact displays |
| Small | -2 | - |
| Medium | -1 | Default content |
| Large | 0 | Default (base) |
| xLarge | +1 | - |
| xxLarge | +2 | Accessibility |
| xxxLarge | +3 | Maximum accessibility |
| AX1-AX5 | +4 to +11 | High contrast needs |

### 3.3 Layout Grids and Spacing

**macOS Standard Spacing:**
- **8-point grid**: Base unit for all spacing
- **Standard padding**: 16pt (2× base)
- **Compact padding**: 8pt (1× base)
- **Wide padding**: 24pt (3× base)

**Common Layout Values:**
```
Toolbar height: 52pt
Sidebar width: 200-320pt (resizable)
Button height: 20-32pt
Text field height: 22pt
Table row height: 20-44pt (variable)
Segmented control height: 20pt
```

**Transcription View Layout:**
```
┌─────────────────────────────────────────────────────┐
│  Toolbar (52pt)                                     │
├──────────────┬──────────────────────────────────────┤
│              │  Content Area                        │
│  Sidebar     │  ┌────────────────────────────────┐  │
│  (240pt)     │  │  Transcription Text             │  │
│              │  │  (comfortable line spacing)       │  │
│              │  └────────────────────────────────┘  │
│              │                                      │
└──────────────┴──────────────────────────────────────┘
```

### 3.4 macOS-Specific Sizing

**Window Sizes:**
- **Minimum window**: 400×300pt
- **Default transcription window**: 900×600pt
- **Settings window**: 600×400pt
- **Floating player**: 400×80pt

**Control Sizes:**
- **Small**: 16pt height (compact UIs)
- **Regular**: 20pt height (default)
- **Large**: 24pt height (emphasized actions)

**Button Dimensions:**
```swift
// Primary action button
Button("Start Recording") {}
    .controlSize(.large)

// Toolbar button
Button {} label: { Image(systemName: "gear") }
    .controlSize(.regular)
```

---

## 4. Color & Appearance

### 4.1 Light/Dark Mode Adaptation

**System Color Sets:**
macOS automatically provides appropriate colors for current appearance

| Semantic Color | Light Mode | Dark Mode | Usage |
|----------------|------------|-----------|-------|
| `.label` | Black | White | Primary text |
| `.secondaryLabel` | Dark gray | Light gray | Secondary text |
| `.tertiaryLabel` | Medium gray | Medium gray | Disabled/tertiary |
| `.quaternaryLabel` | Light gray | Dark gray | Very subtle |
| `.textBackgroundColor` | White | Dark gray | Text backgrounds |
| `.windowBackgroundColor` | #F0F0F0 | #1E1E1E | Window chrome |
| `.controlBackgroundColor` | White | #2D2D2D | Controls |
| `.selectedContentBackgroundColor` | Blue accent | Blue accent | Selection |
| `.unemphasizedSelectedContentBackgroundColor` | Light gray | Dark gray | Unfocused selection |

**Implementation:**
```swift
// Automatic adaptation
Text("Transcription text")
    .foregroundColor(.primary)

// Using system colors
Rectangle()
    .fill(Color(.windowBackgroundColor))
```

### 4.2 Accent Colors

**System Accent Colors:**
Users can set system accent color in System Settings

| Color | System Name | Use |
|-------|-------------|-----|
| Blue | `.blue` | Default accent |
| Purple | `.purple` | - |
| Pink | `.pink` | - |
| Red | `.red` | Errors, recording |
| Orange | `.orange` | Warnings |
| Yellow | `.yellow` | Caution |
| Green | `.green` | Success, complete |
| Graphite | `.gray` | Neutral |

**OpenOats Recommendations:**
- Use **Blue** as default accent for consistency
- Use **Red** for recording indicators (`record.circle.fill`)
- Use **Green** for completion states (`checkmark.circle.fill`)
- Use **Yellow** for processing/warning states
- Consider allowing user to customize accent color

### 4.3 System Color Usage

**Semantic Colors for Transcription App:**

```swift
// Recording status - Always red regardless of accent
Circle()
    .fill(Color.red)
    .frame(width: 8, height: 8)

// Processing indicator - Use accent color
ProgressView()
    .tint(.accentColor)

// Success state - Always green
Image(systemName: "checkmark.circle.fill")
    .foregroundColor(.green)

// Error state - Always red
Image(systemName: "exclamationmark.triangle.fill")
    .foregroundColor(.red)
```

### 4.4 Vibrancy and Materials

**Material Types (macOS):**

| Material | Use Case |
|----------|----------|
| `.ultraThinMaterial` | Overlays on content |
| `.thinMaterial` | Sidebars, panels |
| `.regularMaterial` | Popovers, menus |
| `.thickMaterial` | Modal sheets |
| `.ultraThickMaterial` | Alerts, critical UI |

**Vibrancy Modes:**
- **Behind window**: Content vibrancy (use sparingly)
- **Within window**: Standard for sidebars/toolbars
- **Titlebar**: Title bar specific

**Liquid Glass Materials (macOS 26+):**
- New dynamic material combining glass properties with fluidity
- Automatically responds to lighting and content below
- Use for:
  - Control panels
  - Floating toolbars
  - Waveform display backgrounds
  - Playback controls

**Implementation:**
```swift
// Standard material
.background(.thinMaterial)

// Liquid Glass (macOS 26+)
.background(.liquidGlass)

// With vibrancy
.visualEffect(.vibrancy, in: .rect)
```

---

## 5. Icon Design

### 5.1 macOS App Icon Guidelines

**Icon Specifications:**

| Size (pt) | Size (px @1x) | Size (px @2x) | Usage |
|-----------|---------------|---------------|-------|
| 16×16 | 16×16 | 32×32 | Finder, lists |
| 32×32 | 32×32 | 64×64 | Finder, previews |
| 128×128 | 128×128 | 256×256 | Finder, dock |
| 256×256 | 256×256 | 512×512 | Quick Look |
| 512×512 | 512×512 | 1024×1024 | App Store, Spotlight |

**Format:**
- Create layered icons using **Icon Composer** (macOS Sequoia+)
- Supports **Liquid Glass** material effects
- Export to `.iconset` or `.icns`

**Design Principles:**
- Use a **recognizable metaphor** (e.g., microphone + waveform for OpenOats)
- Maintain **simplicity** - avoid excessive detail
- Use **rounded corners** (macOS standard: 22% radius)
- Ensure **contrast** in both Light and Dark modes
- Consider **tinted variants** for user customization

### 5.2 Menu Bar Icon Specs

**Status Bar Icon Requirements:**
- **Size**: 18×18 points (36×36 @2x)
- **Style**: Template image (monochrome)
- **Format**: PDF or PNG with alpha
- **Alignment**: Centered within 22×22 point touch target

**States to Design:**
1. **Idle**: Microphone or waveform icon
2. **Recording**: Pulsing/red recording dot
3. **Processing**: Animated activity indicator
4. **Complete**: Checkmark or completion indicator
5. **Error**: Warning symbol

**Template Image Setup:**
```swift
let icon = NSImage(named: "StatusBarIcon")
icon?.isTemplate = true
statusItem.button?.image = icon
```

### 5.3 Template Images

**Creating Template Images:**
- Use solid black (will be tinted by system)
- Include alpha channel for transparency
- Avoid color - system applies vibrancy

**Template Usage Guidelines:**
- Menu bar icons (always template)
- Toolbar icons (typically template)
- Sidebar icons (template or hierarchical)
- Segmented controls (template)

**Dynamic Icons:**
```swift
// Dynamic menu bar icon based on state
func updateStatusIcon() {
    let imageName = isRecording ? "waveform.badge.mic" : "mic"
    let icon = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
    icon?.isTemplate = true
    statusItem.button?.image = icon
}
```

---

## 6. Accessibility

### 6.1 macOS Accessibility Patterns

**Core Principles:**
1. **Perceivable**: Information must be presentable in ways users can perceive
2. **Operable**: Interface components must be operable by all users
3. **Understandable**: Information and operation must be understandable
4. **Robust**: Content must work with assistive technologies

**Essential Implementation Areas:**
- **VoiceOver**: Screen reader support
- **Keyboard Navigation**: Full keyboard control
- **Color Contrast**: Minimum 4.5:1 ratio
- **High Contrast**: Support Increase Contrast setting
- **Reduce Motion**: Respect motion preferences
- **Text Size**: Support Dynamic Type

### 6.2 VoiceOver Support

**Adding Accessibility Labels:**
```swift
// Basic accessibility
Button(action: startRecording) {
    Image(systemName: "record.circle")
}
.accessibilityLabel("Start Recording")
.accessibilityHint("Begins audio recording from selected source")

// Complex UI elements
Text("Transcription content...")
    .accessibilityLabel("Transcribed text from meeting")
    .accessibilityValue("Speaker: John, Duration: 45 seconds")
```

**Live Regions:**
```swift
// Announce status changes
Text(statusMessage)
    .accessibilityLiveRegion(.polite)
    .accessibilityAnnouncementPriority(.high)
```

**Accessibility Actions:**
```swift
// Custom actions for VoiceOver
.accessibilityAction(named: "Skip Backward") {
    skipBackward()
}
.accessibilityAction(named: "Skip Forward") {
    skipForward()
}
```

### 6.3 Keyboard Navigation

**Keyboard Shortcuts:**

| Action | Shortcut | Category |
|--------|----------|----------|
| Start/Stop Recording | ⌘R | Core |
| Pause/Resume | ⌘. | Playback |
| Skip Backward | ⌘← | Navigation |
| Skip Forward | ⌘→ | Navigation |
| Search | ⌘F | Navigation |
| Export | ⌘E | File |
| New Transcription | ⌘N | File |
| Preferences | ⌘, | App |
| Hide App | ⌘H | Window |
| Quit | ⌘Q | App |

**Focus Management:**
```swift
// Programmatic focus
@FocusState private var isSearchFocused: Bool

// Focusable elements
TextField("Search", text: $searchText)
    .focused($isSearchFocused)

// Keyboard navigation group
HStack {
    Button("Record") {}
    Button("Stop") {}
}
.keyboardShortcut(.defaultAction)
```

### 6.4 High Contrast Support

**Increase Contrast Mode:**
- System setting that increases contrast of UI elements
- Test with: System Settings > Accessibility > Display > Increase Contrast

**Implementation:**
```swift
// Use semantic colors (automatically adapt)
.background(Color(.windowBackgroundColor))

// Avoid hardcoded colors
// ❌ Bad
.background(Color.white)

// ✅ Good
.background(Color(.textBackgroundColor))
```

**Differentiate Without Color:**
```swift
// Don't rely solely on color for status
HStack {
    Image(systemName: isRecording ? "record.circle.fill" : "circle")
    Text(isRecording ? "Recording" : "Idle")
}
```

---

## 7. OpenOats-Specific Recommendations

### 7.1 App Architecture

**Recommended Window Structure:**
```
┌─────────────────────────────────────────────────────────────┐
│  Menu Bar Extra (always visible)                            │
│  - Status: Idle/Recording/Processing                        │
│  - Quick controls: Record/Stop, Recent files                 │
│  - Access: Main window, Settings                            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Main Window                                                │
├──────────────┬──────────────────────────────────────────────┤
│  Sidebar     │  Content Area                                │
│  (240pt)     │  ┌─────────────────────────────────────────┐ │
│  - Meetings  │  │  Toolbar                                  │ │
│  - Files     │  │  [Play] [Pause] [<<] [>>] [Speed]       │ │
│  - Search    │  ├─────────────────────────────────────────┤ │
│  - Tags      │  │                                           │ │
│              │  │  Waveform Visualization                   │ │
│              │  │  ┌─────────────────────────────────────┐ │ │
│              │  │  │ ▁▂▃▅▆▇███▇▆▅▃▂▁▁▂▃▅▆▇████▇▆▅▃▂▁ │ │ │
│              │  │  └─────────────────────────────────────┘ │ │
│              │  │                                           │ │
│              │  │  Transcription Text                       │ │
│              │  │  [Speaker 1]: Hello everyone...           │ │
│              │  │  [Speaker 2]: Thanks for joining...       │ │
│              │  │                                           │ │
│              │  └─────────────────────────────────────────┘ │
└──────────────┴──────────────────────────────────────────────┘
```

### 7.2 Recording Flow UX

**Recording State Machine:**

```
[IDLE] ──Record──> [RECORDING] ──Stop──> [PROCESSING] ──Done──> [COMPLETED]
   │                    │                                      │
   │                    │ Error                              │
   │                    ▼                                      │
   │               [ERROR] <───────────────────────────────────┘
   │                    │
   └────────────────────┘ Retry
```

**UI Feedback for Each State:**

| State | Menu Bar | Window | Audio |
|-------|----------|--------|-------|
| Idle | Gray mic icon | Ready state | None |
| Recording | Red pulsing waveform | Recording UI | Input active |
| Processing | Yellow spinner | Progress indicator | None |
| Completed | Green checkmark | Results view | Available for playback |
| Error | Red warning | Error message | None |

### 7.3 Waveform Display Guidelines

**Design Specifications:**
- **Height**: 60-120pt depending on window size
- **Color**: Use accent color or custom brand color
- **Background**: Thin material for depth
- **Playback indicator**: Vertical line with time tooltip

**Accessibility:**
- Provide text alternative for waveform (timecodes)
- Allow keyboard navigation through audio
- Show time remaining/elapsed

### 7.4 Speaker Diarization Display

**Speaker Identification UI:**
```swift
// Speaker label component
HStack(spacing: 8) {
    Circle()
        .fill(speakerColor)
        .frame(width: 8, height: 8)
    Text("Speaker \(index + 1)")
        .font(.caption)
        .fontWeight(.medium)
    Text("(", durationFormatter.string(from: duration), ")")
        .font(.caption)
        .foregroundColor(.secondary)
}
```

**Color Assignment:**
- Assign consistent colors to speakers
- Ensure colorblind-friendly palette
- Add pattern/texture alternatives

### 7.5 Keyboard Shortcuts Reference

**Full Shortcut Map:**

| Category | Action | Shortcut |
|----------|--------|----------|
| **Recording** | | |
| | Start Recording | ⌘R |
| | Stop Recording | ⌘. or ⌘R |
| | Pause (during playback) | Space |
| **Playback** | | |
| | Play/Pause | Space |
| | Skip Backward 10s | ⌘← or ⌘[ |
| | Skip Forward 10s | ⌘→ or ⌘] |
| | Skip to Beginning | ⌘↑ |
| | Skip to End | ⌘↓ |
| | Increase Speed | ⌘+ |
| | Decrease Speed | ⌘- |
| **Navigation** | | |
| | Search Transcription | ⌘F |
| | Next Result | ⌘G |
| | Previous Result | ⌘⇧G |
| | Show/Hide Sidebar | ⌘⌥S |
| **File** | | |
| | New Recording | ⌘N |
| | Open File | ⌘O |
| | Export | ⌘E |
| | Save | ⌘S |
| **View** | | |
| | Zoom In | ⌘+ |
| | Zoom Out | ⌘- |
| | Reset Zoom | ⌘0 |

### 7.6 Recommended Design Resources

**Download from Apple:**
1. **SF Symbols 7** - 6,900+ symbols
   - URL: https://devimages-cdn.apple.com/design/resources/download/SF-Symbols-7.dmg

2. **macOS 26 UI Kit (Figma/Sketch)**
   - Figma: https://www.figma.com/community/file/1543337041090580818/apple-design-resources-macos-26
   - Sketch: https://sketch.com/s/7e5d41a8-dbde-4372-abf1-59792d73bc7c

3. **SF Pro Fonts**
   - URL: https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg

4. **Icon Composer** (for creating layered app icons)
   - Available on Mac App Store

5. **SF Mono** (for code display)
   - URL: https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg

### 7.7 Brand Colors for OpenOats

**Primary Brand Palette:**

| Color | Hex | RGB | Usage |
|-------|-----|-----|-------|
| Oats Blue | #007AFF | 0,122,255 | Primary accent |
| Oats Green | #34C759 | 52,199,89 | Success/completed |
| Oats Red | #FF3B30 | 255,59,48 | Recording/error |
| Oats Yellow | #FFCC00 | 255,204,0 | Processing/warning |
| Oats Gray | #8E8E93 | 142,142,147 | Secondary text |

**Accessibility Compliance:**
- All colors meet WCAG 2.1 AA contrast ratios
- Test with Sim Daltonism for colorblind simulation
- Provide icon/symbol alternatives to color coding

---

## Summary Checklist

### For Implementation

- [ ] Use SF Symbols for all icons
- [ ] Implement Dark Mode support
- [ ] Add VoiceOver labels to all controls
- [ ] Support Dynamic Type
- [ ] Provide full keyboard navigation
- [ ] Design menu bar icon (template, 18pt)
- [ ] Create app icon set (all sizes, Liquid Glass)
- [ ] Test with Increase Contrast mode
- [ ] Implement reduce motion support
- [ ] Add keyboard shortcuts
- [ ] Use semantic colors throughout
- [ ] Follow 8-point grid for spacing
- [ ] Support window resizing
- [ ] Test on multiple screen sizes

### Design Deliverables

- [ ] App icon (512×512 base, all sizes)
- [ ] Menu bar icons (active/inactive states)
- [ ] Toolbar icons (SF Symbols based)
- [ ] Color palette (Light/Dark mode)
- [ ] Typography scale
- [ ] Layout grid specification
- [ ] Recording state flow diagrams
- [ ] Keyboard shortcuts reference

---

**Document End**

*For questions or updates, refer to Apple's official Human Interface Guidelines at developer.apple.com/design/human-interface-guidelines/*
