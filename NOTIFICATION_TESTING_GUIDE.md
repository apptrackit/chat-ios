# Notification Testing Guide

## Issues Found & Fixed

### 1. Threading Issues ✅ FIXED
**Problem**: "Publishing changes from background threads is not allowed"
**Solution**: Wrapped all UI updates in `DispatchQueue.main.async`

### 2. Notification Logic ✅ IMPROVED  
**Problem**: Notifications not firing when expected
**Solution**: 
- Added detailed logging with app state checking
- Improved app state detection logic
- Added force notification testing capability

### 3. Background Connection ✅ ENHANCED
**Problem**: App immediately suspends signaling when backgrounded while waiting
**Solution**: Added 30-second grace period for peer connections in waiting rooms

## Testing Instructions

### Step 1: Test Notification Permissions
1. Open Settings → Development
2. Tap "Force Test Notification" 
3. **Expected**: You should see a test notification appear immediately
4. **If no notification**: Check Settings → Notifications → Inviso and ensure notifications are enabled

### Step 2: Test Background Peer Connection
1. Start the app and join/create a room
2. Put the app in background (home button)
3. Have another device join the same room
4. **Expected**: You should receive a "Peer Connected" notification
5. **Check logs**: Look for lines like:
   ```
   🔔 Checking notification - App state: 2 (0=active, 1=inactive, 2=background)
   🔔 Should notify: true
   ✅ Local notification scheduled for peer connection
   ```

### Step 3: Test Waiting Room Background Behavior
1. Create a room and stay in waiting state
2. Put app in background
3. **Expected**: App maintains connection for 30 seconds then suspends
4. **Check logs**: Look for:
   ```
   ChatManager: In waiting room, allowing brief background connection time
   ChatManager: Grace period expired, suspending signaling (after 30s)
   ```

## Debug Information

### App State Values
- `0` = Active (foreground)
- `1` = Inactive (transitioning)  
- `2` = Background

### Log Prefixes
- `🔔` = Notification system
- `🔗` = Connection events
- `🧪` = Debug testing
- `✅` = Success
- `❌` = Error

### Key Log Messages

#### Successful Notification Flow:
```
🔗 PCM ICE state changed: false -> true, App state: 2
ChatManager: Peer joined room: [room-id]
🔔 Checking notification - App state: 2
🔔 Should notify: true  
✅ Local notification scheduled for peer connection
```

#### Skipped Notification (App Active):
```
🔔 Checking notification - App state: 0
🔔 Should notify: false
🔔 App is active, skipping notification
```

## Troubleshooting

### No Notifications Appearing
1. **Check Permissions**: Settings → Notifications → Inviso
2. **Test Force Notification**: Use "Force Test Notification" button
3. **Check Focus Modes**: Disable Do Not Disturb / Focus modes
4. **Restart Notification Service**: Restart device if needed

### Notifications Not Firing During Background
1. **Check App State Logs**: Ensure app state is `2` (background)
2. **Verify Peer Connection**: Look for ICE state change logs
3. **Check 30s Grace Period**: Notifications only work after grace period expires

### Threading Errors Persist
1. **Check Console**: Look for "Publishing changes from background threads"
2. **Verify Fix**: All UI updates should be wrapped in `DispatchQueue.main.async`

## Testing Checklist

- [ ] Force test notification works
- [ ] Notification permissions enabled
- [ ] Background peer connection triggers notification
- [ ] App state logging shows correct values
- [ ] 30-second grace period works for waiting rooms
- [ ] No threading errors in console
- [ ] Notification tap opens app to correct room

## Next Steps

1. **Test the fixes** using the guide above
2. **Monitor console logs** for debugging information
3. **Report results** - what works and what doesn't
4. **Background behavior** should now properly handle waiting rooms
5. **Live Activity** can be implemented next once notifications work reliably

The implementation now has much better debugging and should work reliably for background notifications.