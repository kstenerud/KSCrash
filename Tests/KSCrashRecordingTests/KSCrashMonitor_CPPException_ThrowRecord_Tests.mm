// SPDX-License-Identifier: MIT
#import <XCTest/XCTest.h>

#import "KSCrashMonitor_CPPException+ThrowRecord.h"

#include <thread>

@interface KSCrashMonitor_CPPException_ThrowRecord_Tests : XCTestCase
@end

@implementation KSCrashMonitor_CPPException_ThrowRecord_Tests

- (void)testCollisionLeavesTheFirstRecordIntact
{
    // Exercise one slot directly: this should not depend on the hash or the allocator.
    ThrowRecord slot;
    int first = 0, second = 0;
    XCTAssertTrue(slot.tryReserve());
    XCTAssertFalse(slot.tryReserve());  // Still capturing, not yet published.
    XCTAssertFalse(slot.matches(&first));

    slot.publish(&first, [](void *p) { ++*static_cast<int *>(p); });
    XCTAssertFalse(slot.tryReserve());
    XCTAssertFalse(slot.matches(&second));
    XCTAssertTrue(slot.matches(&first));

    slot.release(&first);
    XCTAssertEqual(first, 1);
    XCTAssertEqual(second, 0);
    XCTAssertFalse(slot.matches(&first));
}

- (void)testAddressCanBeReusedAfterNullDestructor
{
    ThrowRecord slot;
    int object = 0;
    XCTAssertTrue(slot.tryReserve());

    slot.publish(&object, nullptr);
    slot.release(&object);
    XCTAssertFalse(slot.matches(&object));

    // Same address, different lifetime and destructor.
    XCTAssertTrue(slot.tryReserve());
    slot.publish(&object, [](void *p) { ++*static_cast<int *>(p); });
    slot.release(&object);
    XCTAssertEqual(object, 1);
}

- (void)testOnlyOneConcurrentThrowCanPublishToASlot
{
    ThrowRecord slot;
    std::atomic<int> ready { 0 };
    int objects[2] = {};
    bool claimed[2] = {};
    auto capture = [&](int i) {
        ++ready;
        while (ready.load() != 2) std::this_thread::yield();
        claimed[i] = slot.tryReserve();
        if (claimed[i]) slot.publish(&objects[i], [](void *p) { ++*static_cast<int *>(p); });
    };

    std::thread worker(capture, 1);
    capture(0);
    worker.join();

    XCTAssertNotEqual(claimed[0], claimed[1]);
    int winner = claimed[0] ? 0 : 1;
    XCTAssertTrue(slot.matches(&objects[winner]));
    XCTAssertFalse(slot.matches(&objects[1 - winner]));

    slot.release(&objects[winner]);
    XCTAssertEqual(objects[winner], 1);
    XCTAssertEqual(objects[1 - winner], 0);
}
@end
