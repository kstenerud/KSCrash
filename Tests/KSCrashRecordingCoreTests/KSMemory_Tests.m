//
//  ksmemory_Tests.m
//
//  Created by Karl Stenerud on 2012-03-03.
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
#import <sys/mman.h>
#import <unistd.h>

#import "KSMemory.h"
#import "TestThread.h"

@interface KSMemory_Tests : XCTestCase
@end

@implementation KSMemory_Tests

- (void)testCopyMem
{
    char buff[100];
    char buff2[100] = { 1, 2, 3, 4, 5 };

    bool result = ksmem_copySafely(buff2, buff, sizeof(buff));
    XCTAssertTrue(result, @"");
    int memCmpResult = memcmp(buff, buff2, sizeof(buff));
    XCTAssertEqual(memCmpResult, 0, @"");
}

- (void)testCopyMemNull
{
    char buff[100];
    char *buff2 = NULL;

    bool result = ksmem_copySafely(buff2, buff, sizeof(buff));
    XCTAssertFalse(result, @"");
}

- (void)testCopyMemBad
{
    char buff[100];
    char *buff2 = (char *)-1;

    bool result = ksmem_copySafely(buff2, buff, sizeof(buff));
    XCTAssertFalse(result, @"");
}

- (void)testCopyMaxPossibleMem
{
    char buff[1000];
    char buff2[5] = { 1, 2, 3, 4, 5 };

    int copied = ksmem_copyMaxPossible(buff2, buff, sizeof(buff));
    XCTAssertTrue(copied >= 5, @"");
    int memCmpResult = memcmp(buff, buff2, sizeof(buff2));
    XCTAssertEqual(memCmpResult, 0, @"");
}

- (void)testCopyMaxPossibleMemNull
{
    char buff[1000];
    char *buff2 = NULL;

    int copied = ksmem_copyMaxPossible(buff2, buff, sizeof(buff));
    XCTAssertTrue(copied == 0, @"");
}

- (void)testCopyMaxPossibleMemBad
{
    char buff[1000];
    char *buff2 = (char *)-1;

    int copied = ksmem_copyMaxPossible(buff2, buff, sizeof(buff));
    XCTAssertTrue(copied == 0, @"");
}

- (void)testCopyMaxPossibleMemOverflow
{
    char buff[1000];
    char *src = (char *)(UINTPTR_MAX - 100);

    int copied = ksmem_copyMaxPossible(src, buff, 1000);
    XCTAssertTrue(copied == 0, @"");
}

- (void)testMaxReadableBytesNeverExceedsTheRequest
{
    char buff[256] = { 0 };
    XCTAssertEqual(ksmem_maxReadableBytes(buff, (int)sizeof(buff)), (int)sizeof(buff));
}

- (void)testMaxReadableBytesStopsAtAnUnreadablePage
{
    // Far more than the probe's 10 KB scratch buffer, so the chunked walk stops early with
    // more left to answer for than that buffer holds.
    const size_t pageSize = (size_t)getpagesize();
    uint8_t *pages = mmap(NULL, 4 * pageSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    XCTAssertNotEqual(pages, MAP_FAILED);
    XCTAssertEqual(mprotect(pages + pageSize, pageSize, PROT_NONE), 0);

    XCTAssertEqual(ksmem_maxReadableBytes(pages, (int)(4 * pageSize)), (int)pageSize);

    munmap(pages, 4 * pageSize);
}

- (void)testIsMemoryReadableChecksPastFirstChunk
{
    // Readable pages followed by an unreadable one, with the request reaching into it. The probe
    // copies in chunks of its scratch buffer's size, so this needs more than one chunk before the
    // unreadable page for a probe that re-reads its first chunk to answer true.
    const size_t pageSize = (size_t)getpagesize();
    const size_t readableSize = pageSize * ((32 * 1024 + pageSize - 1) / pageSize);
    const size_t totalSize = readableSize + pageSize;
    uint8_t *region = mmap(NULL, totalSize, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    XCTAssertNotEqual(region, MAP_FAILED);
    if (region == MAP_FAILED) {
        return;
    }
    XCTAssertEqual(mprotect(region + readableSize, pageSize, PROT_NONE), 0);

    XCTAssertTrue(ksmem_isMemoryReadable(region, (int)readableSize));
    XCTAssertFalse(ksmem_isMemoryReadable(region, (int)totalSize));
    XCTAssertFalse(ksmem_isMemoryReadable(region, (int)readableSize + 1));

    munmap(region, totalSize);
}

@end
