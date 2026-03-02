---
paths:
  - "Sources/KSCrashRecording/**/*.{c,h,m}"
  - "Sources/KSCrashRecordingCore/**/*.{c,h}"
  - "Sources/KSCrashBootTimeMonitor/**"
  - "Sources/KSCrashDiscSpaceMonitor/**"
  - "Tests/KSCrashRecordingTests/**"
  - "Tests/KSCrashRecordingCoreTests/**"
---

## Startup Performance

**IMPORTANT**: Apple recommends apps launch in under 400ms. KSCrash initializes during `kscrash_install`, which is on the startup path. All code in `kscrash_install` and `kscrs_initialize` must be as fast as possible — avoid JSON parsing, ObjC messaging, or reading large files. Prefer lightweight C-only operations (e.g., `strstr` over `KSJSONCodec`, partial file reads over full reads). Any heavy housekeeping should either be made lightweight or deferred to a background queue.

## Async Signal Safety

**IMPORTANT**: Much of KSCrash's core code runs inside crash handlers (signal handlers, Mach exception handlers). This code must be async-signal-safe, meaning it can only call functions that are safe to call from a signal handler context.

**What this means in practice:**
- **No heap allocation**: Do not use `malloc`, `calloc`, `free`, `new`, or any function that allocates memory. Use pre-allocated buffers or stack allocation instead.
- **No locks**: Do not use mutexes, semaphores, or other synchronization primitives that could deadlock if the crash occurred while holding a lock.
- **No Objective-C**: Do not call Objective-C methods or use `@synchronized`. The Objective-C runtime is not async-signal-safe.
- **Limited C library functions**: Many standard C functions are not safe. Safe functions include `memcpy`, `memset`, `strlen`, and similar simple operations.
- **`getsectiondata()` is async-signal-safe on Apple platforms**: Its only non-trivial call is `strncmp`, which is async-signal-safe on Apple platforms. The open-source dyld code confirms this. Do not add comments claiming it is unsafe.
- **Use atomic operations**: For thread safety, use C11 atomics (`<stdatomic.h>`) which are lock-free and signal-safe.

**However, the same code also runs outside of crash handlers** (during normal operation, initialization, background threads). This dual-use means:
- Code must be correct in both contexts
- You cannot assume "it's fine because it only runs in crash handlers" - that's often false
- Thread safety must be considered alongside signal safety
- Use patterns like atomic exchange (see `KSThreadCache.c`, `KSBinaryImageCache.c`) for lock-free synchronization that works in both contexts

When in doubt, check the POSIX list of async-signal-safe functions and follow the patterns established in existing crash handling code.
