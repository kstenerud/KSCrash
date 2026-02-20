//
//  KSCrashMonitor_DiscSpace_Tests.m
//
//  Created by Gleb Linnik on 10.06.2024.
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

#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_DiscSpace.h"
#import "KSCrashMonitor_System.h"
#import "KSFileUtils.h"

#include <errno.h>
#include <fcntl.h>

extern void kscm_discSpace_resetState(void);

static char g_sidecarPath[512];

static bool stubRunSidecarPath(const char *monitorId, char *pathBuffer, size_t pathBufferLength)
{
    if (g_sidecarPath[0] == '\0') {
        return false;
    }
    snprintf(pathBuffer, pathBufferLength, "%s/%s.ksscr", g_sidecarPath, monitorId);
    return true;
}

@interface KSCrashMonitorDiscSpaceTests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation KSCrashMonitorDiscSpaceTests

- (void)setUp
{
    [super setUp];
    kscm_discSpace_resetState();

    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    strlcpy(g_sidecarPath, self.tempDir.fileSystemRepresentation, sizeof(g_sidecarPath));

    KSCrashMonitorAPI *sysApi = kscm_system_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .getRunSidecarPath = stubRunSidecarPath };
    sysApi->init(&callbacks, NULL);
    sysApi->setEnabled(true, NULL);
}

- (void)tearDown
{
    KSCrashMonitorAPI *sysApi = kscm_system_getAPI();
    sysApi->setEnabled(false, NULL);

    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    g_sidecarPath[0] = '\0';
    [super tearDown];
}

- (void)testMonitorActivation
{
    KSCrashMonitorAPI *discSpaceMonitor = kscm_discspace_getAPI();

    XCTAssertFalse(discSpaceMonitor->isEnabled(NULL), @"Disc space monitor should be initially disabled.");
    discSpaceMonitor->setEnabled(true, NULL);
    XCTAssertTrue(discSpaceMonitor->isEnabled(NULL), @"Disc space monitor should be enabled after setting.");
    discSpaceMonitor->setEnabled(false, NULL);
    XCTAssertFalse(discSpaceMonitor->isEnabled(NULL), @"Disc space monitor should be disabled after setting.");
}

- (void)testNotifyPostSystemEnableSetsDiscSpace
{
    KSCrashMonitorAPI *discSpaceMonitor = kscm_discspace_getAPI();
    discSpaceMonitor->setEnabled(true, NULL);

    discSpaceMonitor->notifyPostSystemEnable(NULL);

    KSCrash_SystemData sd = {};
    XCTAssertTrue(kscm_system_getSystemData(&sd));
    XCTAssertGreaterThan(sd.storageSize, (uint64_t)0, @"storageSize should be set after notifyPostSystemEnable");
    XCTAssertGreaterThan(sd.freeStorageSize, (uint64_t)0,
                         @"freeStorageSize should be set after notifyPostSystemEnable");
}

- (void)testNoDiscSpaceWhenDisabled
{
    KSCrashMonitorAPI *discSpaceMonitor = kscm_discspace_getAPI();
    discSpaceMonitor->setEnabled(false, NULL);

    discSpaceMonitor->notifyPostSystemEnable(NULL);

    KSCrash_SystemData sd = {};
    XCTAssertTrue(kscm_system_getSystemData(&sd));
    XCTAssertEqual(sd.storageSize, (uint64_t)0, @"storageSize should not be set when the monitor is disabled.");
}

- (void)testMonitorName
{
    KSCrashMonitorAPI *discSpaceMonitor = kscm_discspace_getAPI();
    XCTAssertEqual(strcmp(discSpaceMonitor->monitorId(NULL), "DiscSpace"), 0,
                   @"The monitor name should be 'DiscSpace'.");
}

@end
