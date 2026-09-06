#import "CrashLibB.h"
#import "KSCrash.h"
#import "KSCrashInstallConfiguration.h"

@implementation CrashLibB

+ (void)start
{
    NSError *error = nil;
    KSCrashInstallConfiguration *config = [KSCrashInstallConfiguration new];
    KSCrash *kscrash = KSCrash.sharedInstance;
    if (![kscrash installWithConfiguration:config error:&error]) {
        NSLog(@"CrashLibB failed to install KSCrash: %@", error);
    } else {
        NSLog(@"CrashLibB: %ld pending crash reports", (long)kscrash.reportStore.reportCount);
    }
}

@end
