//
//  AppDelegate.m
//  Simple-Example
//

#import "AppDelegate.h"

#import <KSCrash/KSCrash.h> // TODO: Remove this
#import <KSCrash/KSCrashInstallation+Alert.h>
#import <KSCrash/KSCrashInstallationStandard.h>
#import <KSCrash/KSCrashInstallationQuincyHockey.h>
#import <KSCrash/KSCrashInstallationEmail.h>
#import <KSCrash/KSCrashInstallationVictory.h>


/* Very basic crash reporting example.
 *
 * This example creates an installation (standard, email, quincy, or hockey)
 * installs, and then sends any crash reports right away.
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
    // Create an installation (choose one)
//    KSCrashInstallation* installation = [self makeStandardInstallation];
    KSCrashInstallation* installation = [self makeEmailInstallation];
//    KSCrashInstallation* installation = [self makeHockeyInstallation];
//    KSCrashInstallation* installation = [self makeQuincyInstallation];
//    KSCrashInstallation *installation = [self makeVictoryInstallation];
    
    
    // Install the crash handler. This should be done as early as possible.
    // This will record any crashes that occur, but it doesn't automatically send them.
    [installation install];
    [KSCrash sharedInstance].deleteBehaviorAfterSendAll = KSCDeleteNever; // TODO: Remove this


    // Send all outstanding reports. You can do this any time; it doesn't need
    // to happen right as the app launches. Advanced-Example shows how to defer
    // displaying the main view controller until crash reporting completes.
    [installation sendAllReportsWithCompletion:^(NSArray* reports, BOOL completed, NSError* error)
     {
         if(completed)
         {
             NSLog(@"Sent %d reports", (int)[reports count]);
         }
         else
         {
             NSLog(@"Failed to send reports: %@", error);
         }
     }];
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
    [email setReportStyle:KSCrashEmailReportStyleApple useDefaultFilenameFormat:YES];

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
    
    return quincy;
}

- (KSCrashInstallation*) makeStandardInstallation
{
    NSURL* url = [NSURL URLWithString:@"http://put.your.url.here"];
    
    KSCrashInstallationStandard* standard = [KSCrashInstallationStandard sharedInstance];
    standard.url = url;
    
    return standard;
}

- (KSCrashInstallation*) makeVictoryInstallation
{
//    NSURL* url = [NSURL URLWithString:@"https://victory-demo.appspot.com/api/v1/crash/0571f5f6-652d-413f-8043-0e9531e1b689"];
    NSURL* url = [NSURL URLWithString:@"https://put.your.url.here/api/v1/crash/<application key>"];
    
    KSCrashInstallationVictory* victory = [KSCrashInstallationVictory sharedInstance];
    victory.url = url;
    victory.userName = [[UIDevice currentDevice] name];
    victory.userEmail = @"nobody@nowhere.com";
    
    return victory;
}

@end
