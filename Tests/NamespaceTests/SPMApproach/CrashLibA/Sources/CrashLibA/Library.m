#import "CrashLibA.h"
#import "KSCrash.h"
#import "KSCrashInstallConfiguration.h"

@implementation CrashLibA

+ (void)start
{
    NSError *error = nil;
    KSCrashInstallConfiguration *config = [KSCrashInstallConfiguration new];
    KSCrash *kscrash = KSCrash.sharedInstance;
    if (![kscrash installWithConfiguration:config error:&error]) {
        NSLog(@"CrashLibA failed to install KSCrash: %@", error);
    } else {
        NSLog(@"CrashLibA: %ld pending crash reports", (long)kscrash.reportStore.reportCount);
    }
}

@end
