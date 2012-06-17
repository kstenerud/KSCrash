//
//  ViewController.m
//  CrashLiteTester
//
//  Created by Karl Stenerud on 12-05-08.
//

#import "ViewController.h"
#import "Paths.h"


@implementation ViewController

@synthesize crashTextView = _crashTextView;

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.crashTextView.text = [NSString stringWithContentsOfFile:[Paths reportPath]
                                                        encoding:NSUTF8StringEncoding
                                                           error:nil];
}

- (IBAction)onException:(id)sender
{
    #pragma unused(sender)
    id data = @"a";
    [data objectAtIndex:0];
}

- (IBAction)onBadPointer:(id)sender
{
    #pragma unused(sender)
    char* ptr = (char*)-1;
    *ptr = 1;
}

@end
