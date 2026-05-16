---
paths:
  - "Sources/KSCrashRecording/include/*.h"
  - "Sources/KSCrashFilters/include/*.h"
  - "Sources/KSCrashSinks/include/*.h"
  - "Sources/KSCrashDiscSpaceMonitor/include/*.h"
  - "Sources/KSCrashBootTimeMonitor/include/*.h"
  - "Sources/KSCrashDemangleFilter/include/*.h"
---

## Public Modules

The public API surface consists of: **KSCrashRecording**, **KSCrashFilters**, **KSCrashSinks**, **KSCrashDiscSpaceMonitor**, **KSCrashBootTimeMonitor**, and **KSCrashDemangleFilter**. Only files in `Sources/[ModuleName]/include/*.h` are public headers.

## API Stability

KSCrash prioritizes API stability. A change is **breaking** only if it breaks code that compiled against the **most recent tagged release**, not against unreleased work on master.

**This is the only baseline that matters.** Apply it when authoring changes, when reviewing PRs, and when evaluating any review comment that claims "this is source-breaking."

- Find the current release with `git describe --tags --abbrev=0` (or check the GitHub releases page).
- Compare the affected public header at that tag (`git show <tag>:Sources/.../Header.h`) against the PR's version.
- If the API in the PR is identical to, or strictly additive over, the API at the release tag, **the change is not source-breaking**, regardless of what unreleased work on master has done in between.
- A symbol or type that does not exist at the release tag is not part of the released surface, so changing or removing it on master cannot be source-breaking.
- A reviewer comment, automated tool, or memory note that flags a change as source-breaking must be verified against the release tag before being acted on. If the verification disagrees with the comment, the comment is wrong.

The following changes to public headers need strong justification plus migration guidance **when they would break code compiled against the most recent release**:

- **Method parameter changes**: Any addition, removal, type change, or reordering. ObjC has no default parameters, so even adding a nullable parameter breaks all call sites.
- **Callback/function pointer signature changes**: Parameter or return type changes.
- **Property changes**: Type changes, nullability changes in either direction, attribute changes (e.g., atomic → nonatomic is an ABI break).
- **NS_SWIFT_NAME changes**: Adding, modifying, or removing on existing types/methods changes the Swift API.
- **Struct/enum layout changes**: Field reordering, removal, type changes, or enum value changes break binary compatibility.
- **Report field constant removal**: Constants like `KSCrashExcType_*` and `KSCrashField_*` are used by consumers to match against on-disk reports. Removing them breaks both compilation and the ability to read existing reports. Keep old constants as deprecated aliases when renaming.
- **Protocol requirement changes**: Adding required methods or making optional methods required.
- **C function signature changes**: Parameter or return type changes.
- **Superclass changes**: Changing inheritance hierarchy.
- **Private module leaks**: Private/internal types must not appear in public headers.

### Safe Changes

- Adding deprecation attributes
- Adding completely new methods, properties, or classes with new names
- Adding `NS_SWIFT_NAME` to brand new APIs only
- Adding `@optional` methods to protocols
