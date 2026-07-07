#import <Foundation/Foundation.h>

NSBundle* KSCrashRecordingTests_SWIFTPM_MODULE_BUNDLE() {
    NSURL *bundleURL = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"KSCrash_KSCrashRecordingTests.bundle"];

    NSBundle *preferredBundle = [NSBundle bundleWithURL:bundleURL];
    if (preferredBundle == nil) {
      return [NSBundle bundleWithPath:@"/private/tmp/claude-501/-Users-alex-Documents-Code-Github-KSCrash/970ce29a-b378-4e24-bd72-2d2a41382f5a/scratchpad/pr855/.build-tsan263/arm64-apple-macosx/debug/KSCrash_KSCrashRecordingTests.bundle"];
    }

    return preferredBundle;
}