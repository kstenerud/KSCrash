---
applyTo: "Sources/KSCrashRecording/KSCrashAppStateTracker*,Sources/KSCrashRecording/include/KSCrashAppStateTracker.h,Sources/KSCrashRecording/KSCrashHostKind.*,Tests/KSCrashRecordingTests/KSCrashAppMemory_Tests.m,Tests/KSCrashRecordingTests/KSCrashHostKind_Tests.m,Sources/KSCrashUIMonitorCore/**"
---

# App state tracker decisions

Settled decisions for `KSCrashAppStateTracker` and the host kind it shares with
the Lifecycle monitor. Do not flag code that follows them. When a decision
changes or a new one is made, it is recorded here.

- **No UI framework, no platform `#if`.** The tracker imports neither UIKit
  nor WatchKit and has no compile-time platform branches. It observes the
  `UIApplication*` and `NSExtensionHost*` notifications by name (each string
  equals its symbol; a test compares them where the symbols exist), finds
  `UIApplication` with `NSClassFromString`, and messages it through a declared
  protocol, with `UIApplicationState`'s values mirrored. The names are declared
  once, in `KSCrashNotificationNames.h`, for every part of the core that
  observes them. This is part of the core dropping UIKit, so an app extension
  that links KSCrash links no UIKit. Observing by name is not observing
  everywhere: only a process that gets a notification registers for it, decided
  at runtime by host kind (the application's only in an app, the host's only in
  an extension).
- **One runtime decision in `start`.** An app extension (by host kind)
  observes its extension host. Otherwise a process with a `UIApplication`
  class observes the application and takes its state. A process without one
  (macOS) is Active for its whole run.
- **A watch app takes the application path.** A watch app built as an `.app`
  has a `UIApplication` (an `SPApplication`) that posts the `UIApplication*`
  notifications by name with `UIApplicationState`'s values, and it gets no
  `NSExtensionHost*` notifications at all (probed on a watchOS simulator), so
  the old watchOS branch observing the host never moved one off Startup. Its
  launch also runs before the main run loop starts, like a scene-based iOS
  app's. A watch extension (an `.appex`) follows its host like any extension.
- **No `+load` in the core, and no constructor either.** The shared tracker
  starts on first access, which is normally install. Starting it before `main`
  cost 0.6 to 2.5 ms in every process that links KSCrash, installed or not
  (measured in fresh processes, almost all of it the first use of
  `NSNotificationCenter`), and a dylib constructor runs at the same point for
  the same cost.
- **The UI module starts the tracker at load.** Linking the UI module is how
  an app chooses to have the tracker running from process start: its `+load`
  starts the shared tracker, so the tracker sees every launch notification.
  The core has no `+load`, so an app that doesn't link the module gets a
  tracker that starts at install. Starting before `main` costs 0.6 to 2.5 ms,
  paid only by apps that link the module. SwiftPM is the supported way to link
  it, and it keeps the `+load` even when nothing references the module (probed
  with static and automatic products, Debug and Release). Repackaging KSCrash
  as a static library is not recommended: the linker drops the `+load` unless
  the app passes `-ObjC`.
- **Start takes the running application's state.** Because the tracker can
  start after the app has launched, `start` reads the application once, after
  observing, and applies what it read only while the state is still the one
  `start` saw, so a notification that arrived in between wins. The read is
  made only on the main thread (`applicationState` belongs to it) from a
  running main run loop: inline when `start` runs there, and otherwise a block
  performed on the main run loop, which waits for the loop to run. A
  scene-based app, and a watch app, runs its whole launch,
  `didFinishLaunching` and `UIApplicationDidFinishLaunchingNotification`
  included, before the main run loop starts, reading `background` on its way
  to the foreground (probed on iOS 27 and watchOS); waiting for the loop puts
  the read after the launch notifications, so the guard drops it. The mapping:
  - no `UIApplication`: the starting state stays;
  - started on the main thread before `UIApplicationMain`, by the UI module's
    `+load`: no read at all. There is no application object yet and no
    notification has been posted to miss. The one `UIApplicationMain` makes
    reads `background` on the main run loop's first turn, before UIKit starts
    the launch, so an app without scenes would otherwise be labeled Background
    through `didFinishLaunching` of a foreground launch (probed on iOS 26.5);
  - `active`: Active;
  - `background`: Background;
  - `inactive`: read again once the current main run loop callout has
    returned, then Deactivating if nothing moved the state in between. UIKit
    does not say whether an inactive app is being interrupted or coming back
    from the background; Deactivating is the likelier one after launch, both
    are user perceptible, and the next notification corrects the label.
