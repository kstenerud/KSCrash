//
//  KSCrashMonitor_Resource_Tests.m
//
//  Created by Codex on 2026-09-13.
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

#import "KSCrashAppMemory+Private.h"
#import "KSCrashAppMemoryTracker.h"
#import "KSCrashMonitor_Resource.h"

@interface KSCrashAppMemoryTracker (ResourceTests)
- (void)_heartbeat:(BOOL)sendObservers;
@end

static NSString *g_sidecarPath;

static bool testRunSidecarPath(__unused const char *monitorId, char *path, size_t length)
{
    return g_sidecarPath != nil && snprintf(path, length, "%s", g_sidecarPath.fileSystemRepresentation) < (int)length;
}

static KSCrashAppMemory *memorySample(uint64_t footprint, uint64_t systemRemaining, KSCrashAppMemoryState pressure)
{
    return [[KSCrashAppMemory alloc] initWithFootprint:footprint
                                             remaining:100000000 - footprint
                                              pressure:pressure
                                       systemRemaining:systemRemaining
                                           systemLimit:1000000000];
}

@interface KSCrashMonitor_Resource_Tests : XCTestCase
@property(nonatomic, strong) KSCrashAppMemoryTracker *tracker;
@property(atomic, strong) KSCrashAppMemory *sample;
@property(nonatomic, assign) BOOL trackerWasRunning;
@end

@implementation KSCrashMonitor_Resource_Tests

- (void)setUp
{
    [super setUp];
    self.tracker = KSCrashAppMemoryTracker.sharedInstance;
    self.trackerWasRunning = [self.tracker valueForKey:@"limitSource"] != nil;
    [self.tracker stop];
    // Drain the timer before controlling the provider and driving heartbeats.
    dispatch_queue_t queue = [self.tracker valueForKey:@"heartbeatQueue"];
    dispatch_sync(queue, ^ {
                  });
    testsupport_KSCrashAppMemorySetProvider(^KSCrashAppMemory * {
        return self.sample;
    });

    g_sidecarPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    KSCrashMonitorAPI *api = kscm_resource_getAPI();
    api->setEnabled(false, NULL);
    KSCrash_ExceptionHandlerCallbacks callbacks = { .getRunSidecarPath = testRunSidecarPath };
    api->init(&callbacks, NULL);
}

- (void)tearDown
{
    KSCrashMonitorAPI *api = kscm_resource_getAPI();
    api->setEnabled(false, NULL);
    KSCrash_ExceptionHandlerCallbacks callbacks = {};
    api->init(&callbacks, NULL);
    testsupport_KSCrashAppMemorySetProvider(nil);
    if (self.trackerWasRunning) [self.tracker start];
    [[NSFileManager defaultManager] removeItemAtPath:g_sidecarPath error:nil];
    g_sidecarPath = nil;
    [super tearDown];
}

- (void)assertSidecarMatchesSample:(KSCrashAppMemory *)sample
{
    KSCrash_ResourceData data = {};
    XCTAssertTrue(ksresource_readSnapshotFromPath(g_sidecarPath.fileSystemRepresentation, &data));
    XCTAssertEqual(data.memoryFootprint, sample.footprint);
    XCTAssertEqual(data.memoryRemaining, sample.remaining);
    XCTAssertEqual(data.memoryLimit, sample.limit);
    XCTAssertEqual(data.memoryLevel, sample.level);
    XCTAssertEqual(data.memoryPressure, sample.pressure);
    XCTAssertEqual(data.systemMemoryRemaining, sample.systemRemaining);
    XCTAssertEqual(data.systemMemoryLimit, sample.systemLimit);
    XCTAssertEqual(data.memoryHeadroom, sample.headroom);
    XCTAssertGreaterThan(data.memoryUpdatedAtNs, 0ULL);
}

- (void)testInitialSnapshotIsPersistedBeforeHeartbeat
{
    self.sample = memorySample(74000000, 51000000, KSCrashAppMemoryStateWarn);
    kscm_resource_getAPI()->setEnabled(true, NULL);
    [self assertSidecarMatchesSample:self.sample];
}

- (void)testMemoryUpdateRefreshesStatesWithoutStateChangeFlags
{
    // The tracker and resource seed can sample opposite sides of a boundary.
    self.sample = memorySample(76000000, 49000000, KSCrashAppMemoryStateCritical);
    [self.tracker _heartbeat:NO];
    self.sample = memorySample(74000000, 51000000, KSCrashAppMemoryStateNormal);
    kscm_resource_getAPI()->setEnabled(true, NULL);
    [self assertSidecarMatchesSample:self.sample];

    __block KSCrashAppMemoryTrackerChangeType observedChanges = KSCrashAppMemoryTrackerChangeTypeNone;
    id observer = [self.tracker
        addObserverWithBlock:^(__unused KSCrashAppMemory *memory, KSCrashAppMemoryTrackerChangeType changes) {
            observedChanges = changes;
        }];

    // Both states return to the tracker's previous bands, so only byte-change
    // flags are sent. All persisted values, including pressure, must still
    // come from this sample instead of retaining labels from the initial seed.
    self.sample = memorySample(80000000, 30000000, KSCrashAppMemoryStateCritical);
    [self.tracker _heartbeat:NO];
    XCTAssertEqual(observedChanges,
                   KSCrashAppMemoryTrackerChangeTypeFootprint | KSCrashAppMemoryTrackerChangeTypeSystemRemaining);
    [self assertSidecarMatchesSample:self.sample];
    XCTAssertNotNil(observer);
}

@end
