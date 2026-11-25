//
//  KSCrashMonitor_CPPException_ThrowRecord_Tests.mm
//
//  Created by Mischan Toosarani-Hausberger on 2026-11-19.
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

// clang-format off
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreserved-macro-identifier"
#import <XCTest/XCTest.h>
#pragma clang diagnostic pop
// clang-format on

#import "KSCrashMonitor_CPPException+ThrowRecord.h"

#include <atomic>
#include <thread>

@interface KSCrashMonitor_CPPException_ThrowRecord_Tests : XCTestCase
@end

@implementation KSCrashMonitor_CPPException_ThrowRecord_Tests

- (void)testCollisionsProbePastLiveRecordsAndHoles
{
    // Addresses differing only in the low four bits have the same home slot.
    alignas(16) char objects[5] = {};
    KSStackCursor *slots[4] = {};

    for (int i = 0; i < 4; i++) {
        slots[i] = kstr_reserve(&objects[i]);
        XCTAssertNotEqual(slots[i], nullptr);

        if (!slots[i]) return;

        XCTAssertEqual(kstr_find(&objects[i]), nullptr);
        kstr_publish(slots[i], &objects[i], [](void *p) { ++*static_cast<char *>(p); });
    }

    XCTAssertEqual(kstr_reserve(&objects[4]), nullptr);

    for (int i = 0; i < 4; i++) {
        XCTAssertEqual(kstr_find(&objects[i]), slots[i]);
        kstr_release(&objects[i]);

        XCTAssertEqual(objects[i], 1);
        XCTAssertEqual(kstr_find(&objects[i]), nullptr);
    }
}

- (void)testAddressCanBeReusedAfterNullDestructor
{
    int object = 0;
    auto *slot = kstr_reserve(&object);
    XCTAssertNotEqual(slot, nullptr);
    if (!slot) return;

    kstr_publish(slot, &object, nullptr);
    kstr_release(&object);
    XCTAssertEqual(kstr_find(&object), nullptr);

    slot = kstr_reserve(&object);
    XCTAssertNotEqual(slot, nullptr);
    if (!slot) return;

    kstr_publish(slot, &object, [](void *p) { ++*static_cast<int *>(p); });
    kstr_release(&object);
    XCTAssertEqual(object, 1);
}

- (void)testConcurrentCollisionsClaimDistinctSlots
{
    alignas(16) char objects[2] = {};
    KSStackCursor *slots[2] = {};
    std::atomic<int> ready { 0 };
    auto capture = [&](int i) {
        ++ready;
        while (ready.load() != 2) std::this_thread::yield();
        slots[i] = kstr_reserve(&objects[i]);
        if (slots[i]) kstr_publish(slots[i], &objects[i], nullptr);
    };
    std::thread worker(capture, 1);
    capture(0);
    worker.join();

    XCTAssertNotEqual(slots[0], slots[1]);
    for (int i = 0; i < 2; i++) {
        XCTAssertNotEqual(slots[i], nullptr);
        XCTAssertEqual(kstr_find(&objects[i]), slots[i]);
        if (slots[i]) kstr_release(&objects[i]);
    }
}
@end
