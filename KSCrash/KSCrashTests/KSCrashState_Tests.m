//
//  KSCrashState_Tests.m
//
//  Created by Karl Stenerud on 2012-02-05.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//


#import "FileBasedTestCase.h"
#import "SenTestCase+KSCrash.h"

#import "KSCrashState.h"


@interface KSCrashState_Tests : FileBasedTestCase@end


@implementation KSCrashState_Tests

- (void) testInitRelaunch
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);

    STAssertTrue(context.applicationIsInForeground, @"");
    STAssertFalse(context.applicationIsActive, @"");

    STAssertEquals(context.activeDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.launchesSinceLastCrash, 1, @"");
    STAssertEquals(context.sessionsSinceLastCrash, 1, @"");

    STAssertEquals(context.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.sessionsSinceLaunch, 1, @"");

    STAssertFalse(context.crashedThisLaunch, @"");
    STAssertFalse(context.crashedLastLaunch, @"");

    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);

    STAssertTrue(context.applicationIsInForeground, @"");
    STAssertFalse(context.applicationIsActive, @"");

    STAssertEquals(context.activeDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.launchesSinceLastCrash, 2, @"");
    STAssertEquals(context.sessionsSinceLastCrash, 2, @"");

    STAssertEquals(context.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.sessionsSinceLaunch, 1, @"");

    STAssertFalse(context.crashedThisLaunch, @"");
    STAssertFalse(context.crashedLastLaunch, @"");
}

- (void) testInitCrash
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    KSCrash_State checkpoint0 = context;

    usleep(1);
    kscrashstate_notifyAppCrash();
    KSCrash_State checkpointC = context;

    STAssertTrue(checkpointC.applicationIsInForeground ==
                 checkpoint0.applicationIsInForeground, @"");
    STAssertTrue(checkpointC.applicationIsActive ==
                 checkpoint0.applicationIsActive, @"");

    STAssertTrue(checkpointC.activeDurationSinceLastCrash ==
                 checkpoint0.activeDurationSinceLastCrash, @"");
    STAssertTrue(checkpointC.backgroundDurationSinceLastCrash ==
                 checkpoint0.backgroundDurationSinceLastCrash, @"");
    STAssertTrue(checkpointC.launchesSinceLastCrash ==
                 checkpoint0.launchesSinceLastCrash, @"");
    STAssertTrue(checkpointC.sessionsSinceLastCrash ==
                 checkpoint0.sessionsSinceLastCrash, @"");

    STAssertTrue(checkpointC.activeDurationSinceLaunch ==
                 checkpoint0.activeDurationSinceLaunch, @"");
    STAssertTrue(checkpointC.backgroundDurationSinceLaunch ==
                 checkpoint0.backgroundDurationSinceLaunch, @"");
    STAssertTrue(checkpointC.sessionsSinceLaunch ==
                 checkpoint0.sessionsSinceLaunch, @"");

    STAssertTrue(checkpointC.crashedThisLaunch, @"");
    STAssertFalse(checkpointC.crashedLastLaunch, @"");

    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);

    STAssertTrue(context.applicationIsInForeground, @"");
    STAssertFalse(context.applicationIsActive, @"");

    STAssertEquals(context.activeDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.launchesSinceLastCrash, 1, @"");
    STAssertEquals(context.sessionsSinceLastCrash, 1, @"");

    STAssertEquals(context.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.sessionsSinceLaunch, 1, @"");

    STAssertFalse(context.crashedThisLaunch, @"");
    STAssertTrue(context.crashedLastLaunch, @"");
}

