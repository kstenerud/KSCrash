//
//  LoaderVC.m
//  Advanced-Example
//

#import "LoaderVC.h"

#import "AppDelegate.h"
#import <KSCrash/KSCrashInstallation.h>

/**
 * Defers application loading until all error reports have been sent.
 * This allows error reports to be sent even if the app's initialization
 * code is causing a crash.
 *
 * Normally you'd just have this view display Default.png so that it looks
 * no different from the launch view.
 */
@implementation LoaderVC

- (void) viewDidAppear:(BOOL) animated
{
    [super viewDidAppear:animated];
    
    // Send all outstanding reports, then show the main view controller.
    AppDelegate* appDelegate = [UIApplication sharedApplication].delegate;
    [appDelegate.crashInstallation sendAllReportsWithCompletion:^(NSArray* reports, BOOL completed, NSError* error)
     {
         if(completed)
         {
             NSLog(@"Sent %d reports", [reports count]);
         }
         else
         {
             NSLog(@"Failed to send reports: %@", error);
         }

         // If you added an alert to the installation, it will interfere with replacing
         // the root view controller. Delaying by 0.3 seconds mitigates this.
         [self performSelector:@selector(showMainVC) withObject:nil afterDelay:0.3];
     }];

}

- (void) showMainVC
{
    UIViewController* vc = [self.storyboard instantiateViewControllerWithIdentifier:@"MainVC"];
    [UIApplication sharedApplication].keyWindow.rootViewController = vc;
}

@end
