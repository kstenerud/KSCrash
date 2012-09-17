//
//  AppDelegate.m
//  CrashLiteTester
//
//  Created by Karl Stenerud on 12-05-08.
//

#import "AppDelegate.h"

#import "ViewController.h"
#import "Paths.h"
#import "ARCSafe_MemMgmt.h"

#import <KSCrashLite/KSCrashReporter.h>


@implementation AppDelegate

@synthesize window = _window;
@synthesize viewController = _viewController;

- (NSString*) generateUUIDString
{
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString* uuidString = (as_bridge_transfer NSString*)CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    
    return uuidString;
}

static void onCrash(const KSReportWriter* writer)
{
    writer->addStringElement(writer, "test", "test");
    writer->addStringElement(writer, "intl2", "テスト２");
}

- (BOOL)application:(UIApplication*) application didFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    #pragma unused(application)
    #pragma unused(launchOptions)

    kscrash_installReporter([[Paths reportPath] UTF8String],
                            [[Paths statePath] UTF8String],
                            [[self generateUUIDString] UTF8String],
                            NULL,
                            0,
                            YES,
                            onCrash);

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.viewController = [[ViewController alloc] initWithNibName:@"ViewController" bundle:nil];
    self.window.rootViewController = self.viewController;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
