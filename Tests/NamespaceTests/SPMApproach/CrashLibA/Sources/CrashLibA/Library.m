#import "CrashLibA.h"
#import "KSCrashC.h"

@implementation CrashLibA

+ (void)start
{
    NSString *installPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CrashLibA"];
    KSCrashCConfiguration config = KSCrashCConfiguration_Default();
    KSCrashInstallErrorCode code = kscrash_install(installPath.fileSystemRepresentation, &config);
    KSCrashCConfiguration_Release(&config);
    if (code != KSCrashInstallErrorNone) {
        NSLog(@"CrashLibA failed to install KSCrash: %d", code);
    } else {
        NSLog(@"CrashLibA installed KSCrash (%s)", kscrash_namespaceIdentifier());
    }
}

@end
