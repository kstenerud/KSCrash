//
//  KSThread_Main.m
//  KSCrash
//
//  Created by Golder on 2019/4/16.
//  Copyright © 2019 Karl Stenerud. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KSThread_Main.h"

static KSThread g_mainThread;

KSThread ksthread_main(void) {
    return g_mainThread;
}

@interface KSThreadMain : NSObject

@end

@implementation KSThreadMain

+ (void)load {
    g_mainThread = ksthread_self();
}

@end
