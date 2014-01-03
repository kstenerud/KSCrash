//
//  main.m
//  CrashTester
//
//  Created by Karl Stenerud on 2012-04-29.
//

#import <UIKit/UIKit.h>
#import "ARCSafe_MemMgmt.h"

#import "AppDelegate.h"

int main(int argc, char* argv[])
{
    as_autoreleasepool_start(pool_a);

    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));

    as_autoreleasepool_end(pool_a);
}
