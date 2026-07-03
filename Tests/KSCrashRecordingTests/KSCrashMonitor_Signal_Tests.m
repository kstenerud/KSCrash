//
//  KSCrashMonitor_Signal_Tests.m
//
//  Created by Karl Stenerud on 2013-01-26.
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

#include <signal.h>

#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Signal.h"
#import "KSSystemCapabilities.h"

@interface KSCrashMonitor_Signal_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Signal_Tests

#if KSCRASH_HAS_SIGNAL

- (void)testInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_signal_getAPI();
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    [NSThread sleepForTimeInterval:0.1];
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testDoubleInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_signal_getAPI();

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));

    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testPreservesIgnoredSignalHandlers
{
    KSCrashMonitorAPI *api = kscm_signal_getAPI();
    api->setEnabled(false, NULL);

    struct sigaction originalAction;
    XCTAssertEqual(sigaction(SIGPIPE, NULL, &originalAction), 0);

    struct sigaction ignoredAction = { { 0 } };
    ignoredAction.sa_handler = SIG_IGN;
    sigemptyset(&ignoredAction.sa_mask);
    XCTAssertEqual(sigaction(SIGPIPE, &ignoredAction, NULL), 0);

    @try {
        api->setEnabled(true, NULL);
        XCTAssertTrue(api->isEnabled(NULL));

        struct sigaction currentAction;
        XCTAssertEqual(sigaction(SIGPIPE, NULL, &currentAction), 0);
        XCTAssertEqual(currentAction.sa_handler, SIG_IGN);
    } @finally {
        api->setEnabled(false, NULL);
        sigaction(SIGPIPE, &originalAction, NULL);
    }
}

#else

- (void)testNoImplementation
{
    KSCrashMonitorAPI *api = kscm_signal_getAPI();
    XCTAssertTrue(api->monitorId(NULL) != NULL);
}

#endif

@end
