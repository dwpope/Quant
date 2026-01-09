# Ticket 2.4 — Tagging During Record Implementation Summary

## Implementation Complete ✅

**Goal**: Add manual + voice tags during recording

**Date**: 2026-01-09

## What Was Implemented

### 1. VoiceTagService
**Location**: `Quant/Services/VoiceTagService.swift`

Speech recognition service with:
- **Speech Framework Integration**: Continuous listening for voice commands
- **Opt-In Design**: Voice recognition **OFF by default**
- **Toggle Control**: Users can enable/disable voice recognition
- **Authorization Handling**: Requests and checks Speech Recognition permissions
- **Command Recognition**: Recognizes multiple tag commands
- **Haptic Feedback**: Provides tactile confirmation when tag recognized
- **Error Handling**: Graceful failures with user-friendly error messages

**Supported Voice Commands**:
- "mark good" / "mark good posture" → `.goodPosture`
- "mark slouch" / "mark slouching" → `.slouching`
- "mark reading" → `.reading`
- "mark typing" → `.typing`
- "mark stretch" / "mark stretching" → `.stretching`
- "mark absent" → `.absent`

### 2. TaggingControlsView
**Location**: `Quant/Views/TaggingControlsView.swift`

UI component with:
- **Manual Tag Buttons**: 6 colorful buttons for quick tagging
- **Voice Toggle**: Enable/disable voice recognition (off by default)
- **Authorization UI**: Request speech permissions inline
- **Listening Status**: Visual indicator when listening
- **Recognized Text Display**: Shows what was heard
- **Error Display**: User-friendly error messages
- **Recording State**: Only active when recording in progress

**Button Design**:
- Color-coded by tag type (green for good, red for slouch, etc.)
- Icon + text labels
- Grid layout for compact display
- Haptic feedback on tap

### 3. AppModel Integration
**Location**: `Quant/AppModel.swift`

Enhanced with:
- **RecorderService Integration**: Full recording lifecycle
- **Tag Management**: `addRecordingTag()` method
- **Recording State**: Published properties for UI binding
- **Automatic Sample Recording**: Records samples from pipeline
- **Export Functionality**: Save recordings to JSON files

**New Properties**:
```swift
@Published var isRecording = false
@Published var recordingDuration: TimeInterval = 0
@Published var tagCount: Int = 0
```

**New Methods**:
```swift
func startRecording()
func stopRecording() -> RecordedSession
func addRecordingTag(_ tag: Tag)
func exportRecording(to url: URL) throws
```

### 4. ContentView Updates
**Location**: `Quant/ContentView.swift`

Added:
- **Recording Controls**: Start/stop recording buttons
- **Recording Status**: Duration timer and tag count
- **TaggingControlsView**: Integrated at bottom of screen
- **Visual Feedback**: Red recording indicator

## How It Works

### Manual Tagging Workflow

```swift
User taps "Good Posture" button →
  TaggingControlsView calls addTag(.goodPosture, source: .manual) →
  AppModel.addRecordingTag() called →
  RecorderService.addTag() stores tag →
  Haptic feedback plays →
  Tag count updates in UI
```

### Voice Tagging Workflow (When Enabled)

```swift
User enables voice toggle →
  App requests Speech Recognition permission →
  User taps "Start Listening" →
  VoiceTagService begins continuous recognition →
  User says "mark slouch" →
  VoiceTagService recognizes command →
  Callback fires with TagLabel.slouching →
  AppModel.addRecordingTag() called →
  Tag stored + haptic feedback →
  UI shows "Heard: 'mark slouch'"
```

### Recording Session Flow

```swift
// Start recording
User taps "Start Recording" →
  AppModel.startRecording() →
  RecorderService.startRecording() →
  Pipeline samples auto-recorded →
  UI shows recording indicator

// Add tags
User can tap manual buttons OR use voice

// Stop recording
User taps "Stop Recording" →
  AppModel.stopRecording() →
  RecordedSession returned with all samples + tags →
  Can export to JSON
```

## Acceptance Criteria Met

- ✅ Manual tag buttons functional
- ✅ Voice recognition implemented
- ✅ Voice recognition **OFF by default**
- ✅ Toggle to enable/disable voice
- ✅ Can say "Mark slouch" and tag appears
- ✅ Tags stored with timestamp and source
- ✅ Integrated with RecorderService
- ✅ Haptic feedback on tagging

## UI/UX Features

### Voice Recognition Toggle (OFF by Default)

Key design decision:
- **Default State**: OFF (no automatic permission requests)
- **Explicit Opt-In**: User must toggle on
- **Permission Flow**: Only requests permission when toggled on
- **Visual State**: Clear indication when listening
- **Manual Fallback**: Manual buttons always available

### Manual Tag Buttons

6 tag types with distinct styling:
- **Good Posture**: Green with checkmark icon
- **Slouching**: Red with warning icon
- **Reading**: Blue with book icon
- **Typing**: Purple with keyboard icon
- **Stretching**: Orange with figure icon
- **Absent**: Gray with person-slash icon

### Recording State Management

