//
//  CrashLibA.m
//  CrashLibA
//
//  Created by Karl Stenerud on 03.09.25.
//

#import "CrashLibA.h"
#import <KSCrashInstallationConsole.h>

@implementation CrashLibA

+ (void)start
{
    NSError *error = nil;
    KSCrashConfiguration *config = [KSCrashConfiguration new];
    KSCrashInstallation *installation = KSCrashInstallationConsole.sharedInstance;
    if (![installation installWithConfiguration:config error:&error]) {
        NSLog(@"CrashLibA failed to install KSCrash: %@", error);
    } else {
        NSLog(@"CrashLibA: Sending any new crash reports...");
        [installation sendAllReportsWithCompletion:^(NSArray<id<KSCrashReport>> *_Nullable filteredReports,
                                                     NSError *_Nullable error) {
            NSLog(@"CrashLibA sent %lu reports with error %@", (unsigned long)filteredReports.count, error);
        }];
    }
}

@end
