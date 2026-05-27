#import "CrashLibA.h"
#import "KSCrash.h"
#import "KSCrashInstallConfiguration.h"
#import "KSCrashReportSinkConsole.h"
#import "KSCrashSendConfiguration.h"

@implementation CrashLibA

+ (void)start
{
    NSError *error = nil;
    KSCrashInstallConfiguration *config = [KSCrashInstallConfiguration new];
    KSCrash *kscrash = KSCrash.sharedInstance;
    if (![kscrash installWithConfiguration:config error:&error]) {
        NSLog(@"CrashLibA failed to install KSCrash: %@", error);
    } else {
        NSLog(@"CrashLibA: Sending any new crash reports...");
        KSCrashSendConfiguration *sendConfig = [KSCrashSendConfiguration new];
        sendConfig.reportFilters = [KSCrashReportSinkConsole new].defaultCrashReportFilterSet;
        sendConfig.reportCleanupPolicy = KSCrashReportCleanupPolicyAlways;
        [kscrash sendAllReportsWithConfiguration:sendConfig
                                      completion:^(NSArray<id<KSCrashReport>> *_Nullable filteredReports,
                                                   NSError *_Nullable error) {
                                          NSLog(@"CrashLibA sent %lu reports with error %@",
                                                (unsigned long)filteredReports.count, error);
                                      }];
    }
}

@end
