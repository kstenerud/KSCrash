//
//  AppDelegate.m
//
//  Created by Karl Stenerud on 2012-03-04.
//

#import "AppDelegate.h"
#import "ARCSafe_MemMgmt.h"
#import "AppDelegate+UI.h"

#import <KSCrash/KSCrash.h>

// Used to expose "logToFile"
#import <KSCrash/KSCrashAdvanced.h>


@interface AppDelegate ()

- (void) installCrashHandler;

@end

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
    // Uncomment this to write all log entries to Library/Caches/KSCrashReports/CrashTester/CrashTester-CrashLog.txt
//    [KSCrash logToFile];

    [KSCrash installWithCrashReportSink:nil
                               userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                         @"\"quote\"", @"quoted value",
                                         @"blah", @"\"quoted\" key",
                                         @"bslash\\", @"bslash value",
                                         @"x", @"bslash\\key",
                                         @"intl", @"テスト",
                                         nil]
                        zombieCacheSize:16384
               deadlockWatchdogInterval:5.0f
                     printTraceToStdout:YES
                                onCrash:onCrash];
}



- (BOOL)application:(UIApplication*) application didFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    #pragma unused(application)
    #pragma unused(launchOptions)

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
