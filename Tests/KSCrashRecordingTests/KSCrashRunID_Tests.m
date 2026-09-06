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
#import <mach-o/loader.h>
#import <mach/mach.h>

#import "KSCrashC.h"
#import "KSCrashCConfiguration.h"
#import "KSCrashMonitorType.h"

extern void kscrash_testcode_setRunID(const char *runID);

@interface KSCrashRunID_Tests : XCTestCase
@end

@implementation KSCrashRunID_Tests {
    // The run id is process state that every later report in the process is
    // written with and stitched by. These tests seed a known one; the one
    // the install generated goes back afterwards, or reports written by later
    // suites look for their run sidecars under the seeded id and find none.
    NSString *_originalRunID;
}

- (void)setUp
{
    [super setUp];
    const char *runID = kscrash_getRunID();
    _originalRunID = runID != NULL ? @(runID) : nil;
}

- (void)tearDown
{
    kscrash_testcode_setRunID(_originalRunID.length > 0 ? _originalRunID.UTF8String : NULL);
    [super tearDown];
}

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

    const char *runID = kscrash_getRunID();
    XCTAssertTrue(runID != NULL && strlen(runID) == 36, @"Run id should be populated by the seed");
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

// Two namespaced copies of KSCrash linked into one image each emit a __ks_runid payload, and
// the linker lays them out back to back in one section. The loader must find this namespace's
// copy wherever it sits, not just first. Modelled with a synthetic image whose section points
// at two payloads, a foreign namespace's first.
- (void)testLoadRunIDFromCorpseFindsThisNamespaceBehindAnotherCopy
{
    typedef struct {
        char namespaceID[64];
        char runID[37];
    } Payload;
    static Payload payloads[2];
    memset(payloads, 0, sizeof(payloads));
    strlcpy(payloads[0].namespaceID, "KSCrashSomeoneElses", sizeof(payloads[0].namespaceID));
    strlcpy(payloads[0].runID, "11111111-2222-4333-8444-555555555555", sizeof(payloads[0].runID));
    strlcpy(payloads[1].namespaceID, kscrash_namespaceIdentifier(), sizeof(payloads[1].namespaceID));
    strlcpy(payloads[1].runID, "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", sizeof(payloads[1].runID));

    static struct {
        struct mach_header_64 header;
        struct segment_command_64 text;
        struct segment_command_64 data;
        struct section_64 runIDSection;
    } image;
    memset(&image, 0, sizeof(image));
    image.header.magic = MH_MAGIC_64;
    image.header.ncmds = 2;
    image.header.sizeofcmds = (uint32_t)(sizeof(image) - sizeof(struct mach_header_64));
    image.text.cmd = LC_SEGMENT_64;
    image.text.cmdsize = sizeof(struct segment_command_64);
    strlcpy(image.text.segname, "__TEXT", sizeof(image.text.segname));
    // vmaddr equal to the load address makes the slide zero, so section
    // addresses are the real ones.
    image.text.vmaddr = (uint64_t)(uintptr_t)&image;
    image.text.vmsize = sizeof(image);
    image.text.filesize = sizeof(image);
    image.data.cmd = LC_SEGMENT_64;
    image.data.cmdsize = sizeof(struct segment_command_64) + sizeof(struct section_64);
    strlcpy(image.data.segname, "__DATA", sizeof(image.data.segname));
    image.data.vmaddr = (uint64_t)(uintptr_t)payloads;
    image.data.vmsize = sizeof(payloads);
    image.data.filesize = sizeof(payloads);
    image.data.nsects = 1;
    strlcpy(image.runIDSection.sectname, "__ks_runid", sizeof(image.runIDSection.sectname));
    strlcpy(image.runIDSection.segname, "__DATA", sizeof(image.runIDSection.segname));
    image.runIDSection.addr = (uint64_t)(uintptr_t)payloads;
    image.runIDSection.size = sizeof(payloads);

    kscrash_clearRunID();
    uint64_t loadAddress = (uint64_t)(uintptr_t)&image;
    XCTAssertTrue(kscrash_loadRunIDFromCorpse(mach_task_self(), &loadAddress, 1));
    XCTAssertEqualObjects(@(kscrash_getRunID()), @"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee");

    // With only the foreign copy present nothing is loaded, and nothing is invented.
    image.runIDSection.size = sizeof(payloads[0]);
    image.data.vmsize = sizeof(payloads[0]);
    image.data.filesize = sizeof(payloads[0]);
    kscrash_clearRunID();
    XCTAssertFalse(kscrash_loadRunIDFromCorpse(mach_task_self(), &loadAddress, 1));
    XCTAssertEqual(strlen(kscrash_getRunID()), (size_t)0);
}

- (void)testLoadRunIDFromCorpseRejectsInvalidArguments
{
    uint64_t addr = 0;
    XCTAssertFalse(kscrash_loadRunIDFromCorpse(MACH_PORT_NULL, &addr, 1));
    XCTAssertFalse(kscrash_loadRunIDFromCorpse(mach_task_self(), NULL, 1));
    XCTAssertFalse(kscrash_loadRunIDFromCorpse(mach_task_self(), &addr, 0));
}

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
