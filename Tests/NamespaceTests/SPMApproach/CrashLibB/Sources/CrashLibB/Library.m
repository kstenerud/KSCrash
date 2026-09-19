#import "CrashLibB.h"
#import "KSCrashC.h"

@implementation CrashLibB

+ (void)start
{
    NSString *installPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CrashLibB"];
    KSCrashCConfiguration config = KSCrashCConfiguration_Default();
    KSCrashInstallErrorCode code = kscrash_install(installPath.fileSystemRepresentation, &config);
    KSCrashCConfiguration_Release(&config);
    if (code != KSCrashInstallErrorNone) {
        NSLog(@"CrashLibB failed to install KSCrash: %d", code);
    } else {
        NSLog(@"CrashLibB installed KSCrash (%s)", kscrash_namespaceIdentifier());
    }
}

@end
