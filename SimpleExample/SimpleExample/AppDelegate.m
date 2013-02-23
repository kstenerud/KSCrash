//
//  AppDelegate.m
//  SimpleExample
//

#import "AppDelegate.h"
#import <KSCrash/KSCrashInstallationQuincyHockey.h>
#import <KSCrash/KSCrash.h>

@implementation AppDelegate

- (BOOL)application:(__unused UIApplication *)application didFinishLaunchingWithOptions:(__unused NSDictionary *)launchOptions
{
    KSCrashInstallation* installation = [self makeHockeyInstallation];
//    KSCrashInstallation* installation = [self makeQuincyInstallation];

//    [[KSCrash sharedInstance] redirectConsoleLogsToDefaultFile];

    // Install the crash handler. This should be done as early as possible.
    // This will record any crashes that occur, but it doesn't automatically send them.
    [installation install];

    
    // The next part can be done anywhere. It doesn't need to be done in application:didFinishLaunchingWithOptions:
    
    // Send all outstanding reports.
    [installation sendAllReportsWithCompletion:^(NSArray* reports, BOOL completed, NSError* error)
     {
         if(completed)
         {
             NSLog(@"Sent %d reports", [reports count]);
         }
         else
         {
             NSLog(@"Failed to send reports: %@", error);
         }
     }];
    
    return YES;
}

- (KSCrashInstallation*) makeHockeyInstallation
{
//    NSString* hockeyAppIdentifier = @"PUT_YOUR_HOCKEY_APP_ID_HERE";
    NSString* hockeyAppIdentifier = @"d388d0d3e38b29935e0034fea4b7b8ce";
    
    KSCrashInstallationHockey* hockey = [KSCrashInstallationHockey sharedInstance];
    hockey.appIdentifier = hockeyAppIdentifier;
    hockey.userID = @"ABC123";
    hockey.contactEmail = @"nobody@nowhere.com";
    hockey.description = @"Something broke!";
    
    return hockey;
}

- (KSCrashInstallation*) makeQuincyInstallation
{
    NSURL* quincyURL = [NSURL URLWithString:@"http://put.your.quincy.url.here"];
    
    KSCrashInstallationQuincy* quincy = [KSCrashInstallationQuincy sharedInstance];
    quincy.url = quincyURL;
    
    return quincy;
}



static void advanced_crash_callback(const KSCrashReportWriter* writer)
{
    writer->addBooleanElement(writer, "advanced_mode", NO);
}

- (void) configureAdvancedSettings
{
    KSCrash* handler = [KSCrash sharedInstance];
    
    // Settings in KSCrash.h
    handler.zombieCacheSize = 16384;
    handler.deadlockWatchdogInterval = 8;
    handler.userInfo = @{@"someKey": @"someValue"};
    handler.onCrash = advanced_crash_callback;
    handler.printTraceToStdout = YES;
}


@end
