//
//  AppDelegate.m
//  Advanced-Example
//

#import "AppDelegate.h"

#import <KSCrash/KSCrashInstallation+Alert.h>
#import <KSCrash/KSCrashInstallationStandard.h>
#import <KSCrash/KSCrashInstallationQuincyHockey.h>
#import <KSCrash/KSCrashInstallationEmail.h>
#import <KSCrash/KSCrashInstallationVictory.h>
#import <KSCrash/KSCrashInstallationConsole.h>
#import <KSCrash/KSCrash.h>


/* More advanced crash reporting example.
 *
 * This example creates an installation (standard, email, quincy, or hockey),
 * but defers showing the main VC until crash reporting has completed.
 *
 * This mitigates issues where the app crashes during initialization (in which
 * case you'd never see a crash report).
 *
 * This example also enables some more advanced features of KSCrash. See
 * configureAdvancedSettings.
 */


@implementation AppDelegate

- (BOOL) application:(__unused UIApplication *) application
didFinishLaunchingWithOptions:(__unused NSDictionary *) launchOptions
{
    [self installCrashHandler];
    
    return YES;
}

// ======================================================================
#pragma mark - Basic Crash Handling -
// ======================================================================

- (void) installCrashHandler
{
    // This can be useful when debugging on the simulator.
    // Normally, there's no way to see console messages in the simulator,
    // except when running in the debugger, which disables the crash handler.
    // This feature redirects KSCrash console messages to a log file instead.
//    [[KSCrash sharedInstance] redirectConsoleLogsToDefaultFile];
    
    
    // Create an installation (choose one)

    self.crashInstallation = [self makeConsoleInstallation];
    //    self.crashInstallation = [self makeStandardInstallation];
    //    self.crashInstallation = [self makeEmailInstallation];
    //    self.crashInstallation = [self makeHockeyInstallation];
    //    self.crashInstallation = [self makeQuincyInstallation];
    //    self.crashInstallation = [self makeVictoryInstallation];
    
    
    // Install the crash handler. This should be done as early as possible.
    // This will record any crashes that occur, but it doesn't automatically send them.
    [self.crashInstallation install];
    
    // You may also optionally configure some more advanced settings if you like.
    [self configureAdvancedSettings];
    
    // Crash reports will be sent by LoaderVC.
}


- (KSCrashInstallation*) makeConsoleInstallation
{
    return [KSCrashInstallationConsole new];
}

- (KSCrashInstallation*) makeEmailInstallation
{
    NSString* emailAddress = @"your@email.here";
    
    KSCrashInstallationEmail* email = [KSCrashInstallationEmail sharedInstance];
    email.recipients = @[emailAddress];
    email.subject = @"Crash Report";
    email.message = @"This is a crash report";
    email.filenameFmt = @"crash-report-%d.txt.gz";
    
    [email addConditionalAlertWithTitle:@"Crash Detected"
                                message:@"The app crashed last time it was launched. Send a crash report?"
                              yesAnswer:@"Sure!"
                               noAnswer:@"No thanks"];
    
    // Uncomment to send Apple style reports instead of JSON.
//    [email setReportStyle:KSCrashEmailReportStyleApple useDefaultFilenameFormat:YES];

    return email;
}

- (KSCrashInstallation*) makeHockeyInstallation
{
    NSString* hockeyAppIdentifier = @"PUT_YOUR_HOCKEY_APP_ID_HERE";
    
    KSCrashInstallationHockey* hockey = [KSCrashInstallationHockey sharedInstance];
    hockey.appIdentifier = hockeyAppIdentifier;
    hockey.userID = @"ABC123";
    hockey.contactEmail = @"nobody@nowhere.com";
    hockey.crashDescription = @"Something broke!";

    // Don't wait until reachable because the main VC won't show until the process completes.
    hockey.waitUntilReachable = NO;
    
    return hockey;
}

- (KSCrashInstallation*) makeQuincyInstallation
{
//    NSURL* quincyURL = [NSURL URLWithString:@"http://localhost:8888/quincy/crash_v200.php"];
    NSURL* quincyURL = [NSURL URLWithString:@"http://put.your.quincy.url.here"];
    
    KSCrashInstallationQuincy* quincy = [KSCrashInstallationQuincy sharedInstance];
    quincy.url = quincyURL;
    quincy.userID = @"ABC123";
    quincy.contactEmail = @"nobody@nowhere.com";
    quincy.crashDescription = @"Something broke!";
    
    // Don't wait until reachable because the main VC won't show until the process completes.
    quincy.waitUntilReachable = NO;
    
    return quincy;
}

- (KSCrashInstallation*) makeStandardInstallation
{
    NSURL* url = [NSURL URLWithString:@"http://put.your.url.here"];
    
    KSCrashInstallationStandard* standard = [KSCrashInstallationStandard sharedInstance];
    standard.url = url;
    
    return standard;
}

- (KSCrashInstallationVictory*) makeVictoryInstallation
{
//    NSURL* url = [NSURL URLWithString:@"https://victory-demo.appspot.com/api/v1/crash/0571f5f6-652d-413f-8043-0e9531e1b689"];
    NSURL* url = [NSURL URLWithString:@"https://put.your.url.here/api/v1/crash/<application key>"];
    
    KSCrashInstallationVictory* victory = [KSCrashInstallationVictory sharedInstance];
    victory.url = url;
    victory.userName = [[UIDevice currentDevice] name];
    victory.userEmail = @"nobody@nowhere.com";
    
    return victory;
}


// ======================================================================
#pragma mark - Advanced Crash Handling (optional) -
// ======================================================================

static void advanced_crash_callback(const KSCrashReportWriter* writer)
{
    // You can add extra user data at crash time if you want.
    writer->addBooleanElement(writer, "some_bool_value", NO);
    NSLog(@"***advanced_crash_callback");
}

- (void) configureAdvancedSettings
{
    KSCrash* handler = [KSCrash sharedInstance];
    
    // Settings in KSCrash.h
    handler.deadlockWatchdogInterval = 8;
    handler.userInfo = @{@"someKey": @"someValue"};
    handler.onCrash = advanced_crash_callback;
    handler.monitoring = KSCrashMonitorTypeProductionSafe;

    // Do not introspect class SensitiveInfo (see MainVC)
    // When added to the "do not introspect" list, the Objective-C introspector
    // will only record the class name, not its contents.
    handler.doNotIntrospectClasses = @[@"SensitiveInfo"];
}

@end
