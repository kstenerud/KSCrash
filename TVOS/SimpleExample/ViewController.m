//
//  ViewController.m
//  SimpleExample
//
//  Created by karl on 2016-04-08.
//  Copyright © 2016 Karl Stenerud. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (IBAction)onCrash:(id)sender
{
    [NSException raise:@"CrashException" format:@"It dun crashed!"];
}

@end