- (void) testActRelaunch
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    KSCrash_State checkpoint0 = context;

    usleep(1);
    kscrashstate_notifyAppActive(true);
    KSCrash_State checkpoint1 = context;

    STAssertTrue(checkpoint1.applicationIsInForeground ==
                 checkpoint0.applicationIsInForeground, @"");
    STAssertTrue(checkpoint1.applicationIsActive !=
                 checkpoint0.applicationIsActive, @"");
    STAssertTrue(checkpoint1.applicationIsActive, @"");

    STAssertTrue(checkpoint1.activeDurationSinceLastCrash ==
                 checkpoint0.activeDurationSinceLastCrash, @"");
    STAssertTrue(checkpoint1.backgroundDurationSinceLastCrash ==
                 checkpoint0.backgroundDurationSinceLastCrash, @"");
    STAssertTrue(checkpoint1.launchesSinceLastCrash ==
                 checkpoint0.launchesSinceLastCrash, @"");
    STAssertTrue(checkpoint1.sessionsSinceLastCrash ==
                 checkpoint0.sessionsSinceLastCrash, @"");

    STAssertTrue(checkpoint1.activeDurationSinceLaunch ==
                 checkpoint0.activeDurationSinceLaunch, @"");
    STAssertTrue(checkpoint1.backgroundDurationSinceLaunch ==
                 checkpoint0.backgroundDurationSinceLaunch, @"");
    STAssertTrue(checkpoint1.sessionsSinceLaunch ==
                 checkpoint0.sessionsSinceLaunch, @"");

    STAssertFalse(checkpoint1.crashedThisLaunch, @"");
    STAssertFalse(checkpoint1.crashedLastLaunch, @"");

    usleep(1);
    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);

    STAssertTrue(context.applicationIsInForeground, @"");
    STAssertFalse(context.applicationIsActive, @"");

    STAssertEquals(context.activeDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.launchesSinceLastCrash, 2, @"");
    STAssertEquals(context.sessionsSinceLastCrash, 2, @"");

    STAssertEquals(context.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.sessionsSinceLaunch, 1, @"");

    STAssertFalse(context.crashedThisLaunch, @"");
    STAssertFalse(context.crashedLastLaunch, @"");
}

- (void) testActCrash
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    usleep(1);
    kscrashstate_notifyAppActive(true);
    KSCrash_State checkpoint0 = context;

    usleep(1);
    kscrashstate_notifyAppCrash();
    KSCrash_State checkpointC = context;

    STAssertTrue(checkpointC.applicationIsInForeground ==
                 checkpoint0.applicationIsInForeground, @"");
    STAssertTrue(checkpointC.applicationIsActive ==
                 checkpoint0.applicationIsActive, @"");

    STAssertTrue(checkpointC.activeDurationSinceLastCrash >
                 checkpoint0.activeDurationSinceLastCrash, @"");
    STAssertTrue(checkpointC.backgroundDurationSinceLastCrash ==
                 checkpoint0.backgroundDurationSinceLastCrash, @"");
    STAssertTrue(checkpointC.launchesSinceLastCrash ==
                 checkpoint0.launchesSinceLastCrash, @"");
    STAssertTrue(checkpointC.sessionsSinceLastCrash ==
                 checkpoint0.sessionsSinceLastCrash, @"");

    STAssertTrue(checkpointC.activeDurationSinceLaunch >
                 checkpoint0.activeDurationSinceLaunch, @"");
    STAssertTrue(checkpointC.backgroundDurationSinceLaunch ==
                 checkpoint0.backgroundDurationSinceLaunch, @"");
    STAssertTrue(checkpointC.sessionsSinceLaunch ==
                 checkpoint0.sessionsSinceLaunch, @"");

    STAssertTrue(checkpointC.crashedThisLaunch, @"");
    STAssertFalse(checkpointC.crashedLastLaunch, @"");

    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);

    STAssertTrue(context.applicationIsInForeground, @"");
    STAssertFalse(context.applicationIsActive, @"");

    STAssertEquals(context.activeDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.launchesSinceLastCrash, 1, @"");
    STAssertEquals(context.sessionsSinceLastCrash, 1, @"");

    STAssertEquals(context.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.sessionsSinceLaunch, 1, @"");

    STAssertFalse(context.crashedThisLaunch, @"");
    STAssertTrue(context.crashedLastLaunch, @"");
}

