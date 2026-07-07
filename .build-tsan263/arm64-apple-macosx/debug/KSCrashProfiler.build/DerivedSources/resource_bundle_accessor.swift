import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("KSCrash_KSCrashProfiler.bundle").path
        let buildPath = "/private/tmp/claude-501/-Users-alex-Documents-Code-Github-KSCrash/970ce29a-b378-4e24-bd72-2d2a41382f5a/scratchpad/pr855/.build-tsan263/arm64-apple-macosx/debug/KSCrash_KSCrashProfiler.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}