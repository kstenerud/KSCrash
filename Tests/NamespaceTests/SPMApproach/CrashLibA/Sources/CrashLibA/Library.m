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
        NSLog(@"CrashLibA: %lu pending crash reports", (unsigned long)kscrash.reportStore.reportIDs.count);
    }
}

@end