- (void) testActDeactRelaunch
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    usleep(1);
    kscrashstate_notifyAppActive(true);
    KSCrash_State checkpoint0 = context;

    usleep(1);
    kscrashstate_notifyAppActive(false);
    KSCrash_State checkpoint1 = context;

    STAssertTrue(checkpoint1.applicationIsInForeground ==
                 checkpoint0.applicationIsInForeground, @"");
    STAssertTrue(checkpoint1.applicationIsActive !=
                 checkpoint0.applicationIsActive, @"");
    STAssertFalse(checkpoint1.applicationIsActive, @"");

    STAssertTrue(checkpoint1.activeDurationSinceLastCrash >
                 checkpoint0.activeDurationSinceLastCrash, @"");
    STAssertTrue(checkpoint1.backgroundDurationSinceLastCrash ==
                 checkpoint0.backgroundDurationSinceLastCrash, @"");
    STAssertTrue(checkpoint1.launchesSinceLastCrash ==
                 checkpoint0.launchesSinceLastCrash, @"");
    STAssertTrue(checkpoint1.sessionsSinceLastCrash ==
                 checkpoint0.sessionsSinceLastCrash, @"");

    STAssertTrue(checkpoint1.activeDurationSinceLaunch >
                 checkpoint0.activeDurationSinceLaunch, @"");
    STAssertTrue(checkpoint1.backgroundDurationSinceLaunch ==
                 checkpoint0.backgroundDurationSinceLaunch, @"");
    STAssertTrue(checkpoint1.sessionsSinceLaunch ==
                 checkpoint0.sessionsSinceLaunch, @"");

    STAssertFalse(checkpoint1.crashedThisLaunch, @"");
    STAssertFalse(checkpoint1.crashedLastLaunch, @"");

    usleep(1);
    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    KSCrash_State checkpointR = context;

    STAssertTrue(checkpointR.applicationIsInForeground, @"");
    STAssertFalse(checkpointR.applicationIsActive, @"");

    // We don't save after going inactive, so this will still be 0.
    STAssertEquals(checkpointR.activeDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(checkpointR.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(checkpointR.launchesSinceLastCrash, 2, @"");
    STAssertEquals(checkpointR.sessionsSinceLastCrash, 2, @"");

    STAssertEquals(checkpointR.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(checkpointR.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(checkpointR.sessionsSinceLaunch, 1, @"");

    STAssertFalse(checkpointR.crashedThisLaunch, @"");
    STAssertFalse(checkpointR.crashedLastLaunch, @"");
}

- (void) testActDeactCrash
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    usleep(1);
    kscrashstate_notifyAppActive(true);
    usleep(1);
    kscrashstate_notifyAppActive(false);
    KSCrash_State checkpoint0 = context;

    usleep(1);
    kscrashstate_notifyAppCrash();
    KSCrash_State checkpointC = context;

    STAssertTrue(checkpointC.applicationIsInForeground ==
                 checkpoint0.applicationIsInForeground, @"");
    STAssertTrue(checkpointC.applicationIsActive ==
                 checkpoint0.applicationIsActive, @"");

    STAssertTrue(checkpointC.activeDurationSinceLastCrash ==
                 checkpoint0.activeDurationSinceLastCrash, @"");
    STAssertTrue(checkpointC.backgroundDurationSinceLastCrash ==
                 checkpoint0.backgroundDurationSinceLastCrash, @"");
    STAssertTrue(checkpointC.launchesSinceLastCrash ==
                 checkpoint0.launchesSinceLastCrash, @"");
    STAssertTrue(checkpointC.sessionsSinceLastCrash ==
                 checkpoint0.sessionsSinceLastCrash, @"");

    STAssertTrue(checkpointC.activeDurationSinceLaunch ==
                 checkpoint0.activeDurationSinceLaunch, @"");
    STAssertTrue(checkpointC.backgroundDurationSinceLaunch ==
                 checkpoint0.backgroundDurationSinceLaunch, @"");
    STAssertTrue(checkpointC.sessionsSinceLaunch ==
                 checkpoint0.sessionsSinceLaunch, @"");

    STAssertTrue(checkpointC.crashedThisLaunch, @"");
    STAssertFalse(checkpointC.crashedLastLaunch, @"");

    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);

    STAssertTrue(context.applicationIsInForeground, @"");
    STAssertFalse(context.applicationIsActive, @"");

    STAssertEquals(context.activeDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.launchesSinceLastCrash, 1, @"");
    STAssertEquals(context.sessionsSinceLastCrash, 1, @"");

    STAssertEquals(context.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.sessionsSinceLaunch, 1, @"");

    STAssertFalse(context.crashedThisLaunch, @"");
    STAssertTrue(context.crashedLastLaunch, @"");
}

- (void) testActDeactBGRelaunch
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    usleep(1);
    kscrashstate_notifyAppActive(true);
    usleep(1);
    kscrashstate_notifyAppActive(false);
    KSCrash_State checkpoint0 = context;

    usleep(1);
    kscrashstate_notifyAppInForeground(false);
    KSCrash_State checkpoint1 = context;

    STAssertTrue(checkpoint1.applicationIsInForeground !=
                 checkpoint0.applicationIsInForeground, @"");
    STAssertTrue(checkpoint1.applicationIsActive ==
                 checkpoint0.applicationIsActive, @"");
    STAssertFalse(checkpoint1.applicationIsInForeground, @"");

    STAssertTrue(checkpoint1.activeDurationSinceLastCrash ==
                 checkpoint0.activeDurationSinceLastCrash, @"");
    STAssertTrue(checkpoint1.backgroundDurationSinceLastCrash ==
                 checkpoint0.backgroundDurationSinceLastCrash, @"");
    STAssertTrue(checkpoint1.launchesSinceLastCrash ==
                 checkpoint0.launchesSinceLastCrash, @"");
    STAssertTrue(checkpoint1.sessionsSinceLastCrash ==
                 checkpoint0.sessionsSinceLastCrash, @"");

    STAssertTrue(checkpoint1.activeDurationSinceLaunch ==
                 checkpoint0.activeDurationSinceLaunch, @"");
    STAssertTrue(checkpoint1.backgroundDurationSinceLaunch ==
                 checkpoint0.backgroundDurationSinceLaunch, @"");
    STAssertTrue(checkpoint1.sessionsSinceLaunch ==
                 checkpoint0.sessionsSinceLaunch, @"");

    STAssertFalse(checkpoint1.crashedThisLaunch, @"");
    STAssertFalse(checkpoint1.crashedLastLaunch, @"");

    usleep(1);
    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    KSCrash_State checkpointR = context;

    STAssertTrue(checkpointR.applicationIsInForeground, @"");
    STAssertFalse(checkpointR.applicationIsActive, @"");

    STAssertTrue(checkpointR.activeDurationSinceLastCrash > 0, @"");
    STAssertEquals(checkpointR.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(checkpointR.launchesSinceLastCrash, 2, @"");
    STAssertEquals(checkpointR.sessionsSinceLastCrash, 2, @"");

    STAssertEquals(checkpointR.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(checkpointR.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(checkpointR.sessionsSinceLaunch, 1, @"");

    STAssertFalse(checkpointR.crashedThisLaunch, @"");
    STAssertFalse(checkpointR.crashedLastLaunch, @"");
}

- (void) testActDeactBGTerminate
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    usleep(1);
    kscrashstate_notifyAppActive(true);
    usleep(1);
    kscrashstate_notifyAppActive(false);
    usleep(1);
    kscrashstate_notifyAppInForeground(false);
    KSCrash_State checkpoint0 = context;
    usleep(1);
    kscrashstate_notifyAppTerminate();

    usleep(1);
    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    KSCrash_State checkpointR = context;

    STAssertTrue(checkpointR.applicationIsInForeground, @"");
    STAssertFalse(checkpointR.applicationIsActive, @"");

    STAssertTrue(checkpointR.backgroundDurationSinceLastCrash >
                 checkpoint0.backgroundDurationSinceLastCrash, @"");
    STAssertEquals(checkpointR.launchesSinceLastCrash, 2, @"");
    STAssertEquals(checkpointR.sessionsSinceLastCrash, 2, @"");

    STAssertEquals(checkpointR.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(checkpointR.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(checkpointR.sessionsSinceLaunch, 1, @"");

    STAssertFalse(checkpointR.crashedThisLaunch, @"");
    STAssertFalse(checkpointR.crashedLastLaunch, @"");
}

- (void) testActDeactBGCrash
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    usleep(1);
    kscrashstate_notifyAppActive(true);
    usleep(1);
    kscrashstate_notifyAppActive(false);
    usleep(1);
    kscrashstate_notifyAppInForeground(false);
    KSCrash_State checkpoint0 = context;

    usleep(1);
    kscrashstate_notifyAppCrash();
    KSCrash_State checkpointC = context;

    STAssertTrue(checkpointC.applicationIsInForeground ==
                 checkpoint0.applicationIsInForeground, @"");
    STAssertTrue(checkpointC.applicationIsActive ==
                 checkpoint0.applicationIsActive, @"");

    STAssertTrue(checkpointC.activeDurationSinceLastCrash ==
                 checkpoint0.activeDurationSinceLastCrash, @"");
    STAssertTrue(checkpointC.backgroundDurationSinceLastCrash >
                 checkpoint0.backgroundDurationSinceLastCrash, @"");
    STAssertTrue(checkpointC.launchesSinceLastCrash ==
                 checkpoint0.launchesSinceLastCrash, @"");
    STAssertTrue(checkpointC.sessionsSinceLastCrash ==
                 checkpoint0.sessionsSinceLastCrash, @"");

    STAssertTrue(checkpointC.activeDurationSinceLaunch ==
                 checkpoint0.activeDurationSinceLaunch, @"");
    STAssertTrue(checkpointC.backgroundDurationSinceLaunch >
                 checkpoint0.backgroundDurationSinceLaunch, @"");
    STAssertTrue(checkpointC.sessionsSinceLaunch ==
                 checkpoint0.sessionsSinceLaunch, @"");

    STAssertTrue(checkpointC.crashedThisLaunch, @"");
    STAssertFalse(checkpointC.crashedLastLaunch, @"");

    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);

    STAssertTrue(context.applicationIsInForeground, @"");
    STAssertFalse(context.applicationIsActive, @"");

    STAssertEquals(context.activeDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.launchesSinceLastCrash, 1, @"");
    STAssertEquals(context.sessionsSinceLastCrash, 1, @"");

    STAssertEquals(context.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.sessionsSinceLaunch, 1, @"");

    STAssertFalse(context.crashedThisLaunch, @"");
    STAssertTrue(context.crashedLastLaunch, @"");
}

- (void) testActDeactBGFGRelaunch
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    usleep(1);
    kscrashstate_notifyAppActive(true);
    usleep(1);
    kscrashstate_notifyAppActive(false);
    usleep(1);
    kscrashstate_notifyAppInForeground(false);
    usleep(1);
    KSCrash_State checkpoint0 = context;

    usleep(1);
    kscrashstate_notifyAppInForeground(true);
    KSCrash_State checkpoint1 = context;

    STAssertTrue(checkpoint1.applicationIsInForeground !=
                 checkpoint0.applicationIsInForeground, @"");
    STAssertTrue(checkpoint1.applicationIsActive ==
                 checkpoint0.applicationIsActive, @"");
    STAssertTrue(checkpoint1.applicationIsInForeground, @"");

    STAssertTrue(checkpoint1.activeDurationSinceLastCrash ==
                 checkpoint0.activeDurationSinceLastCrash, @"");
    STAssertTrue(checkpoint1.backgroundDurationSinceLastCrash >
                 checkpoint0.backgroundDurationSinceLastCrash, @"");
    STAssertTrue(checkpoint1.launchesSinceLastCrash ==
                 checkpoint0.launchesSinceLastCrash, @"");
    STAssertTrue(checkpoint1.sessionsSinceLastCrash ==
                 checkpoint0.sessionsSinceLastCrash + 1, @"");

    STAssertTrue(checkpoint1.activeDurationSinceLaunch ==
                 checkpoint0.activeDurationSinceLaunch, @"");
    STAssertTrue(checkpoint1.backgroundDurationSinceLaunch >
                 checkpoint0.backgroundDurationSinceLaunch, @"");
    STAssertTrue(checkpoint1.sessionsSinceLaunch ==
                 checkpoint0.sessionsSinceLaunch + 1, @"");

    STAssertFalse(checkpoint1.crashedThisLaunch, @"");
    STAssertFalse(checkpoint1.crashedLastLaunch, @"");

    usleep(1);
    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    KSCrash_State checkpointR = context;

    STAssertTrue(checkpointR.applicationIsInForeground, @"");
    STAssertFalse(checkpointR.applicationIsActive, @"");

    STAssertTrue(checkpointR.activeDurationSinceLastCrash > 0, @"");
    // We don't save after going to FG, so this will still be 0.
    STAssertEquals(checkpointR.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(checkpointR.launchesSinceLastCrash, 2, @"");
    STAssertEquals(checkpointR.sessionsSinceLastCrash, 2, @"");

    STAssertEquals(checkpointR.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(checkpointR.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(checkpointR.sessionsSinceLaunch, 1, @"");

    STAssertFalse(checkpointR.crashedThisLaunch, @"");
    STAssertFalse(checkpointR.crashedLastLaunch, @"");
}

- (void) testActDeactBGFGCrash
{
    KSCrash_State context = {0};
    NSString* stateFile = [self.tempPath stringByAppendingPathComponent:@"state.json"];

    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);
    usleep(1);
    kscrashstate_notifyAppActive(true);
    usleep(1);
    kscrashstate_notifyAppActive(false);
    usleep(1);
    kscrashstate_notifyAppInForeground(false);
    usleep(1);
    kscrashstate_notifyAppInForeground(true);
    KSCrash_State checkpoint0 = context;

    usleep(1);
    kscrashstate_notifyAppCrash();
    KSCrash_State checkpointC = context;

    STAssertTrue(checkpointC.applicationIsInForeground ==
                 checkpoint0.applicationIsInForeground, @"");
    STAssertTrue(checkpointC.applicationIsActive ==
                 checkpoint0.applicationIsActive, @"");

    STAssertTrue(checkpointC.activeDurationSinceLastCrash ==
                 checkpoint0.activeDurationSinceLastCrash, @"");
    STAssertTrue(checkpointC.backgroundDurationSinceLastCrash ==
                 checkpoint0.backgroundDurationSinceLastCrash, @"");
    STAssertTrue(checkpointC.launchesSinceLastCrash ==
                 checkpoint0.launchesSinceLastCrash, @"");
    STAssertTrue(checkpointC.sessionsSinceLastCrash ==
                 checkpoint0.sessionsSinceLastCrash, @"");

    STAssertTrue(checkpointC.activeDurationSinceLaunch ==
                 checkpoint0.activeDurationSinceLaunch, @"");
    STAssertTrue(checkpointC.backgroundDurationSinceLaunch ==
                 checkpoint0.backgroundDurationSinceLaunch, @"");
    STAssertTrue(checkpointC.sessionsSinceLaunch ==
                 checkpoint0.sessionsSinceLaunch, @"");

    STAssertTrue(checkpointC.crashedThisLaunch, @"");
    STAssertFalse(checkpointC.crashedLastLaunch, @"");

    memset(&context, 0, sizeof(context));
    kscrashstate_init([stateFile cStringUsingEncoding:NSUTF8StringEncoding],
                      &context);

    STAssertTrue(context.applicationIsInForeground, @"");
    STAssertFalse(context.applicationIsActive, @"");

    STAssertEquals(context.activeDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLastCrash, 0.0, @"");
    STAssertEquals(context.launchesSinceLastCrash, 1, @"");
    STAssertEquals(context.sessionsSinceLastCrash, 1, @"");

    STAssertEquals(context.activeDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.backgroundDurationSinceLaunch, 0.0, @"");
    STAssertEquals(context.sessionsSinceLaunch, 1, @"");

    STAssertFalse(context.crashedThisLaunch, @"");
    STAssertTrue(context.crashedLastLaunch, @"");
}

@end
