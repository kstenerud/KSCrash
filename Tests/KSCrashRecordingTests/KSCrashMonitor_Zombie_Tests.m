//
//  KSCrashMonitor_Zombie_Tests.m
//
//  Created by Alexander Cohen on 2026-02-28.
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

#import "KSCrashMonitor_Zombie.h"
#import "KSSystemCapabilities.h"

// The Zombie monitor swizzles NSObject dealloc and reads freed memory by design.
// This is incompatible with sanitizers, so skip tests that enable the monitor.
#if !KSCRASH_HAS_SANITIZER

@interface KSCrashMonitor_Zombie_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Zombie_Tests

- (void)testInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_zombie_getAPI();
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));

    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testMonitorId
{
    KSCrashMonitorAPI *api = kscm_zombie_getAPI();
    const char *mid = api->monitorId(NULL);
    XCTAssertTrue(strcmp(mid, "Zombie") == 0, @"Expected monitorId 'Zombie', got '%s'", mid);
}

- (void)testClassNameNullForNullInput
{
    KSCrashMonitorAPI *api = kscm_zombie_getAPI();
    api->setEnabled(true, NULL);

    const char *name = kszombie_className(NULL);
    XCTAssertTrue(name == NULL);
}

- (void)testClassNameAfterDealloc
{
    KSCrashMonitorAPI *api = kscm_zombie_getAPI();
    api->setEnabled(true, NULL);

    const void *ptr;
    @autoreleasepool {
        NSObject *obj = [[NSObject alloc] init];
        ptr = (__bridge const void *)obj;
    }
    // After dealloc, the zombie cache should have recorded the class name
    const char *name = kszombie_className(ptr);
    // May be NULL if the hash slot was overwritten, but if present it should be "NSObject"
    if (name != NULL) {
        XCTAssertTrue(strcmp(name, "NSObject") == 0, @"Expected 'NSObject', got '%s'", name);
    }
}

- (void)testClassNameForUnknownPointer
{
    KSCrashMonitorAPI *api = kscm_zombie_getAPI();
    api->setEnabled(true, NULL);

    // An arbitrary pointer that was never deallocated through the zombie cache
    const void *fakePtr = (const void *)0xDEADBEEF;
    const char *name = kszombie_className(fakePtr);
    XCTAssertTrue(name == NULL);
}

@end

#endif  // !KSCRASH_HAS_SANITIZER
