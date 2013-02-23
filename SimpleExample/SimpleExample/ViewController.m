//
//  ViewController.m
//  SimpleExample
//

#import "ViewController.h"

@implementation ViewController

- (IBAction)onCrash:(__unused id)sender
{
    id value = [[NSArray array] objectAtIndex:0];
    NSLog(@"Value = %@", value);
}

@end
