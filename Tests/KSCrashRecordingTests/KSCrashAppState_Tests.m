//
//  KSCrashAppState_Tests.m
//
//  Created by Alexander Cohen on 2026-11-27.
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

#import <XCTest/XCTest.h>

#import "KSCrashAppState.h"
#import "KSCrashAppStateTracker.h"

extern void ksapp_testcode_publishTransitionState(KSCrashAppTransitionState state);
extern void ksapp_testcode_setHasBeenActive(bool hasBeenActive);

@interface KSCrashAppState_Tests : XCTestCase
@end

@implementation KSCrashAppState_Tests

- (void)setUp
{
    [super setUp];
    KSCrashAppTransitionState realState = ksapp_currentTransitionState();
    bool realHasBeenActive = ksapp_hasBeenActive();
    [self addTeardownBlock:^{
        ksapp_testcode_publishTransitionState(realState);
        ksapp_testcode_setHasBeenActive(realHasBeenActive);
    }];
}

- (void)testTheStateIsTheSharedTrackers
{
    XCTAssertEqual(ksapp_currentTransitionState(), KSCrashAppStateTracker.sharedInstance.transitionState);
}

- (void)testStartupLastsUntilTheFirstActive
{
    ksapp_testcode_setHasBeenActive(false);

    ksapp_testcode_publishTransitionState(KSCrashAppTransitionStateLaunching);
    ksapp_testcode_publishTransitionState(KSCrashAppTransitionStateForegrounding);
    XCTAssertFalse(ksapp_hasBeenActive());

    ksapp_testcode_publishTransitionState(KSCrashAppTransitionStateActive);
    XCTAssertTrue(ksapp_hasBeenActive());
    XCTAssertEqual(ksapp_currentTransitionState(), KSCrashAppTransitionStateActive);

    ksapp_testcode_publishTransitionState(KSCrashAppTransitionStateBackground);
    ksapp_testcode_publishTransitionState(KSCrashAppTransitionStateForegrounding);
    XCTAssertTrue(ksapp_hasBeenActive());
    XCTAssertEqual(ksapp_currentTransitionState(), KSCrashAppTransitionStateForegrounding);
}

@end
