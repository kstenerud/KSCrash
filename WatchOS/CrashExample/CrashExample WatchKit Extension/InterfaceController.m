//
//  InterfaceController.m
//  CrashExample WatchKit Extension
//
//  Created by Karl on 2016-10-18.
//  Copyright © 2016 Karl Stenerud. All rights reserved.
//

#import "InterfaceController.h"


@interface InterfaceController()

@end


@implementation InterfaceController

- (void)awakeWithContext:(id)context {
    [super awakeWithContext:context];

    // Configure interface objects here.
}

- (void)willActivate {
    // This method is called when watch view controller is about to be visible to user
    [super willActivate];
}

- (void)didDeactivate {
    // This method is called when watch view controller is no longer visible
    [super didDeactivate];
}

- (IBAction)onCrash:(id)sender {
    [NSException raise:@"TestException" format:@"Testing"];
}

@end



