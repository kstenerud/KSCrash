//
//  AppDelegate.m
//
//  Created by Karl Stenerud on 2012-03-04.
//

#import "AppDelegate.h"
#import "ARCSafe_MemMgmt.h"
#import "AppDelegate+UI.h"

#import <KSCrash/KSCrash.h>
#import <KSCrash/KSCrashAdvanced.h>


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
        printf(NULL);
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

    // Uncomment this to write all log entries to Library/Caches/KSCrashReports/Crash-Tester/Crash-Tester-CrashLog.txt
//    [handler redirectConsoleLogsToDefaultFile];

    handler.zombieCacheSize = 16384;
    handler.deadlockWatchdogInterval = 5.0f;
    handler.printTraceToStdout = YES;
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
    self.crasher = as_autorelease([[Crasher alloc] init]);

    self.window = as_autorelease([[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]]);
    self.window.rootViewController = [self createRootViewController];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void) dealloc
{
    as_release(_viewController);
    as_release(_window);
    as_release(_crasher);
    as_superdealloc();
}

@end
