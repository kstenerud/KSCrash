KSCrash Namespacing Test
========================

This is a demonstration of how to namespace your own instance of KSCrash. KSCrash namespacing works such that you can reference it directly as a git submodule (or vendor it in if you like) rather than having to modify and maintain your own fork of the KSCrash source files.

After running [`build.sh`](build.sh), you can open the [CrashyApp](CrashyApp) project and run it to see it in action. The two libraries (CrashLibA and CrashLibB) will each record the crash, and will each report to the console.


Our Example
-----------

This example builds two separate libraries ([CrashLibA](CrashLibA) and [CrashLibB](CrashLibB)) that each use KSCrash under the hood. These libraries are then BOTH used in [CrashyApp](CrashyApp).

Normally, two libraries each statically linking in a copy of KSCrash would result in a slew of duplicate symbol errors during the linking phase when both used in a single app, but this can be mitigated using the `KSCRASH_NAMESPACE` define.

### Setting the Namespace

To set the namespace define, set `GCC_PREPROCESSOR_DEFINITIONS=\"KSCRASH_NAMESPACE\=mynamespace\"` when building.

**Note**: This _should_ also be doable via the build settings in Xcode, but that doesn't work for some reason (The compiled C/OBJC code will be out of sync with the compiled Swift code, resulting in linker errors).

### Swift or Objective-C Target

Another wrinkle: Swift library building has been [broken for years now](https://github.com/swiftlang/swift/issues/64669). If your library is implemented as a Swift target, you'll need to add `OTHER_SWIFT_FLAGS="-no-verify-emitted-module-interface"` to your build, and **so will all of your users** when they use your library, compiled or not!

If you build an Objective-C library, it'll just work, and your users won't need to set `-no-verify-emitted-module-interface`.

### Getting around Swift Package Manager's Magic

Now you'd think that simply building the KSCrash package with the `KSCRASH_NAMESPACE` define would be enough, but sadly SPM has too much magic for that to work. Swift uses the package name to namespace the target names (which are stored as symbols in the binary), and so if multiple libraries use KSCrash directly as a dependency, you'll get naming collisions.

The workaround is to create your own package using a copied and slightly modified `Package.swift`, and then symlink to the sources:

* Create a directory to hold your namespaced package
* Copy [`Package.swift`](../../../Package.swift), and set the package name to something else
* Symlink the [`Sources`](../../../Sources) and [`Tests`](../../../Tests) directories

This produces a new package directory with the following contents:

* `Package.swift` (slightly modified copy of the KSCrash `Package.swift`)
* `Sources` (symlink to the KSCrash `Sources` directory)
* `Tests` (symlink to the KSCrash `Tests` directory)

Which is exactly what [`build.sh`](build.sh) does.

### Distributing the Namespaced Library

The easiest way to distribute your namespaced library this way is via an `.xcframework`:

* Build frameworks for each platform you want to support (iOS, macOS, tvOS, watchOS, etc)
* Combine them all together using `xcodebuild -create-xcframework`

You can see an example of this in [`build.sh`](build.sh).
