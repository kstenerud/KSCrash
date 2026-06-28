//
//  KSCrashRunID_Tests.m
//
//  Created by Alexander Cohen on 2026-06-27.
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
#import <mach-o/dyld.h>
#import <mach/mach.h>

#import "KSCrashC.h"
#import "KSCrashMonitorType.h"

@interface KSCrashRunID_Tests : XCTestCase
@end

@implementation KSCrashRunID_Tests

// The real round trip for kscrash_loadRunIDFromCorpse: install (no monitors, so no crash handlers
// are wired; a temp dir keeps it isolated) only to populate this process's run id, then point the
// loader at our own task and images. It must locate the real __ks_runid section, read the run id,
// and load it back, the exact operation the crash extension performs against a corpse.
- (void)testLoadRunIDFromCorpseRoundTrip
{
    // No install: the __ks_runid section exists statically and the seam fills it, which is all
    // the loader reads. Installing here would take the one-per-process install from the Swift
    // install suites sharing this test process.
    kscrash_testcode_setRunID("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee");

    // When every test target shares one process (older SwiftPM aggregates them), the corpse
    // tests win the one-per-process install in extension-reporting mode, which generates no run
    // id by design (and their captures clear it). The loader is exercised against a real corpse
    // section by those same tests, so skipping here loses nothing.
    const char *runID = kscrash_getRunID();
    XCTSkipIf(runID == NULL || strlen(runID) != 36,
              @"another suite installed in extension-reporting mode; no run id to round-trip");
    XCTAssertTrue(runID != NULL && strlen(runID) == 36, @"Run id should be populated after install");
    char expected[64] = { 0 };
    strlcpy(expected, runID, sizeof(expected));

    // Stand in for the corpse's image list with our own loaded images; the loader scans them for the
    // __ks_runid section just as it would scan a corpse's binary images.
    uint32_t imageCount = _dyld_image_count();
    uint64_t *imageAddrs = malloc(imageCount * sizeof(uint64_t));
    for (uint32_t i = 0; i < imageCount; i++) {
        imageAddrs[i] = (uint64_t)(uintptr_t)_dyld_get_image_header(i);
    }

    bool loaded = kscrash_loadRunIDFromCorpse(mach_task_self(), imageAddrs, imageCount);
    free(imageAddrs);

    XCTAssertTrue(loaded, @"Loader should locate __ks_runid and read the run id");
    XCTAssertEqual(0, strcmp(kscrash_getRunID(), expected), @"Loaded run id should match the installed one");
}

- (void)testLoadRunIDFromCorpseRejectsInvalidArguments
{
    uint64_t addr = 0;
    XCTAssertFalse(kscrash_loadRunIDFromCorpse(MACH_PORT_NULL, &addr, 1));
    XCTAssertFalse(kscrash_loadRunIDFromCorpse(mach_task_self(), NULL, 1));
    XCTAssertFalse(kscrash_loadRunIDFromCorpse(mach_task_self(), &addr, 0));
}

extern void kscrash_testcode_setRunID(const char *runID);

// Load-or-clear: a capture clears the run id before loading the next corpse's, so a corpse
// whose id cannot be read is reported with no run id, never a previous corpse's. Clearing
// wipes this process's own __ks_runid section (the global IS the section storage) and install
// cannot repopulate it (it is single-shot), so this test saves the id and puts it back. Every
// later test in the process reads the same global (an empty one silently changes which reports
// sendAllReports considers current-run), and XCTest ordering is not a guarantee to lean on.
- (void)testClearRunIDThenFailedLoadLeavesItEmpty
{
    // Same install dance as the round-trip test, so the id is populated beforehand whenever
    // this class runs first in the process.
    // No install: the __ks_runid section exists statically and the seam fills it, which is all
    // the loader reads. Installing here would take the one-per-process install from the Swift
    // install suites sharing this test process.
    kscrash_testcode_setRunID("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee");

    NSString *saved = @(kscrash_getRunID());
    @try {
        kscrash_clearRunID();
        XCTAssertEqual(strlen(kscrash_getRunID()), (size_t)0, @"Clearing must empty the run id");

        // A failed load (no __ks_runid at this address) must leave the id empty, not resurrect
        // or invent one.
        uint64_t bogus = 0x1000;
        XCTAssertFalse(kscrash_loadRunIDFromCorpse(mach_task_self(), &bogus, 1));
        XCTAssertEqual(strlen(kscrash_getRunID()), (size_t)0);
    } @finally {
        kscrash_testcode_setRunID(saved.length > 0 ? saved.UTF8String : NULL);
    }
    XCTAssertEqualObjects(@(kscrash_getRunID()), saved, @"The run id must be restored for later tests");
}

@end
