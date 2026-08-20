# flutter_continued_task Lifecycle Test Matrix

This document defines testing scenarios to verify that the `flutter_continued_task` plugin functions properly across various mobile OS lifecycle events (Doze mode, battery saver, background transitions, timeouts, and user cancellation).

---

## 1. Test Scenario Matrix

| ID | Scenario | Purpose | Platform | Expected Result |
| :--- | :--- | :--- | :--- | :--- |
| **TC-01** | Foreground start → Home/Screen lock | Maintain process and network connectivity during background transition | Android, iOS | • Progress notification / Lock screen UI persists<br>• Dart execution completes without interruption<br>• Notification automatically dismissed upon completion |
| **TC-02** | Force Android Doze mode | FGS execution and network persistence under Doze mode | Android | • Task continues after `adb shell dumpsys deviceidle force-idle`<br>• Transfers continue without `UnknownHostException` |
| **TC-03** | Android 6-hour timeout guard | Prevent crashes when 6h `dataSync` limit is reached | Android | • Immediate clean shutdown on `onTimeout`<br>• No `RemoteServiceException` crash<br>• Emits `timeout` event to Dart layer |
| **TC-04** | Attempt `start()` from background | Handle background start restrictions safely | Android (API 31+), iOS | • Returns `false` cleanly without crashing<br>• Caller remains safe in pending state |
| **TC-05** | Tap "Cancel" on notification | Handle active user cancellation | Android, iOS | • Emits `stopRequested` to Dart<br>• Work queue stops cleanly and service terminates |
| **TC-06** | Rapid `update()` calls (100 calls/sec) | Verify IPC serialization and coalescing performance | Common | • Smooth UI without frame drops<br>• Final completion progress guaranteed without loss |
| **TC-07** | Swipe-kill app and relaunch | Reconnect and clean up detached service | Android | • `syncState` recovers assertion and cleans up pending stop requests upon next launch |

---

## 2. Manual Device / Emulator Verification Guide

### 2.1 Android Simulation Commands
```bash
# 1. Inspect Foreground Service state
adb shell dumpsys activity services | grep -A 10 "dev.flutter.continued_task"

# 2. Force Doze Mode
adb shell dumpsys deviceidle force-idle

# 3. Exit Doze Mode
adb shell dumpsys deviceidle unforce

# 4. Monitor plugin logs
adb logcat -c && adb logcat | grep -iE "ContinuedTask|FlutterContinuedTask"
```

### 2.2 iOS `BGContinuedProcessingTask` Debugging
1. Launch app in Xcode and start task.
2. Move app to background and lock screen.
3. In Xcode LLDB, simulate task expiration:
```lldb
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"co.zelly.flutter.upload"]
```
4. Verify console logs.
