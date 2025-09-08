Namespacing with Swift Package Manager
======================================

This approach allows you to distribute your library via Swift Package Manager, but requires some work to keep things in sync and properly namspaced since all SPM targets seem to share the same global namespace (they should be namespaced to the package, but they aren't for some reason).

To get around this, we make a new `Package.swift` with our own names, and then copy in the source files from the official KSCrash repo (this could be done by including KSCrash as submodule, or perhaps vendoring in a copy). The end result is that you have a new `Package.swift` containing your own target and sources, as well as a namespaced "KSCrash" target containing the unmodified KSCrash source files that your library needs - sparing you the pain of forking and maintaining KSCrash source code.

I've included a [script](merge_spm_project.py) to make this task easier.

This Example
------------

In this example, we have two libraries ([`CrashLibA`](CrashLibA) and [`CrashLibB`](CrashLibB)) to represent two external libraries from different vendors (A and B) - each of which uses their own instance of KSCrash under the hood. These instances could even be entirely different versions of KSCrash.

[`CrashyApp`](CrashyApp) is the customer's buggy app that uses both libraries because they like some features of Vendor A, and other features of Vendor B.

Suppose you are Vendor A. The files you're maintaining manually are:

* [`Package.swift`](CrashLibA/Package.swift)
* [`CrashLibA.h`](CrashLibA/Sources/CrashLibA/include/CrashLibA.h)
* [`Library.m`](CrashLibA/Sources/CrashLibA/Library.m)

The rest of the files (everything in `CrashLibA/Sources/KSCrashLibA` are generated using [merge_spm_project.py](merge_spm_project.py) (which is called via [`sync.sh`](sync.sh) in this example for convenience), and consist entirely of generated code or copies of original, unmodified KSCrash source files (which should NOT be modified).


### How It Works

[`sync.sh`](sync.sh) holds a list of targets to merge from the KSCrash package, as well as a list of headers to export from it (in this case, `CrashLibA` and `CrashLibB` are only using `KSCrashInstallationConsole`, so they don't need many headers exposed).

First, it merges from the KSCrash project using [`merge_spm_project.py`](merge_spm_project.py). This script creates `CrashLibA/Sources/KSCrashLibA` and then copies all of the KSCrash sources from the targets we're interested in (listed in [`sync.sh`](sync.sh)).

**Note**: This example uses the `-s` flag of `merge_spm_project.py` to create symlinks for convenience when debugging KSCrash itself - you'll probably want to use the default (copy) since Xcode plays nicer with actual files when looking things up.

The script also merges every `PrivacyInfo.xcprivacy` file it finds into one merged file: `CrashLibA/Sources/KSCrashLibA/Resources/PrivacyInfo.xcprivacy`.

Once this is done, the script generates `CrashLibA/Sources/KSCrashLibA/include/module.modulemap` so that SPM will know how to expose the KSCrash API.

[`Package.swift`](CrashLibA/Package.swift) is where we declare the new namespaced KSCrash target (`KSCrashLibA`), and set our own target (`CrashLibA`) as dependent upon it. We also set `KSCRASH_NAMESPACE` in BOTH `KSCrashLibA` and `CrashLibA`.

With this setup, we have package `CrashLibA` with targets `CrashLibA` and `KSCrashLibA` inside of it, setting every public KSCrash symbol to have a namespace suffix of `CrashLibA`.

`CrashLibB` is set up the same way.

Now everything is fully namespaced and can be built from source via SPM.


Example App
-----------

[`CrashyApp`](CrashyApp) starts both crash libraries ([CrashLibA](CrashLibA) and [CrashLibB](CrashLibB)). Each library will record crashes and report them to the console on relaunch.

### Building and Running

- [Install Tuist](https://docs.tuist.dev/en/guides/quick-start/install-tuist)
- `./sync.sh`
- `cd CrashyApp`
- `tuist install`
- `tuist generate`
- Build using Xcode or xcodebuild