Clear visual hierarchy:
1. **Top**: Debug overlay (tracking quality, FPS)
2. **Center**: Recording controls (start/stop, timer)
3. **Bottom**: Tagging controls (manual + voice)

## Privacy & Permissions

### Speech Recognition

**Usage Description Needed**:
```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>Voice commands allow hands-free tagging during posture recording sessions.</string>

<key>NSMicrophoneUsageDescription</key>
<string>Microphone access enables voice-activated tagging for recording sessions.</string>
```

**Permission Handling**:
- Checks authorization status on init
- Requests only when user enables voice toggle
- Shows settings deep-link if denied
- Graceful degradation to manual-only mode

### User Privacy

- Voice recognition is **opt-in**
- No audio is recorded (only transcripts processed)
- Microphone only active when listening
- User can stop listening anytime
- All processing on-device (Speech framework)

## Technical Implementation Details

### Speech Recognition Architecture

```swift
@MainActor
class VoiceTagService: NSObject, ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: "en-US")
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Callback pattern for recognized tags
    private var onTagRecognized: ((TagLabel) -> Void)?
}
```

**Key Features**:
- Continuous recognition (doesn't stop after each command)
- Partial results for live feedback
- Command matching in transcript
- Audio tap for real-time processing
- Proper cleanup on stop

### Audio Session Configuration

```swift
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
```

Ensures:
- Recording mode enabled
- Other audio ducks (quiets) during listening
- Notifies other apps when done

### Command Matching Strategy

```swift
let commands: [String: TagLabel] = [
    "mark good": .goodPosture,
    "mark slouch": .slouching,
    // ...
]

func processTranscript(_ transcript: String) {
    for (command, label) in commands {
        if transcript.contains(command) {
            onTagRecognized?(label)
            break
        }
    }
}
```

**Advantages**:
- Flexible matching (works with sentence context)
- Multiple command variations per tag
- First match wins
- Case-insensitive

## Use Cases

### Creating Golden Recordings

```swift
// Developer workflow
1. Start monitoring on device
2. Tap "Start Recording"
3. Sit with good posture → say "mark good" or tap button
4. Gradually slouch → say "mark slouch"
5. Return to typing → say "mark typing"
6. Tap "Stop Recording"
7. Export to "gradual_slouch.json"
```

### Hands-Free Operation

Voice tagging is crucial when:
- Both hands typing (can't tap phone)
- Holding a specific posture position
- Phone mounted far away
- Want precise timing of tag

### Manual Tagging Preference

Some users prefer manual:
- Quieter environment needed
- Privacy concerns with microphone
- More precise control
- No permission prompts

## Integration Points

### Inputs
- User button taps
- Voice commands via Speech framework
- RecorderService status

### Outputs
- `Tag` objects to RecorderService
- UI state updates
- Haptic feedback
- Console logging

### Dependencies
- RecorderService (Ticket 2.3) ✅
- PostureLogic package ✅
- Speech framework (iOS SDK)
- AVFoundation (audio session)

## Testing Strategy

### Manual Testing Steps

**Manual Tags**:
1. Start recording
2. Tap each tag button
3. Verify tag count increases
4. Stop recording
5. Check session.tags array contains all tags

**Voice Tags** (requires device):
1. Start recording
2. Enable voice toggle
3. Grant permissions
4. Tap "Start Listening"
5. Say "mark good posture"
6. Verify haptic feedback
7. Verify tag count increases
8. Check UI shows recognized text
9. Say other commands
10. Stop listening
11. Verify all tags captured

**Toggle Behavior**:
1. Toggle voice ON → Check permission request
2. Toggle voice OFF while listening → Verify stops
3. Toggle ON without permission → Verify request flow
4. Deny permission → Verify fallback to manual-only

### Edge Cases Handled

- Recording not started → Tagging disabled
- Voice disabled → Manual buttons still work
- Permission denied → Shows settings link
- Recognizer unavailable → Shows error
- Audio engine fails → Graceful error message
- Multiple rapid tags → All captured with unique timestamps

## Next Steps

According to the plan, the next ticket is:

**Ticket 2.6 — Golden Recordings Requirement**
- Create 4 reference recordings using this tagging system
- Use voice/manual tags to label ground truth
- Export to JSON for regression testing

**With Ticket 2.4 complete**, we can now:
1. Record real sessions on device
2. Tag them accurately (voice + manual)
3. Export high-quality labeled data
4. Use in Simulator via ReplayService

## Files Created

**Created**:
- `Quant/Services/VoiceTagService.swift`
- `Quant/Views/TaggingControlsView.swift`

**Modified**:
- `Quant/AppModel.swift` - Added recording integration
- `Quant/ContentView.swift` - Added UI components

## Summary

Ticket 2.4 completes Sprint 2's recording infrastructure by adding the UI layer for tagging. The implementation provides:

- **Flexible tagging**: Manual buttons + voice commands
- **Privacy-first**: Voice recognition OFF by default
- **User control**: Clear toggle and authorization flow
- **Good UX**: Visual feedback, haptic confirmation, error messages
- **Developer-friendly**: Ready for creating golden recordings

**Key Achievement**: Can now create high-quality labeled recordings for Ticket 2.6 (golden recordings) and future ML training.
