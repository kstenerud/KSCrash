//
//  KSSidecarFormat_Tests.m
//
//  Created by Alexander Cohen on 2026-09-28.
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

#import "FileBasedTestCase.h"

#include <sys/stat.h>
#include <unistd.h>

#import "KSFileUtils.h"
#import "KSSidecarFormat.h"

// A three-version sidecar: each version appends one field.
typedef struct {
    KSSidecarHeader header;
    uint8_t flag;
    uint64_t value;

    // --- v2 ---
    uint64_t added;

    // --- v3 ---
    uint64_t addedLater;
} TestSidecar;

#define kTestMagic ((int32_t)'kstt')
#define kTestV1Size ((size_t)16)
#define kTestV2Size ((size_t)24)
#define kTestV3Size ((size_t)32)

KSSIDECAR_ASSERT_LAYOUT(TestSidecar, kTestV3Size);
KSSIDECAR_ASSERT_VERSION_START(TestSidecar, added, kTestV1Size);
KSSIDECAR_ASSERT_VERSION_START(TestSidecar, addedLater, kTestV2Size);

static const size_t kTestSizes[] = { kTestV1Size, kTestV2Size, kTestV3Size };
static const KSSidecarFormat kTestFormat = { kTestMagic, kTestSizes, 3 };

static TestSidecar makeSidecar(uint8_t version)
{
    TestSidecar sc = { 0 };
    sc.header = (KSSidecarHeader) { .magic = kTestMagic, .version = version };
    sc.flag = 1;
    sc.value = 42;
    sc.added = 7;
    sc.addedLater = 9;
    return sc;
}

/** A sidecar whose every byte is 0xAB, so a check that the reader zeroed it cannot pass by luck. */
static TestSidecar garbageSidecar(void)
{
    TestSidecar sc;
    memset(&sc, 0xAB, sizeof(sc));
    return sc;
}

extern void kssidecar_testcode_setBeforeReadHook(void (*hook)(const char *path));

static char g_truncateTarget[PATH_MAX];

static void truncateTargetBeforeRead(const char *path)
{
    if (g_truncateTarget[0] != '\0' && strncmp(path, g_truncateTarget, sizeof(g_truncateTarget)) == 0) {
        // Part of the file survives, so the read copies some bytes before it fails.
        truncate(path, (off_t)kTestV1Size);
    }
}

@interface KSSidecarFormat_Tests : FileBasedTestCase
@end

@implementation KSSidecarFormat_Tests

- (NSString *)writeSidecar:(TestSidecar)sc length:(size_t)length
{
    NSMutableData *data = [NSMutableData dataWithBytes:&sc length:MIN(length, sizeof(sc))];
    if (length > sizeof(sc)) {
        [data increaseLengthBy:length - sizeof(sc)];
    }
    return [self generateFileWithData:data];
}

- (KSCrashSidecarReadResult)read:(NSString *)path into:(TestSidecar *)out
{
    return kssidecar_read(&kTestFormat, path.fileSystemRepresentation, out, sizeof(*out));
}

- (void)assertZeroed:(const void *)bytes length:(size_t)length
{
    const uint8_t *p = bytes;
    for (size_t i = 0; i < length; i++) {
        if (p[i] != 0) {
            XCTFail(@"byte %zu is %u, not zero", i, p[i]);
            return;
        }
    }
}

- (void)assertZeroed:(const TestSidecar *)sc
{
    [self assertZeroed:sc length:sizeof(*sc)];
}

#pragma mark - Reads

- (void)testCurrentVersionReads
{
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:makeSidecar(3) length:kTestV3Size] into:&out], KSCrashSidecarReadOK);
    XCTAssertEqual(out.header.version, 3);
    XCTAssertEqual(out.value, 42u);
    XCTAssertEqual(out.added, 7u);
    XCTAssertEqual(out.addedLater, 9u);
}

- (void)testFileWrittenThroughMmapReads
{
    // ksfu_mmap sizes the file a byte past the struct, so a real sidecar is
    // longer than its version's size.
    NSString *path = [self generateTempFilePath];
    TestSidecar *mapped = (TestSidecar *)ksfu_mmap(path.fileSystemRepresentation, sizeof(TestSidecar));
    if (mapped == NULL) {
        XCTFail(@"ksfu_mmap failed");
        return;
    }
    *mapped = makeSidecar(3);
    ksfu_munmap(mapped, sizeof(TestSidecar));

    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:path into:&out], KSCrashSidecarReadOK);
    XCTAssertEqual(out.addedLater, 9u);
}

- (void)testOldestVersionReadsWithNewerFieldsZero
{
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:makeSidecar(1) length:kTestV1Size] into:&out], KSCrashSidecarReadOK);
    XCTAssertEqual(out.header.version, 1);
    XCTAssertEqual(out.flag, 1);
    XCTAssertEqual(out.value, 42u);
    XCTAssertEqual(out.added, 0u);
    XCTAssertEqual(out.addedLater, 0u);
}

- (void)testMiddleVersionReadsWithNewerFieldsZero
{
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:makeSidecar(2) length:kTestV2Size + 1] into:&out],
                   KSCrashSidecarReadOK);
    XCTAssertEqual(out.header.version, 2);
    XCTAssertEqual(out.added, 7u);
    XCTAssertEqual(out.addedLater, 0u);
}

