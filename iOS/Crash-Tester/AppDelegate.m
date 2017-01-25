//
//  AppDelegate.m
//
//  Created by Karl Stenerud on 2012-03-04.
//

#import "AppDelegate.h"
#import "AppDelegate+UI.h"
#import "Configuration.h"

#import <KSCrash/KSCrash.h>


/* Example app that demonstrates the many ways in which an application
 * can crash.
 *
 * Note: This app uses many low level features to demonstrate the
 * different ways you can send reports to a remote server. Normally
 * you'd just use an installation like in Simple-Example or Advanced-Example.
 */


static BOOL g_crashInHandler = NO;

static void onCrash(const KSCrashReportWriter* writer)
{
    if(g_crashInHandler)
    {
        char* buff = NULL;
        buff[0] = 'a';
    }
    writer->addStringElement(writer, "test", "test");
    writer->addStringElement(writer, "intl2", "テスト２");
}


@implementation AppDelegate

@synthesize window = _window;
@synthesize viewController = _viewController;
@synthesize crasher = _crasher;

- (BOOL) crashInHandler
{
    return g_crashInHandler;
}

- (void) setCrashInHandler:(BOOL)crashInHandler
{
    g_crashInHandler = crashInHandler;
}

- (void) installCrashHandler
{
    KSCrash* handler = [KSCrash sharedInstance];

    handler.deadlockWatchdogInterval = 5.0f;
    handler.catchZombies = YES;
//    handler.addConsoleLogToReport = YES;
//    handler.printPreviousLog = YES;
    handler.onCrash = onCrash;
    handler.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                        @"\"quote\"", @"quoted value",
                        @"blah", @"\"quoted\" key",
                        @"bslash\\", @"bslash value",
                        @"x", @"bslash\\key",
                        @"intl", @"テスト",
                        nil];

    // Don't delete after send for this demo.
    handler.deleteBehaviorAfterSendAll = KSCDeleteNever;

    [handler install];
}

- (BOOL)application:(__unused UIApplication*) application didFinishLaunchingWithOptions:(__unused NSDictionary*) launchOptions
{
    [self installCrashHandler];
    self.crasher = [[Crasher alloc] init];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [self createRootViewController];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
