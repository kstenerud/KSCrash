#import "CrashLibB.h"
#import "KSCrashConfiguration.h"
#import "KSCrashInstallationConsole.h"

@implementation CrashLibB

+ (void)start
{
    NSError *error = nil;
    KSCrashConfiguration *config = [KSCrashConfiguration new];
    KSCrashInstallation *installation = KSCrashInstallationConsole.sharedInstance;
    if (![installation installWithConfiguration:config error:&error]) {
        NSLog(@"CrashLibB failed to install KSCrash: %@", error);
    } else {
        NSLog(@"CrashLibB: Sending any new crash reports...");
        [installation sendAllReportsWithCompletion:^(NSArray<id<KSCrashReport>> *_Nullable filteredReports,
                                                     NSError *_Nullable error) {
            NSLog(@"CrashLibB sent %lu reports with error %@", (unsigned long)filteredReports.count, error);
        }];
    }
}

@end
