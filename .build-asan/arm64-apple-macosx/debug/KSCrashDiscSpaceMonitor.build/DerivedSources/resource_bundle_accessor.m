#import <Foundation/Foundation.h>

NSBundle* KSCrashDiscSpaceMonitor_SWIFTPM_MODULE_BUNDLE() {
    NSURL *bundleURL = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"KSCrash_KSCrashDiscSpaceMonitor.bundle"];

    NSBundle *preferredBundle = [NSBundle bundleWithURL:bundleURL];
    if (preferredBundle == nil) {
      return [NSBundle bundleWithPath:@"/private/tmp/claude-501/-Users-alex-Documents-Code-Github-KSCrash/970ce29a-b378-4e24-bd72-2d2a41382f5a/scratchpad/pr855/.build-asan/arm64-apple-macosx/debug/KSCrash_KSCrashDiscSpaceMonitor.bundle"];
    }

    return preferredBundle;
}