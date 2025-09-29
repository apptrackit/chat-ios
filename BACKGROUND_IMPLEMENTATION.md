# Background Connectivity & Local Notifications Implementation

## Overview

This implementation provides robust, Apple-compliant background connectivity for the Inviso offline/LAN peer-to-peer chat app without violating App Store policies. It focuses on local notifications and background task management without relying on audio hacks or APNs.

## Key Features

### ✅ Implemented
1. **Background Task Management** - Uses `BGAppRefreshTask` for periodic housekeeping
2. **Local Notifications** - Peer connection/disconnection alerts via `UNUserNotificationCenter`
3. **Graceful Background Transitions** - Suspend/resume signaling connections properly
4. **Apple-Compliant Architecture** - No audio background mode or policy violations
5. **Development Testing Tools** - Debug utilities for testing background behavior

### 🚧 Ready for Future Implementation
1. **Live Activity** - Framework ready for ActivityKit integration (iOS 16.1+)
2. **Local Network Discovery** - Bonjour/NWBrowser integration points prepared

## Architecture

### Background Task Flow
```
App Active → Background → BGAppRefresh → Resume → App Active
     ↓            ↓            ↓           ↓
  Normal     Suspend      Light       Resume
 Operation  Signaling   Housekeeping  Signaling
```

### Notification Flow
```
Peer Event → App State Check → Local Notification → User Tap → App Resume
     ↓             ↓                ↓                  ↓
P2P Connect    Background?      UNNotification    Join Room
P2P Disconnect    Yes/No         Alert/Badge      Clear Badge
```

## Implementation Details

### 1. Info.plist Configuration
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.apptrackit.inviso.refresh</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>background-fetch</string>
</array>
```

### 2. Core Components

#### BackgroundTaskManager
- Registers and schedules `BGAppRefreshTask` opportunities
- Handles lightweight background housekeeping
- Complies with system-scheduled execution windows

#### LocalNotificationManager  
- Manages local notifications without APNs dependency
- Handles foreground presentation and user interaction
- Provides room-specific notification clearing

#### ChatManager Extensions
- `prepareForBackground()` - Suspends signaling, persists state
- `resumeFromBackground()` - Reconnects signaling, clears notifications
- `backgroundRefreshPendingRooms()` - Lightweight state validation
- `onPeerJoined()`/`onPeerLeft()` - Trigger notifications

#### SignalingClient Extensions
- `suspend()` - Clean WebSocket closure without reconnection
- `resume()` - Attempts reconnection from background

### 3. App Lifecycle Integration

#### AppDelegate
```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    BackgroundTaskManager.shared.scheduleAppRefresh()
    ChatManager.shared.prepareForBackground()
}

func applicationWillEnterForeground(_ application: UIApplication) {
    ChatManager.shared.resumeFromBackground()
}
```

## Testing & Development

### Debug Features (Development Builds Only)
Located in Settings → Development section:

1. **Simulate Background Refresh** - Test background transition behavior
2. **Schedule Background Task** - Queue immediate BGAppRefresh (use with Xcode)
3. **Test Notifications** - Generate peer connection/disconnection alerts
4. **Clear Notifications** - Reset notification state

### Xcode Testing
1. **Background Fetch Simulation**: Debug → Simulate Background Fetch
2. **Background App Refresh**: Set breakpoints in `BackgroundRefreshOperation`
3. **Notification Testing**: Use device simulator for notification banners

### Device Testing
1. **Background Transitions**: Move app to background while in waiting room
2. **Notification Flow**: Have peer join while app backgrounded
3. **Tap Handling**: Tap notifications to verify room navigation

## Apple Compliance

### ✅ Follows Apple Guidelines
- Uses sanctioned `background-fetch` capability only
- Implements `BGTaskScheduler` for periodic opportunities
- Local notifications via `UNUserNotificationCenter`
- Graceful connection suspension/resumption
- No continuous background networking

### ❌ Avoids Policy Violations
- No audio background mode for non-audio purposes
- No VoIP/PushKit without actual VoIP functionality
- No persistent background connections
- No "zero-volume audio" tricks

## Edge Cases & Limitations

### System Limitations
- **Force Quit**: Background tasks don't run after force quit
- **Low Power Mode**: May limit background execution
- **Focus Modes**: Can affect notification delivery
- **Notification Permissions**: Require user authorization

### Network Considerations
- **Offline State**: Gracefully handles network unavailability
- **Connection Changes**: Uses `NWPathMonitor` for reachability
- **Signaling Interruption**: Resumes connections on foreground

### Background Execution
- **System Scheduled**: BGAppRefresh timing controlled by iOS
- **Short Duration**: Background tasks have limited execution time
- **Resource Constraints**: Lightweight operations only

## Future Enhancements

### Live Activity (Ready for Implementation)
```swift
// Framework prepared in BackgroundTaskManager
// Attributes defined for waiting/connected/disconnected states
// Local updates only (no push tokens required)
```

### Local Network Discovery
```swift
// Integration points prepared for:
// - Bonjour service discovery via NWBrowser
// - Local peer detection without server dependency
// - Mesh networking capabilities
```

### Enhanced Persistence
```swift
// Room state persistence for:
// - Peer discovery tokens
// - Connection metadata
// - Session recovery
```

## Integration Points

### Existing Code Integration
- **Minimal Changes**: Extends existing ChatManager and SignalingClient
- **Backward Compatible**: Doesn't break existing functionality
- **Optional Features**: Debug tools only in development builds

### External Dependencies
- **None Added**: Uses iOS system frameworks only
- **WebRTC Compatible**: Works with existing PeerConnectionManager
- **Server Agnostic**: Compatible with existing signaling protocol

## Monitoring & Debugging

### Logging
```swift
// Background operations logged with prefixes:
// "ChatManager: ..." - Chat state changes  
// "SignalingClient: ..." - Connection events
// "🧪 ..." - Development testing utilities
```

### Performance Impact
- **Minimal**: Background tasks are lightweight
- **Battery Friendly**: No continuous background operations
- **Memory Efficient**: Suspend unused connections

## Deployment Checklist

### App Store Submission
- [ ] Only `background-fetch` capability enabled
- [ ] No audio/VoIP capabilities unless justified
- [ ] BGTaskSchedulerPermittedIdentifiers in Info.plist
- [ ] Test background behavior on device
- [ ] Verify notification permissions handling

### User Experience
- [ ] Request notification permissions appropriately
- [ ] Clear explanations for background features
- [ ] Graceful degradation if permissions denied
- [ ] Intuitive notification tap behavior

This implementation provides a solid foundation for offline P2P chat background connectivity while maintaining full Apple App Store compliance.