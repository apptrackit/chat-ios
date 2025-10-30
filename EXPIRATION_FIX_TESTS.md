# Test Scenarios for Expiration Fix

## Scenario 1: Normal Expiration ✅
**Setup:**
- Create pending session with 2-minute expiry
- Don't accept, just wait

**Expected:**
- Countdown shows 2:00, 1:59, ... 0:01, 0:00
- When countdown hits 0:00, UI shows "Expired" in red
- After next polling cycle (within 6 seconds), session marked as expired

**Verification:**
- Session appears in "Closed & Expired" section
- Status is `.expired`

---

## Scenario 2: Acceptance Before Local Expiry ✅
**Setup:**
- Create pending session with 3-minute expiry
- Other user accepts at T=2:30 (before expiry)
- Keep app open

**Expected:**
- Countdown shows normal countdown
- When accepted, session immediately moves to "Active" section
- Status changes to `.accepted`

**Verification:**
- No false expiration
- Can join chat immediately

---

## Scenario 3: Acceptance Near Expiry (App Open) ✅
**Setup:**
- Create pending session with 2-minute expiry
- Other user accepts at T=1:55 (5 seconds before expiry)
- Keep app open

**Expected:**
- Countdown shows 0:05, 0:04, 0:03, 0:02, 0:01
- Session changes to `.accepted` when server confirms
- Even if countdown shows 0:00 briefly, status is `.accepted` not `.expired`

**Verification:**
- Session in "Active" section
- Can join chat

---

## Scenario 4: Acceptance Near Expiry (App Closed) ⭐ **THE BUG SCENARIO**
**Setup:**
- Create pending session with 3-minute expiry
- Exit app at T=0:30
- Other user accepts at T=2:50 (10 seconds before expiry)
- Reopen app at T=3:10 (10 seconds after local expiry)

**Before Fix:**
- ❌ Session marked as expired
- ❌ Appeared in "Closed & Expired" section
- ❌ Could not join chat

**After Fix:**
- ✅ App polls server, gets 404
- ✅ Checks local time: expired (T=3:10 > T=3:00)
- ✅ But server should return accepted with roomId on next poll
- ✅ Session changes to `.accepted` 
- ✅ Appears in "Active" section
- ✅ Can join chat

**Note:** There might be a brief moment (1-2 polling cycles) where status appears pending, but this is acceptable and resolves quickly.

---

## Scenario 5: True Expiration (App Closed)
**Setup:**
- Create pending session with 2-minute expiry
- Exit app at T=0:30
- Nobody accepts
- Reopen app at T=3:00

**Expected:**
- App polls server, gets 404 (pending expired and deleted)
- Checks local time: expired (T=3:00 > T=2:00)
- Session marked as `.expired`

**Verification:**
- Session in "Closed & Expired" section
- Cannot join chat (correct behavior)

---

## Scenario 6: No Expiry Time Set
**Setup:**
- Create pending session with 0 minutes (no expiry)
- Exit app
- Other user never accepts
- Reopen app later

**Expected:**
- Session remains `.pending` indefinitely
- Server says 404 but local time check fails (no expiresAt)
- Continues polling
- Never auto-marked as expired

**Verification:**
- Session stays in "Pending" section
- No countdown timer shown
- Waits forever for acceptance

---

## Scenario 7: Network Error Resilience
**Setup:**
- Create pending session with 2-minute expiry
- Disconnect from network before expiry
- Wait for local timer to hit 0:00
- Reconnect after local expiry

**Expected:**
- While offline: polling paused, status stays `.pending`
- When reconnect: polling resumes
- Server check returns 404 (expired)
- Local check confirms expired
- Session marked as `.expired`

**Verification:**
- No premature expiration while offline
- Correct status when back online

---

## Edge Cases

### Late Server Response
If server is slow to respond and we get multiple 404s before the accepted status:
- ✅ Each 404 checks local time
- ✅ If not locally expired, keeps polling
- ✅ Eventually resolves to `.accepted`

### Clock Skew
If device clock is wrong:
- ⚠️ Could cause issues (always a problem with time-based systems)
- Server expiry time calculated on server (correct)
- Local expiry calculated when creating (uses device time)
- Small skew (< 1 minute) should be acceptable
- Large skew could cause incorrect behavior

### Rapid App Switching
Rapidly opening/closing app around expiry time:
- ✅ Polling runs on app foreground
- ✅ Each check is independent
- ✅ Eventually converges to correct state

---

## Testing Commands

### Quick Test (2 minutes)
```swift
// In SessionsView or CreateRoomModal
chat.createSession(name: "Test", minutes: 2, code: "123456")
```

### Extended Test (5 minutes)
```swift
chat.createSession(name: "Long Test", minutes: 5, code: "654321")
```

### No Expiry Test
```swift
chat.createSession(name: "Forever", minutes: 0, code: "999999")
```

---

## Monitoring

Look for these log messages:
```
[Session] Marking pending 123456 as expired (confirmed by both local timer and server 404)
[Session] Pending 123456 got 404 but local timer hasn't expired - continuing to poll (likely accepted)
```

These indicate the fix is working correctly.
