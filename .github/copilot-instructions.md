# GitHub Copilot Code Review Instructions for KSCrash

When performing code reviews on this repository, follow these instructions to identify API breaking changes in the KSCrash crash reporting library.

## Focus Areas

Only review changes to public API surfaces. The public modules are: KSCrashRecording, KSCrashFilters, KSCrashSinks, KSCrashInstallations, KSCrashDiscSpaceMonitor, KSCrashBootTimeMonitor, and KSCrashDemangleFilter. Only examine files in `Sources/[ModuleName]/include/*.h` directories as these contain the public headers.

## Always Flag as Breaking Changes

Comment on any of these changes as they break existing user code:

- Any parameter addition, removal, or type change to existing Objective-C methods. Remember that Objective-C has no default parameters, so adding even a nullable parameter breaks all existing call sites.

- Any change to callback or function pointer signatures including parameter addition, removal, reordering, or return type changes.

- Any property type changes, including changing between primitive types, object types, or nullability changes in either direction (nonnull to nullable breaks Swift API by changing String to String?, nullable to nonnull breaks code that passes nil).

- Any struct or enum field reordering, removal, or type changes as these break binary compatibility.

- Any addition, modification, or removal of NS_SWIFT_NAME attributes on existing types or methods as these change the Swift API surface.

- Any changes to protocol methods between required and optional as this breaks conforming classes.

- Any superclass changes for existing classes as this alters inheritance behavior.

- Any private module types appearing in public headers as this creates unintended API dependencies.

## Safe Changes (Don't Flag)

These changes are not breaking and don't require comments:

- Adding `__attribute__((deprecated))` to existing APIs as deprecation warnings don't break compilation.

- Adding completely new methods, properties, or classes with entirely new names.

- Adding NS_SWIFT_NAME to brand new APIs that didn't have it before.

- Adding optional methods to existing protocols.

- Internal implementation changes in .m files or private headers not in include directories.

- Documentation updates or comments.

## Review Context

When reviewing changes, ask yourself: Would existing user code fail to compile after this change? If yes, it's breaking. The KSCrash library prioritizes API stability, so any breaking change needs strong justification and clear migration guidance.

Pay special attention to callback API changes as this library has a history of major callback signature evolution for async-safety and policy awareness.
