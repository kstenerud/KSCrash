//
//  AppDelegate.m
//  SimpleExample
//
//  Created by karl on 2016-04-08.
//  Copyright © 2016 Karl Stenerud. All rights reserved.
//

#import "AppDelegate.h"
#import <KSCrash/KSCrashInstallationConsole.h>

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    KSCrashInstallationConsole* installation = [KSCrashInstallationConsole new];
    installation.printAppleFormat = NO;
    [installation install];
    
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
    
    return YES;
}

@end
