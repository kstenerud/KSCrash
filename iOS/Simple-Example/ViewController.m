//
//  ViewController.m
//  Simple-Example
//

#import "ViewController.h"

@implementation ViewController

- (IBAction) onCrash:(__unused id) sender
{
    char* ptr = (char*)-1;
    *ptr = 10;
}

@end