- **A launch into the background settles as Background.** It gets
  `UIApplicationDidFinishLaunchingNotification` and no foreground
  notification, so it would stay Launching, which is user perceptible, for its
  whole run (probed on iOS 27: hours of background location updates labeled
  Launching). Reading `applicationState` at the launch notification cannot
  tell, since a scene-based app reads `background` there on a foreground
  launch too. So the launch notification also reads the state on the main
  queue's next turn and moves Launching to Background only if it still reads
  `background`. On iOS 27 a foreground launch's scene has entered the
  foreground by that turn, so the state has moved on and the read is dropped;
  a background launch still reads `background`. The heuristic is wrong only if
  a foreground launch reached that turn before its scene entered the
  foreground, and then the label is Background until the scene's notification
  arrives. The main queue, not a run loop perform, is what was probed.
- **Without the UI module, start reads the state it missed.** A tracker
  started at install takes its state from `applicationState`, which can't tell
  a launch in progress from a running app. During a launch it reads Background
  or Inactive, so the tracker reports Background or Deactivating where the app
  is really Launching or Foregrounding, until the next notification corrects
  it. This is why we recommend linking the UI module when using KSCrash within
  an application. Extensions work correctly without linking the UI module.
- **An inactive read waits for the current callout.** An app without scenes
  (built with an SDK older than iOS 27, which refuses to launch one) launches
  inside one callout of the running main run loop and reads `inactive` all
  through `didFinishLaunching`, the same as an interruption. UIKit posts
  `UIApplicationDidFinishLaunchingNotification` in that same callout, and a
  block performed on the main run loop runs only once the callout has
  returned, so in a launch the notification moves the state first and the
  waiting read is dropped (probed: such an app
  installing in `didFinishLaunching` goes Startup, Launching, Active). The
  same wait means an app found inactive on its way to active simply becomes
  Active when `UIApplicationDidBecomeActiveNotification` arrives. While it
  waits, readers see the starting state. The wait, and the hop from another
  thread, are `CFRunLoopPerformBlock` on the main run loop in
  `kCFRunLoopCommonModes` (followed by `CFRunLoopWakeUp`) rather than the main
  queue, because what the read waits for is a run loop callout, and the common
  modes are the ones the main run loop runs in throughout the app's life,
  tracking included.
- **Only the run loop's current mode is used.** The connected-scene count also
  marks a scene-based launch, but it cannot tell a launch from a running app:
  a launch into the background connects a scene too, one that never enters
  the foreground (probed on iOS 27); the run loop can. The rest of the
  public run loop state says nothing about launch: the main run loop never
  reads as waiting from a thread that is running, the next timer fire date
  depends on whatever timers are scheduled, and the mode list only changes
  through UIKit internals (a mode named `kCFRunLoopCommonModes` appears after
  launch), which is not a contract.
- **The environment cannot tell a launch in progress from a running app.**
  `ActivePrewarm` is the only launch variable Apple documents, and it stays
  set for the life of a process that began as a prewarm, so it only picks
  StartupPrewarm over Startup at init.
- **App extensions follow their extension host.** An extension has no
  application of its own, so it observes the `NSExtensionHost*` notifications, which
  describe the process presenting it. Nothing announces an extension's launch,
  and one that nothing presents gets no host notifications at all, so an
  extension starts Active rather than staying at a Startup that is not true.
- **Host kind comes from the executable path, once.** `kshostkind_current()`
  decides app, extension, xctest or other under `dispatch_once` from
  `_NSGetExecutablePath`, by the same rule as `NSBundle`'s main bundle
  (`<bundle>/<name>`, or `<bundle>/Contents/MacOS/<name>`). It never asks
  `NSBundle`, whose first touch costs milliseconds and can land on the install
  path. The tracker and the Lifecycle monitor share it; the cache stays even
  where a caller asks once today.
