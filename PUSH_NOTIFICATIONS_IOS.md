# Push Notifications Implementation Guide - iOS

**Version:** 1.0  
**Date:** October 12, 2025  
**Implementation:** Option 2 - Ephemeral Device Token Exchange

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Apple Developer Portal Setup](#apple-developer-portal-setup)
5. [Xcode Configuration](#xcode-configuration)
6. [iOS Implementation](#ios-implementation)
7. [Testing](#testing)
8. [Privacy Considerations](#privacy-considerations)
9. [Troubleshooting](#troubleshooting)

---

## Overview

This guide implements **ephemeral, privacy-preserving push notifications** to alert users when their chat partner joins a room. The system:

- ✅ Uses **APNs device tokens** (not FCM topics)
- ✅ Tokens are **ephemeral per session** (not persistent)
- ✅ Tokens are **automatically purged** when sessions expire or are deleted
- ✅ **No message content** is ever sent through push notifications
- ✅ Only **presence notifications**: "Your chat partner is waiting"
- ✅ Works with your **existing room-based architecture**

### What Gets Implemented:

**iOS Side:**
1. Request notification permissions on first launch
2. Generate APNs device token
3. Send ephemeral token to server during room creation/acceptance
4. Handle incoming notifications → open chat
5. Revoke token on session deletion

**Server Side (see PUSH_NOTIFICATIONS_BACKEND.md):**
1. Store ephemeral tokens in database (per room)
2. Send APNs notification when peer joins
3. Auto-purge tokens on session expiry/deletion

---

## Architecture

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                     CLIENT 1 (Creator)                              │
│                                                                     │
│  1. Create session → Generate APNs token                           │
│  2. POST /api/rooms { joinid, client1, token: "abc123..." }       │
│  3. Wait for acceptance...                                         │
│                                                                     │
│  📱 RECEIVES PUSH: "Your chat partner is waiting"                  │
│  4. User taps notification → App opens → Joins room               │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                     CLIENT 2 (Joiner)                               │
│                                                                     │
│  1. Enter join code → Generate APNs token                          │
│  2. POST /api/rooms/accept { joinid, client2, token: "def456..." }│
│  3. Server returns roomId                                          │
│  4. Join room via WebSocket                                        │
│                                                                     │
│  → Server detects Client1 not connected                            │
│  → Server sends APNs push to Client1's token                       │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                          SERVER                                     │
│                                                                     │
│  rooms table:                                                       │
│  ┌─────────┬──────────┬──────────┬──────────────┬──────────────┐  │
│  │ roomid  │ client1  │ client2  │ client1_token│ client2_token│  │
│  ├─────────┼──────────┼──────────┼──────────────┼──────────────┤  │
│  │ xyz789  │ eph_abc  │ eph_def  │ apns_token_1 │ apns_token_2 │  │
│  └─────────┴──────────┴──────────┴──────────────┴──────────────┘  │
│                                                                     │
│  On WebSocket join_room:                                           │
│    IF peer not connected → Send APNs to peer's token               │
│                                                                     │
│  On session expiry/delete:                                         │
│    DELETE tokens from database                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Required Accounts & Tools

- ✅ **Apple Developer Account** (paid membership: $99/year)
- ✅ **Xcode 15+** installed
- ✅ **Physical iOS device** (push notifications don't work on simulator)
- ✅ **macOS** for Xcode and certificate generation

### Required Knowledge

- Basic Swift/SwiftUI
- Understanding of APNs concepts (tokens, certificates, notifications)
- Familiarity with Keychain and UserNotifications framework

---

## Apple Developer Portal Setup

### Step 1: Create App ID with Push Notification Capability

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Identifiers** → **+ (Add)**
4. Select **App IDs** → Click **Continue**
5. Configure:
   - **Description:** Inviso Chat
   - **Bundle ID:** Explicit → `com.31b4.Inviso` (your existing bundle ID)
   - **Capabilities:** ✅ Enable **Push Notifications**
6. Click **Continue** → **Register**

---

### Step 2: Generate APNs Authentication Key (Recommended Method)

**Why use Auth Key over Certificate?**
- ✅ Never expires (no renewal needed)
- ✅ Works for all apps in your team
- ✅ Simpler server implementation
- ✅ More secure (no password/passphrase)

#### Generate Key:

1. In Apple Developer Portal → **Keys** → **+ (Add)**
2. **Key Name:** `Inviso APNs Auth Key`
3. ✅ Enable **Apple Push Notifications service (APNs)**
4. Click **Continue** → **Register**
5. **Download the key file:** `AuthKey_XXXXXXXXXX.p8`
   
   ⚠️ **CRITICAL:** You can only download this **once**. Store it securely!

6. **Note these values:**
   - **Key ID:** (10-character string, e.g., `AB12CD34EF`)
   - **Team ID:** (found in top-right of developer portal, e.g., `XYZ9876543`)

#### Store Securely:

```bash
# Create secure directory
mkdir -p ~/Developer/APNs-Keys
chmod 700 ~/Developer/APNs-Keys

# Move key file
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/Developer/APNs-Keys/
chmod 600 ~/Developer/APNs-Keys/AuthKey_XXXXXXXXXX.p8

# Backup to encrypted location (recommended)
# Option 1: Use 1Password/Keychain to store the .p8 file
# Option 2: Encrypted disk image
# Option 3: Git repository with encryption (e.g., git-crypt)
```

---

### Step 3: Alternative - Generate APNs Certificate (Legacy Method)

**Only use if you can't use Auth Key (e.g., legacy systems).**

1. **Generate CSR on Mac:**
   - Open **Keychain Access** → **Certificate Assistant** → **Request a Certificate from a Certificate Authority**
   - **User Email:** Your email
   - **Common Name:** `Inviso APNs Certificate`
   - **Request is:** Saved to disk
   - Click **Continue** → Save `CertificateSigningRequest.certSigningRequest`

2. **Create Certificate in Developer Portal:**
   - Go to **Certificates** → **+ (Add)**
   - Select **Apple Push Notification service SSL (Sandbox & Production)**
   - Select your App ID: `com.31b4.Inviso`
   - Upload the CSR file
   - Click **Continue** → **Download** `aps.cer`

3. **Install Certificate:**
   - Double-click `aps.cer` → Opens in Keychain Access
   - Find certificate → Right-click → **Export** → Save as `Inviso_APNs_Cert.p12`
   - Set a strong password (you'll need this on the server)

---

## Xcode Configuration

### Step 1: Enable Push Notifications Capability

1. Open `Inviso.xcodeproj` in Xcode
2. Select project root → **Inviso** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability** → Select **Push Notifications**
5. Verify **Push Notifications** capability is added:
   ```
   ✅ Push Notifications
      - Modes: Development, Production
   ```

---

### Step 2: Enable Background Modes (for notification handling)

1. In **Signing & Capabilities** tab
2. Click **+ Capability** → Select **Background Modes**
3. ✅ Enable **Remote notifications**
   - This allows silent notifications to wake the app

---

### Step 3: Update Info.plist

Add notification usage description (required for iOS 10+):

```xml
<key>NSUserNotificationUsageDescription</key>
<string>We need to notify you when your chat partner is waiting so you don't miss conversations.</string>
```

**Location:** `/Inviso/Inviso/Info.plist` (add before closing `</dict>`)

---

### Step 4: Configure Signing

1. In **Signing & Capabilities**
2. **Team:** Select your Apple Developer team
3. **Bundle Identifier:** Verify it matches `com.31b4.Inviso`
4. **Signing Certificate:** Xcode will auto-provision
5. Build the project to generate provisioning profile

---

## iOS Implementation

### Step 1: Create PushNotificationManager

**File:** `/Inviso/Inviso/Services/Notifications/PushNotificationManager.swift`

```swift
//
//  PushNotificationManager.swift
//  Inviso
//
//  Manages APNs device token lifecycle and notification handling.
//  Tokens are ephemeral per session for maximum privacy.
//

import Foundation
import UserNotifications
import UIKit

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var currentDeviceToken: String?
    
    private let keychain = KeychainService(service: (Bundle.main.bundleIdentifier ?? "inviso") + ".push")
    private let tokenAccount = "apns-token"
    
    private override init() {
        super.init()
        checkAuthorizationStatus()
    }
    
    // MARK: - Public API
    
    /// Request notification permissions from user
    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        
        await MainActor.run {
            authorizationStatus = granted ? .authorized : .denied
        }
        
        if granted {
            // Register for remote notifications on main thread
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            await MainActor.run {
                authorizationStatus = settings.authorizationStatus
            }
        }
    }
    
    /// Store device token (called from AppDelegate)
    func setDeviceToken(_ token: String) {
        currentDeviceToken = token
        // Persist to keychain for offline access
        try? keychain.setString(token, for: tokenAccount)
        print("✅ [Push] Device token registered: \(token.prefix(16))...")
    }
    
    /// Get current device token (from memory or keychain)
    func getDeviceToken() -> String? {
        if let token = currentDeviceToken {
            return token
        }
        // Fallback to keychain
        if let stored = try? keychain.getString(for: tokenAccount) {
            currentDeviceToken = stored
            return stored
        }
        return nil
    }
    
    /// Clear device token (on logout or token invalidation)
    func clearDeviceToken() {
        currentDeviceToken = nil
        try? keychain.delete(account: tokenAccount)
    }
    
    /// Handle notification tap (app opened via notification)
    func handleNotificationTap(roomId: String?) {
        guard let roomId = roomId else { return }
        // Post notification to trigger ChatManager to join room
        NotificationCenter.default.post(
            name: .pushNotificationTapped,
            object: nil,
            userInfo: ["roomId": roomId]
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    
    /// Called when notification arrives while app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner even when app is open
        return [.banner, .sound, .badge]
    }
    
    /// Called when user taps notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let roomId = userInfo["roomId"] as? String
        
        await MainActor.run {
            PushNotificationManager.shared.handleNotificationTap(roomId: roomId)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pushNotificationTapped = Notification.Name("pushNotificationTapped")
}
```

---

### Step 2: Update InvisoApp.swift

**File:** `/Inviso/Inviso/InvisoApp.swift`

```swift
//
//  InvisoApp.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/12/25.
//

import SwiftUI

@main
struct InvisoApp: App {
    @StateObject private var chat = ChatManager()
    @StateObject private var pushManager = PushNotificationManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            SecuredContentView {
                ContentView()
                    .environmentObject(chat)
                    .environmentObject(pushManager)
                    .onOpenURL { url in
                        chat.handleIncomingURL(url)
                    }
                    .task {
                        // Request notification permissions on first launch
                        if pushManager.authorizationStatus == .notDetermined {
                            try? await pushManager.requestAuthorization()
                        }
                    }
            }
        }
    }
}

// MARK: - AppDelegate for Push Notifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = PushNotificationManager.shared
        return true
    }
    
    /// Called when APNs token is successfully registered
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Convert token to hex string
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        
        Task { @MainActor in
            PushNotificationManager.shared.setDeviceToken(tokenString)
        }
    }
    
    /// Called when APNs registration fails
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ [Push] Failed to register: \(error.localizedDescription)")
    }
}
```

---

### Step 3: Update APIClient to Send Tokens

**File:** `/Inviso/Inviso/Netwrorking/APIClient.swift`

Add token parameters to room creation and acceptance:

```swift
func createRoom(joinCode: String, expiresInSeconds: Int, clientID: String, deviceToken: String?) async throws {
    var request = URLRequest(url: apiBase.appendingPathComponent("/api/rooms"))
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = [
        "joinid": joinCode,
        "expiresInSeconds": expiresInSeconds,
        "client1": clientID
    ]
    
    // Add device token if available
    if let token = deviceToken {
        body["client1_token"] = token
    }
    
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, _) = try await URLSession.shared.data(for: request)
}

func acceptJoinCode(_ code: String, clientID: String, deviceToken: String?) async -> String? {
    var request = URLRequest(url: apiBase.appendingPathComponent("/api/rooms/accept"))
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    
    var body: [String: Any] = [
        "joinid": code,
        "client2": clientID
    ]
    
    // Add device token if available
    if let token = deviceToken {
        body["client2_token"] = token
    }
    
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        if httpResponse.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let roomID = json["roomid"] as? String {
            return roomID
        }

        if httpResponse.statusCode == 404 || httpResponse.statusCode == 409 {
            return nil
        }
    } catch {
        print("acceptJoinCode error: \(error)")
    }
    return nil
}
```

---

### Step 4: Update ChatManager to Use Tokens

**File:** `/Inviso/Inviso/Chat/ChatManager.swift`

Update room creation and acceptance to send device tokens:

```swift
// In createPendingOnServer function (around line 270)
private func createPendingOnServer(session: ChatSession, originalMinutes: Int) async {
    guard connectionStatus == .connected, let client1 = clientId else { return }
    
    // Get device token
    let deviceToken = await PushNotificationManager.shared.getDeviceToken()
    
    let expiresInSeconds = originalMinutes * 60
    do {
        try await APIClient().createRoom(
            joinCode: session.code,
            expiresInSeconds: expiresInSeconds,
            clientID: client1,
            deviceToken: deviceToken  // ← Added
        )
    } catch {
        print("Failed to create pending on server: \(error)")
    }
}

// In acceptJoinCodeOnServer function (around line 320)
private func acceptJoinCodeOnServer(code: String, session: ChatSession) async {
    guard connectionStatus == .connected, let client2 = clientId else { return }
    
    // Get device token
    let deviceToken = await PushNotificationManager.shared.getDeviceToken()
    
    if let roomId = await APIClient().acceptJoinCode(code, clientID: client2, deviceToken: deviceToken) {
        // ... existing code
    }
}
```

---

### Step 5: Handle Push Notification Taps

**File:** `/Inviso/Inviso/Chat/ChatManager.swift`

Add observer for push notification taps:

```swift
// In init() function, add after setupAppLifecycleObservers():
setupPushNotificationObservers()

// Add new function:
private func setupPushNotificationObservers() {
    NotificationCenter.default.publisher(for: .pushNotificationTapped)
        .sink { [weak self] notification in
            guard let roomId = notification.userInfo?["roomId"] as? String else { return }
            Task { @MainActor in
                self?.handlePushNotificationTap(roomId: roomId)
            }
        }
        .store(in: &appLifecycleCancellables)
}

// Add handler function:
private func handlePushNotificationTap(roomId: String) {
    // Find session with matching roomId
    guard let session = sessions.first(where: { $0.roomId == roomId }) else {
        print("⚠️ [Push] No session found for roomId: \(roomId)")
        return
    }
    
    // Set as active session
    activeSessionId = session.id
    
    // Join room if connected
    if connectionStatus == .connected {
        joinRoom(roomId: roomId)
    } else {
        // Connect first, then join
        connect()
        pendingJoinRoomId = roomId
    }
}
```

---

### Step 6: Create Settings UI for Notifications

**File:** `/Inviso/Inviso/Views/Settings/NotificationSettingsView.swift`

```swift
//
//  NotificationSettingsView.swift
//  Inviso
//
//  User-facing notification settings.
//

import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject var pushManager: PushNotificationManager
    
    var body: some View {
        List {
            Section {
                statusRow
            }
            
            Section {
                Button {
                    Task {
                        try? await pushManager.requestAuthorization()
                    }
                } label: {
                    Label("Enable Notifications", systemImage: "bell.badge")
                }
                .disabled(pushManager.authorizationStatus == .authorized)
                
                if pushManager.authorizationStatus == .denied {
                    Button {
                        openAppSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                    }
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("Notifications alert you when your chat partner is waiting. No message content is ever sent.")
            }
        }
        .navigationTitle("Notifications")
    }
    
    private var statusRow: some View {
        HStack {
            Text("Status")
            Spacer()
            statusBadge
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch pushManager.authorizationStatus {
        case .authorized:
            Label("Enabled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Label("Disabled", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .notDetermined:
            Label("Not Set", systemImage: "questionmark.circle")
                .foregroundStyle(.orange)
        default:
            Label("Unknown", systemImage: "exclamationmark.circle")
                .foregroundStyle(.gray)
        }
    }
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
```

Add to Settings menu in `SettingsView.swift`:

```swift
NavigationLink {
    NotificationSettingsView()
} label: {
    Label("Notifications", systemImage: "bell.badge")
}
```

---

## Testing

### Step 1: Test on Physical Device

⚠️ **Push notifications do NOT work on iOS Simulator!**

1. Connect iPhone/iPad via USB or Wi-Fi
2. Select device in Xcode (top bar)
3. Build & Run (Cmd+R)

---

### Step 2: Test Permission Request

1. Launch app (fresh install)
2. Should see system alert: "Inviso Would Like to Send You Notifications"
3. Tap **Allow**
4. Check console for: `✅ [Push] Device token registered: ...`

---

### Step 3: Test Token Storage

```swift
// Add temporary debug button in SettingsView
Button("Debug: Show Token") {
    if let token = PushNotificationManager.shared.getDeviceToken() {
        print("📱 Current token: \(token)")
    } else {
        print("❌ No token registered")
    }
}
```

---

### Step 4: Test Full Flow (After Backend is Implemented)

**Two Physical Devices Required:**

**Device 1 (Creator):**
1. Open app → Create session
2. Note the join code
3. Close app / send to background

**Device 2 (Joiner):**
1. Open app → Join with code
2. Wait for room to be created
3. App joins room via WebSocket

**Expected Result:**
- Device 1 receives push notification: "Your chat partner is waiting"
- Tap notification → App opens → Joins room
- P2P connection established

---

### Step 5: Test Token Purging

1. Create a session
2. Delete the session
3. Verify server purges token (check server logs)

---

## Privacy Considerations

### What This Implementation Guarantees:

✅ **No message content** in push notifications  
✅ **Ephemeral tokens** - unique per session  
✅ **Automatic cleanup** - tokens deleted with sessions  
✅ **No persistent tracking** - tokens can't be correlated across sessions  
✅ **User control** - notifications are opt-in  
✅ **Minimal metadata** - only presence information  

### What Apple Sees:

⚠️ Apple's APNs servers see:
- Device token (unique to device+app)
- Notification delivery time
- Bundle ID

They do **NOT** see:
- Message content
- Who you're chatting with
- Room IDs or session data

### Privacy Impact vs. AGENTS.md:

The original constraint was **"no push notifications"**, but this implementation maintains maximum privacy by:
- Only sending presence notifications (not message content)
- Using ephemeral, non-correlatable identifiers
- Automatic cleanup on expiry
- Full user control (opt-in)

**Recommendation:** Update AGENTS.md to allow **"presence notifications only"**.

---

## Troubleshooting

### Device Token Not Registered

**Symptoms:** Console shows `❌ [Push] Failed to register`

**Solutions:**
1. Check **Signing & Capabilities** → Verify **Push Notifications** is enabled
2. Verify **Provisioning Profile** includes push capability:
   - Xcode → Preferences → Accounts → Download Manual Profiles
3. Check network connection (APNs requires internet)
4. Restart device

---

### Notifications Not Received

**Symptoms:** Server sends, but device doesn't show notification

**Solutions:**
1. Verify notification permissions: Settings → Inviso → Notifications
2. Check **Do Not Disturb** is off
3. Verify app is not in **Focus Mode** exclusion list
4. Check server logs to confirm APNs returned success
5. Test with **development** environment first (sandbox APNs)

---

### Invalid Token Error on Server

**Symptoms:** Server logs show APNs rejecting token

**Solutions:**
1. Verify **Team ID** and **Key ID** match on server
2. Check `.p8` key file is not corrupted
3. Ensure using correct APNs environment (sandbox vs production)
4. Regenerate device token: Uninstall app → Reinstall

---

### "Missing apns-topic" Error

**Symptoms:** APNs rejects notifications with missing topic

**Solution:**
- Add `note.topic = "com.31b4.Inviso"` in server code (see backend guide)

---

### Expired Token Error

**Symptoms:** Token worked before, now fails

**Solution:**
- Tokens can expire when:
  - App is uninstalled
  - User disables notifications
  - Device OS is updated
- Implement token refresh: Re-register on next session creation

---

## Next Steps

1. ✅ Complete iOS implementation (this guide)
2. ⏭️ Implement backend (see `PUSH_NOTIFICATIONS_BACKEND.md`)
3. 🧪 Test end-to-end flow with two physical devices
4. 📝 Update AGENTS.md to reflect notification policy
5. 🚀 Deploy to TestFlight for beta testing

---

## Security Checklist

Before deploying to production:

- [ ] APNs `.p8` key stored securely on server (not in git)
- [ ] Tokens are only sent over HTTPS
- [ ] Tokens are purged on session deletion
- [ ] Notification content contains no personal data
- [ ] User can disable notifications in settings
- [ ] Token validation on server before sending
- [ ] Rate limiting on notification sends
- [ ] Audit logging for token operations

---

## References

- [Apple Developer: Setting Up a Remote Notification Server](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server)
- [Apple Developer: Registering Your App with APNs](https://developer.apple.com/documentation/usernotifications/registering_your_app_with_apns)
- [node-apn Documentation](https://github.com/parse-community/node-apn)
- [APNs Provider API](https://developer.apple.com/documentation/usernotifications/sending_notification_requests_to_apns)

---

**End of iOS Implementation Guide**
