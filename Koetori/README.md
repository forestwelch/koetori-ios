# Koetori iOS App

Voice memo recording app with background processing support.

## Setup Instructions

### 1. Open Xcode Project

1. Open `Koetori.xcodeproj` in Xcode
2. All source files are already in `Koetori/Koetori/` directory

### 2. Add Files to Xcode Project

The files are in the filesystem but need to be added to the Xcode project:

1. In Xcode, right-click on the `Koetori` folder (blue icon) in the Project Navigator
2. Select "Add Files to Koetori..."
3. Navigate to `Koetori/Koetori/` and select:
   - All folders: `Views/`, `Services/`, `Models/`, `Extensions/`
   - `Info.plist`
4. Make sure "Copy items if needed" is **unchecked** (files are already in place)
5. Make sure "Create groups" is selected
6. Click "Add"

**Note**: `KoetoriApp.swift` should already be in the project. If `ContentView.swift` appears, delete it from the project (we use `RecordingView` instead).

### 3. Configure Project Settings

In Xcode project settings:

**General Tab:**

- Minimum Deployment: iOS 17.0
- Supported Destinations: iPhone

**Signing & Capabilities:**

- Add your Apple ID for automatic signing (free provisioning)
- Add Capabilities:
  - Background Modes:
    - ✅ Audio, AirPlay, and Picture in Picture
    - ✅ Uses Bluetooth LE accessories
    - ✅ Background fetch

**Info Tab:**

- The `Info.plist` file already contains the required keys:
  - `NSMicrophoneUsageDescription`: "Koetori records voice memos"
  - `NSBluetoothAlwaysUsageDescription`: "Koetori connects to your recording device"
  - `UIBackgroundModes`: Array with "audio", "bluetooth-central", "fetch"
- If Xcode doesn't recognize the plist, you may need to add these keys manually in the Info tab

### 4. Build and Run

- Connect your iPhone
- Select your device as the build target
- Build and run (⌘R)

## Project Structure

```
koetori-ios/
└── Koetori/
    ├── Koetori.xcodeproj/    # Xcode project file
    ├── Koetori/              # Source files directory
    │   ├── KoetoriApp.swift  # App entry point
    │   ├── Info.plist        # App configuration
    │   ├── Assets.xcassets/  # App icons and assets
    │   ├── Views/
    │   │   ├── RecordingView.swift   # Main recording screen
    │   │   ├── ResultsView.swift     # Results display sheet
    │   │   └── Components/
    │   │       ├── RecordButton.swift
    │   │       ├── MemoCard.swift
    │   │       └── CategoryBadge.swift
    │   ├── Services/
    │   │   ├── AudioRecorder.swift   # AVFoundation wrapper
    │   │   └── APIService.swift      # API upload service
    │   ├── Models/
    │   │   ├── APIResponse.swift
    │   │   ├── Memo.swift
    │   │   └── Category.swift
    │   └── Extensions/
    │       └── Color+Theme.swift
    └── README.md
```

## Features

- ✅ Voice recording with AVAudioRecorder
- ✅ M4A format (AAC encoding) for small file sizes
- ✅ Multipart form-data upload to API
- ✅ Results display with transcript and memos
- ✅ Error handling and permission requests
- ✅ Dark theme UI with custom colors
- ✅ Smooth animations and haptic feedback

## Testing

- **Important**: Test on a real iPhone, not the simulator
- Microphone access is limited in the simulator
- Free provisioning allows 7-day signing (Xcode auto-renews)

## Next Steps (Phase 2)

- BLE device integration
- Background processing for locked device recording
- Background URLSession for uploads