- (void)testOlderVersionWithTrailingByteReads
{
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:makeSidecar(1) length:kTestV1Size + 1] into:&out],
                   KSCrashSidecarReadOK);
    XCTAssertEqual(out.added, 0u);
}

#pragma mark - Unrecoverable

- (void)testMissingFileIsUnrecoverable
{
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self generateTempFilePath] into:&out], KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

- (void)testEmptyFileIsUnrecoverable
{
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self generateFileWithData:[NSData data]] into:&out], KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

- (void)testFileShorterThanEveryVersionIsUnrecoverable
{
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:makeSidecar(1) length:kTestV1Size - 1] into:&out],
                   KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

- (void)testWrongMagicIsUnrecoverable
{
    TestSidecar sc = makeSidecar(3);
    sc.header.magic = (int32_t)0xDEADBEEF;
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:sc length:kTestV3Size] into:&out], KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

- (void)testVersionZeroIsUnrecoverable
{
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:makeSidecar(0) length:kTestV3Size] into:&out],
                   KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

- (void)testNewerVersionIsUnrecoverable
{
    // A newer build's file is at least as long as this build's current
    // version, but declares a version this build does not know.
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:makeSidecar(4) length:kTestV3Size + 8] into:&out],
                   KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

- (void)testNewerVersionTruncatedToOlderSizeIsUnrecoverable
{
    // A v3 file cut to v2's size: the fields its version promises are missing.
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:makeSidecar(3) length:kTestV2Size] into:&out],
                   KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

- (void)testMiddleVersionAtNewerSizeIsUnrecoverable
{
    // A v2 declaration only exists in a v2-sized file.
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:makeSidecar(2) length:kTestV3Size] into:&out],
                   KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

- (void)testOldestVersionAtNewerSizeIsUnrecoverable
{
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:[self writeSidecar:makeSidecar(1) length:kTestV2Size] into:&out],
                   KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

- (void)testOutputSizeThatDoesNotMatchTheFormatIsUnrecoverable
{
    NSString *path = [self writeSidecar:makeSidecar(3) length:kTestV3Size];
    uint8_t out[kTestV1Size];
    memset(out, 0xAB, sizeof(out));
    XCTAssertEqual(kssidecar_read(&kTestFormat, path.fileSystemRepresentation, out, sizeof(out)),
                   KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:out length:sizeof(out)];
}

- (void)testNullPathIsUnrecoverable
{
    TestSidecar out = garbageSidecar();
    XCTAssertEqual(kssidecar_read(&kTestFormat, NULL, &out, sizeof(out)), KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

#pragma mark - Failure

- (void)testAReadThatFallsShortAfterTheSizeCheckIsFailure
{
    // The file passes the size check as v3, then shrinks before the read: the
    // read fails, a later read can get past that, and the bytes it did copy are
    // not left in the output.
    NSString *path = [self writeSidecar:makeSidecar(3) length:kTestV3Size];
    strlcpy(g_truncateTarget, path.fileSystemRepresentation, sizeof(g_truncateTarget));
    kssidecar_testcode_setBeforeReadHook(truncateTargetBeforeRead);

    TestSidecar out = garbageSidecar();
    KSCrashSidecarReadResult result = [self read:path into:&out];
    kssidecar_testcode_setBeforeReadHook(NULL);
    g_truncateTarget[0] = '\0';

    XCTAssertEqual(result, KSCrashSidecarReadFailure);
    [self assertZeroed:&out];
}

- (void)testADirectoryAtThePathIsUnrecoverable
{
    // A directory opens read-only, but no read gets a sidecar out of it.
    NSString *path = [self generateTempFilePath];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:path
                                            withIntermediateDirectories:NO
                                                             attributes:nil
                                                                  error:nil]);
    TestSidecar out = garbageSidecar();
    XCTAssertEqual([self read:path into:&out], KSCrashSidecarReadUnrecoverable);
    [self assertZeroed:&out];
}

- (void)testAFifoAtThePathIsUnrecoverableWithoutBlocking
{
    // With no writer, a blocking open of a FIFO never returns. The read runs off the
    // test's thread so that a regression fails the test instead of hanging the suite.
    NSString *path = [self generateTempFilePath];
    XCTAssertEqual(mkfifo(path.fileSystemRepresentation, 0644), 0);
    __block KSCrashSidecarReadResult result = KSCrashSidecarReadOK;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        TestSidecar out = garbageSidecar();
        result = [self read:path into:&out];
        dispatch_semaphore_signal(done);
    });
    XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0,
                   @"the read blocked on the FIFO");
    XCTAssertEqual(result, KSCrashSidecarReadUnrecoverable);
}

- (void)testUnreadableFileIsFailure
{
    if (geteuid() == 0) {
        XCTSkip(@"Root reads a file with no permissions, so there is no failure to observe");
    }
    // Permission denied is the environment, not the bytes: a later read can succeed.
    NSString *path = [self writeSidecar:makeSidecar(3) length:kTestV3Size];
    XCTAssertEqual(chmod(path.fileSystemRepresentation, 0), 0);
    TestSidecar out = garbageSidecar();
    KSCrashSidecarReadResult result = [self read:path into:&out];
    chmod(path.fileSystemRepresentation, 0644);
    XCTAssertEqual(result, KSCrashSidecarReadFailure);
    [self assertZeroed:&out];
}

@end
