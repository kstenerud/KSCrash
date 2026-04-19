//
//  KSLogger_Tests.m
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
#import "KSTestCaseUtils.h"

#import "KSLogger.h"

@interface KSLogger_Tests : XCTestCase

@property(nonatomic, readwrite, copy) NSString *tempDir;

@end

@implementation KSLogger_Tests

- (void)setUp
{
    [super setUp];
    self.tempDir = [KSTestCaseUtils createTempPath];
}

- (void)tearDown
{
    [KSTestCaseUtils removePath:self.tempDir];
}

- (void)testLogError
{
    KSLOG_ERROR(@"TEST");
}

- (void)testLogErrorNull
{
    NSString *str = nil;
    KSLOG_ERROR(str);
}

- (void)testLogAlways
{
    KSLOG_ALWAYS(@"TEST");
}

- (void)testLogAlwaysNull
{
    NSString *str = nil;
    KSLOG_ALWAYS(str);
}

- (void)testLogBasicError
{
    KSLOGBASIC_ERROR(@"TEST");
}

- (void)testLogBasicErrorNull
{
    NSString *str = nil;
    KSLOGBASIC_ERROR(str);
}

- (void)testLogBasicAlways
{
    KSLOGBASIC_ALWAYS(@"TEST");
}

- (void)testLogBasicAlwaysNull
{
    NSString *str = nil;
    KSLOGBASIC_ALWAYS(str);
}

- (void)testSetLogFilename
{
    NSString *expected = @"TEST";
    NSString *logFileName = [self.tempDir stringByAppendingPathComponent:@"log.txt"];
    kslog_setLogFilename([logFileName UTF8String], true);
    KSLOGBASIC_ALWAYS(expected);
    kslog_setLogFilename(nil, true);

    NSError *error = nil;
    NSString *result = [NSString stringWithContentsOfFile:logFileName encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error, @"");
    result = [[result componentsSeparatedByString:@"\x0a"] objectAtIndex:0];
    XCTAssertEqualObjects(result, expected, @"");

    KSLOGBASIC_ALWAYS(@"blah blah");
    result = [NSString stringWithContentsOfFile:logFileName encoding:NSUTF8StringEncoding error:&error];
    result = [[result componentsSeparatedByString:@"\x0a"] objectAtIndex:0];
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, expected, @"");
}

#pragma mark - C formatter (signal-safe path)

extern void i_kslog_logCBasic(const char *fmt, ...);

- (NSString *)captureLogOutput:(void (^)(void))block
{
    // Each test gets a unique file to avoid cross-test interference.
    NSString *logFile = [self.tempDir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    kslog_setLogFilename([logFile UTF8String], true);
    block();
    // write() is unbuffered — data is in the file immediately. Read it back.
    NSString *content = [NSString stringWithContentsOfFile:logFile encoding:NSUTF8StringEncoding error:nil];
    if ([content hasSuffix:@"\n"]) {
        content = [content substringToIndex:content.length - 1];
    }
    return content;
}

- (void)testCFormatterString
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("hello %s", "world");
    }];
    XCTAssertEqualObjects(result, @"hello world");
}

- (void)testCFormatterNullString
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("val=%s", (const char *)NULL);
    }];
    XCTAssertEqualObjects(result, @"val=(null)");
}

- (void)testCFormatterInt
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("n=%d", -42);
    }];
    XCTAssertEqualObjects(result, @"n=-42");
}

- (void)testCFormatterUnsigned
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("n=%u", 12345u);
    }];
    XCTAssertEqualObjects(result, @"n=12345");
}

- (void)testCFormatterHex
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("h=%x", 0xabcdu);
    }];
    XCTAssertEqualObjects(result, @"h=abcd");
}

- (void)testCFormatterZeroPaddedHex
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("h=%08x", 0x1au);
    }];
    XCTAssertEqualObjects(result, @"h=0000001a");
}

- (void)testCFormatterPointer
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("p=%p", (void *)0x1234);
    }];
    XCTAssertEqualObjects(result, @"p=0x1234");
}

- (void)testCFormatterChar
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("c=%c", 'A');
    }];
    XCTAssertEqualObjects(result, @"c=A");
}

- (void)testCFormatterLongLong
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("n=%lld", (long long)INT64_MAX);
    }];
    XCTAssertEqualObjects(result, @"n=9223372036854775807");
}

- (void)testCFormatterSizeT
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("s=%zu", (size_t)65536);
    }];
    XCTAssertEqualObjects(result, @"s=65536");
}

- (void)testCFormatterPercent
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("100%%");
    }];
    XCTAssertEqualObjects(result, @"100%");
}

- (void)testCFormatterMultipleArgs
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("thread_suspend (%08x): %s", 0x1234u, "error");
    }];
    XCTAssertEqualObjects(result, @"thread_suspend (00001234): error");
}

- (void)testCFormatterNullFmt
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic(NULL);
    }];
    XCTAssertEqualObjects(result, @"(null)");
}

- (void)testCFormatterSignedSizeT
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("n=%zd", (ssize_t)-42);
    }];
    XCTAssertEqualObjects(result, @"n=-42");
}

- (void)testCFormatterTrailingPercent
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("end%");
    }];
    XCTAssertEqualObjects(result, @"end%");
}

- (void)testCFormatterFloat
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("v=%.3f", 3.14159);
    }];
    NSString *numPart = [result substringFromIndex:2];
    double parsed = [numPart doubleValue];
    XCTAssertEqualWithAccuracy(parsed, 3.14159, 0.001);
}

- (void)testCFormatterFloatThenString
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("d=%.3f %s", 1.5, "ok");
    }];
    XCTAssertTrue([result hasSuffix:@" ok"], @"Expected trailing ' ok', got: %@", result);
}

- (void)testCFormatterWidthWithoutZeroPad
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("h=%02x", 0xau);
    }];
    XCTAssertEqualObjects(result, @"h=0a");
}

- (void)testCFormatterZeroPadNegativeInt
{
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("%06d", -123);
    }];
    XCTAssertEqualObjects(result, @"-00123");
}

// Bugs found by audit: default case in the formatter should not consume a
// va_arg for unknown specifiers/flags/length modifiers. Doing so silently
// desynchronizes the remaining varargs.

- (void)testCFormatterUnknownSpecifierDoesNotConsumeArg
{
    // %Y is unknown. Should be emitted literally; the int arg should be
    // consumed by the following %d.
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("a=%Y b=%d", 42);
    }];
    XCTAssertEqualObjects(result, @"a=%Y b=42");
}

- (void)testCFormatterShortModifier
{
    // %hd: 'h' length modifier. Should not swallow the int arg via a spurious
    // va_arg(void*) in the default case.
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("%hd", (short)-5);
    }];
    XCTAssertEqualObjects(result, @"-5");
}

- (void)testCFormatterDashFlag
{
    // %-5d: '-' flag. Should not swallow the int arg in the default case.
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("x=%-5d|", 42);
    }];
    // Left-justified padding is optional; what matters is that 42 is formatted,
    // not the literal '?' from an unknown-specifier path.
    XCTAssertTrue([result containsString:@"42"], @"Expected '42' in output, got: %@", result);
    XCTAssertFalse([result containsString:@"?"], @"Unexpected '?' in output: %@", result);
}

- (void)testCFormatterTrailingPercentZero
{
    // "%0" with *fmt='\0' after the '0' should not walk past the null terminator.
    // Acceptable outputs: "" or "%0". Not acceptable: crash / UB.
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("%0");
    }];
    // Just verify it doesn't crash and doesn't emit arbitrary memory.
    XCTAssertNotNil(result);
    XCTAssertLessThan(result.length, 10u, @"Output too long, likely walked past fmt: %@", result);
}

#pragma mark - snprintf parity for integer/string specifiers

- (void)testCFormatterMatchesSnprintfForIntegers
{
    // Compare our logger's output against snprintf for common integer patterns.
    // Each case formats the same value through both and asserts equality.
    char ref[64];

    // %d
    NSString *out1 = [self captureLogOutput:^{
        i_kslog_logCBasic("%d", -12345);
    }];
    snprintf(ref, sizeof(ref), "%d", -12345);
    XCTAssertEqualObjects(out1, @(ref), @"%%d mismatch");

    // %u
    NSString *out2 = [self captureLogOutput:^{
        i_kslog_logCBasic("%u", 99999u);
    }];
    snprintf(ref, sizeof(ref), "%u", 99999u);
    XCTAssertEqualObjects(out2, @(ref), @"%%u mismatch");

    // %lld
    NSString *out3 = [self captureLogOutput:^{
        i_kslog_logCBasic("%lld", (long long)INT64_MIN);
    }];
    snprintf(ref, sizeof(ref), "%lld", (long long)INT64_MIN);
    XCTAssertEqualObjects(out3, @(ref), @"%%lld mismatch");

    // %llu
    NSString *out4 = [self captureLogOutput:^{
        i_kslog_logCBasic("%llu", (unsigned long long)UINT64_MAX);
    }];
    snprintf(ref, sizeof(ref), "%llu", (unsigned long long)UINT64_MAX);
    XCTAssertEqualObjects(out4, @(ref), @"%%llu mismatch");

    // %x with value
    NSString *out5 = [self captureLogOutput:^{
        i_kslog_logCBasic("%x", 0xdeadbeefu);
    }];
    snprintf(ref, sizeof(ref), "%x", 0xdeadbeefu);
    XCTAssertEqualObjects(out5, @(ref), @"%%x mismatch");

    // %08x zero-padded
    NSString *out6 = [self captureLogOutput:^{
        i_kslog_logCBasic("%08x", 0xabu);
    }];
    snprintf(ref, sizeof(ref), "%08x", 0xabu);
    XCTAssertEqualObjects(out6, @(ref), @"%%08x mismatch");

    // %06d with negative (zero-padding + sign)
    NSString *out7 = [self captureLogOutput:^{
        i_kslog_logCBasic("%06d", -42);
    }];
    snprintf(ref, sizeof(ref), "%06d", -42);
    XCTAssertEqualObjects(out7, @(ref), @"%%06d negative mismatch");

    // %zd with ssize_t
    NSString *out8 = [self captureLogOutput:^{
        i_kslog_logCBasic("%zd", (ssize_t)-1);
    }];
    snprintf(ref, sizeof(ref), "%zd", (ssize_t)-1);
    XCTAssertEqualObjects(out8, @(ref), @"%%zd mismatch");
}

- (void)testCFormatterMatchesSnprintfForStringAndChar
{
    char ref[64];

    NSString *out1 = [self captureLogOutput:^{
        i_kslog_logCBasic("%s", "hello world");
    }];
    snprintf(ref, sizeof(ref), "%s", "hello world");
    XCTAssertEqualObjects(out1, @(ref), @"%%s mismatch");

    NSString *out2 = [self captureLogOutput:^{
        i_kslog_logCBasic("%c", 'Z');
    }];
    snprintf(ref, sizeof(ref), "%c", 'Z');
    XCTAssertEqualObjects(out2, @(ref), @"%%c mismatch");
}

- (void)testCFormatterLongModifiersUse64BitWidth
{
    // %ld with a value that exceeds 32-bit range. Catches regressions where
    // longCount==1 falls back to `int`.
    long bigNeg = -(((long)1) << 40) + 7;
    unsigned long bigHex = 0x123456789abcUL;
    char ref[64];

    NSString *out1 = [self captureLogOutput:^{
        i_kslog_logCBasic("off=%ld", bigNeg);
    }];
    snprintf(ref, sizeof(ref), "off=%ld", bigNeg);
    XCTAssertEqualObjects(out1, @(ref), @"%%ld 64-bit mismatch");

    NSString *out2 = [self captureLogOutput:^{
        i_kslog_logCBasic("pc=0x%lx", bigHex);
    }];
    snprintf(ref, sizeof(ref), "pc=0x%lx", bigHex);
    XCTAssertEqualObjects(out2, @(ref), @"%%lx 64-bit mismatch");
}

- (void)testCFormatterSizeTUses64BitWidth
{
    // %zu with a size_t exceeding 32 bits. Catches any regression where 'z'
    // is consumed as a length modifier but the va_arg reads a 32-bit value.
    size_t n = (((size_t)1) << 40) + 3;
    char ref[64];
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("sz=%zu", n);
    }];
    snprintf(ref, sizeof(ref), "sz=%zu", n);
    XCTAssertEqualObjects(result, @(ref), @"%%zu 64-bit mismatch");
}

- (void)testCFormatterTruncatesLongStringCleanly
{
    // Logger buffer is 1024 bytes. Feeding a longer string should truncate
    // cleanly without overrun. We just verify the output fits in the buffer
    // and the start matches the input.
    const size_t longLen = 1100;
    char *longStr = malloc(longLen + 1);
    XCTAssertTrue(longStr != NULL);
    memset(longStr, 'A', longLen);
    longStr[longLen] = '\0';

    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("%s", longStr);
    }];
    // Buffer cap is KSLOGGER_CBufferSize - 1 (one byte reserved for NUL).
    XCTAssertLessThanOrEqual(result.length, 1023u, @"Output exceeded buffer: %zu", (size_t)result.length);
    XCTAssertTrue([result hasPrefix:@"AAAA"], @"Output should start with the input prefix");
    free(longStr);
}

#pragma mark - Call-site format-string parity
//
// These tests enumerate every distinct format string currently used by
// KSLOG_*/KSLOGBASIC_* call sites in the project's C sources and run each one
// through both our signal-safe formatter (i_kslog_logCBasic) and snprintf,
// asserting byte-equal output. If someone introduces a new specifier the
// formatter doesn't handle, or changes formatter behavior, these tests will
// catch the divergence at compile-time-grep-able call sites rather than in
// production.
//
// The exhaustive list below was produced by grepping the codebase for KSLOG
// format strings. `PRIx64`/`PRId64` are hard-coded as "llx"/"lld" so the test
// compiles the same string the macro produces on 64-bit targets.
//
// Known deviation: the formatter ignores precision (e.g. %.3f), so the one
// call site using %.3f (KSCrashMonitor_Watchdog.c, hang duration) does NOT
// match snprintf. That case is covered separately by
// testCallSiteBehavior_FloatPrecisionIgnored below.

#define KSLOG_PARITY(FMT, ...)                                                                   \
    do {                                                                                         \
        char _ref[1200];                                                                         \
        int _n = snprintf(_ref, sizeof(_ref), FMT, ##__VA_ARGS__);                               \
        XCTAssertGreaterThan(_n, 0, @"snprintf returned error for fmt: %s", FMT);                \
        XCTAssertLessThan(_n, (int)sizeof(_ref), @"test ref buffer too small for fmt: %s", FMT); \
        NSString *_ours = [self captureLogOutput:^{                                              \
            i_kslog_logCBasic(FMT, ##__VA_ARGS__);                                               \
        }];                                                                                      \
        XCTAssertEqualObjects(_ours, @(_ref), @"parity mismatch for fmt: %s", FMT);              \
    } while (0)

- (void)testCallSiteParity_SingleStringSpecifier
{
    KSLOG_PARITY("Crash monitor type %s shouldn't be able to cause events!", "Signal");
    KSLOG_PARITY("Dispatch queue name: %s", "com.apple.main-thread");
    KSLOG_PARITY("Could not read: %s", "Permission denied");
    KSLOG_PARITY("Could not munmap: %s", "Invalid argument");
    KSLOG_PARITY("Could not create path: %s", "No such file or directory");
    KSLOG_PARITY("Failed to grow KVS file: %s", "No space left on device");
    KSLOG_PARITY("Failed to mmap KVS file: %s", "Invalid argument");
    KSLOG_PARITY("Failed to remap KVS file: %s", "Invalid argument");
    KSLOG_PARITY("Failed to size KVS file: %s", "No space left on device");
    KSLOG_PARITY("Failed to read last_run_id: %s", "I/O error");
    KSLOG_PARITY("Failed to create watchdog thread: %s", "Resource temporarily unavailable");
    KSLOG_PARITY("pthread_create: %s", "Resource temporarily unavailable");
    KSLOG_PARITY("signalstack: %s", "Invalid argument");
    KSLOG_PARITY("sysctl: %s", "Operation not permitted");
    KSLOG_PARITY("task_threads: %s", "No such process");
    KSLOG_PARITY("thread_get_state: %s", "Invalid argument");
    KSLOG_PARITY("Failed to get protection for section: %s", "Bad address");
    KSLOG_PARITY("Could not delete %s: Not a regular file.", "/tmp/x");
    KSLOG_PARITY("Failed to mmap sidecar at %s", "/tmp/sidecar");
    KSLOG_PARITY("Found backtrace: %s", "trace");
    KSLOG_PARITY("Found first message: %s", "message");
    KSLOG_PARITY("Found second message: %s", "message2");
    KSLOG_PARITY("Found signature: %s", "sig");
    KSLOG_PARITY("Found crash info section in binary: %s", "MyApp");
    KSLOG_PARITY("Processing segment %s", "__TEXT");
    KSLOG_PARITY("Queue label = %s", "com.example.q");
    KSLOG_PARITY("Monitor %s injected.", "Signal");
    KSLOG_PARITY("Contents of %s have been mutated", "/tmp/bin");
}

- (void)testCallSiteParity_TwoStringSpecifiers
{
    KSLOG_PARITY("Could not open %s: %s", "/tmp/f", "No such file");
    KSLOG_PARITY("Could not open crash report file %s: %s", "/tmp/crash", "Permission denied");
    KSLOG_PARITY("Could not open file %s: %s", "/tmp/f", "No such file");
    KSLOG_PARITY("Could not mmap file %s: %s", "/tmp/f", "Bad file descriptor");
    KSLOG_PARITY("Could not create directory %s: %s", "/tmp/dir", "File exists");
    KSLOG_PARITY("Could not delete %s: %s", "/tmp/f", "Permission denied");
    KSLOG_PARITY("Could not remove %s: %s", "/tmp/f", "No such file");
    KSLOG_PARITY("Could not stat %s: %s", "/tmp/f", "No such file");
    KSLOG_PARITY("Could not write file %s: %s", "/tmp/f", "No space left");
    KSLOG_PARITY("Could not rename %s to %s: %s", "/tmp/a", "/tmp/b", "Permission denied");
    KSLOG_PARITY("Could not seek file %s: %s", "/tmp/f", "Invalid argument");
    KSLOG_PARITY("Error reading directory %s: %s", "/tmp/d", "Permission denied");
    KSLOG_PARITY("Error reading file %s: %s", "/tmp/f", "I/O error");
    KSLOG_PARITY("Failed to create KVS file %s: %s", "/tmp/kvs", "No space left");
    KSLOG_PARITY("Failed to delete hang report at %s: %s", "/tmp/h", "Permission denied");
    KSLOG_PARITY("Failed to open KVS file for reading %s: %s", "/tmp/kvs", "Not found");
    KSLOG_PARITY("Failed to seek in %s: %s", "/tmp/f", "Invalid argument");
    KSLOG_PARITY("Failed to truncate %s: %s", "/tmp/f", "Permission denied");
    KSLOG_PARITY("Could not get %s value for %s: %s", "cpu", "idle", "Not found");
    KSLOG_PARITY("Could not get timeval value for %s: %s", "boottime", "Not found");
    KSLOG_PARITY("Could not get interface data for %s: %s", "en0", "Not found");
    KSLOG_PARITY("Could not get interface index for %s: %s", "en0", "Not found");
    KSLOG_PARITY("Error getting thread_info with flavor THREAD_IDENTIFIER_INFO from mach thread : %s",
                 "Invalid argument");
    KSLOG_PARITY("Error getting thread_info with flavor THREAD_BASIC_INFO from mach thread : %s", "Invalid argument");
    KSLOG_PARITY("Failed to add monitor API \"%s\"", "CustomMonitor");
    KSLOG_PARITY("ksobjc_copyStringContents %s failed", "x");
    KSLOG_PARITY("ksobjc_isValidObject %s failed", "x");
    KSLOG_PARITY("ksobjc_ivarNamed %s failed", "x");
    KSLOG_PARITY("ksobjc_ivarValue %s failed", "x");
    KSLOG_PARITY("%s: Unknown ivar type [%s]", "MyClass", "^@");
    KSLOG_PARITY("Performing rebinding with section %s,%s", "__DATA", "__la_symbol_ptr");
    KSLOG_PARITY("Section %s,%s not found", "__DATA", "__la_symbol_ptr");
    KSLOG_PARITY("Section %s not found in segment %s", "__cstring", "__TEXT");
    KSLOG_PARITY("Segment %s not found", "__LINKEDIT");
    KSLOG_PARITY("Searching for segment %s in Mach header at %p", "__TEXT", (void *)0x1000);
    KSLOG_PARITY("Monitor %s already exists. Skipping addition.", "Signal");
    KSLOG_PARITY("Monitor %s is now %sabled.", "Signal", "en");
}

- (void)testCallSiteParity_IntegerSpecifiers
{
    KSLOG_PARITY("Trapped signal %d", 11);
    KSLOG_PARITY("Assigning handler for signal %d", 6);
    KSLOG_PARITY("Restoring original handler for signal %d", 6);
    KSLOG_PARITY("Exceeded maximum number of dylibs (%d)", 512);
    KSLOG_PARITY("Got %d threads", 8);
    KSLOG_PARITY("check thread vs %d threads", 8);
    KSLOG_PARITY("Writing %d of %d threads.", 3, 8);
    KSLOG_PARITY("Thread count %d is higher than maximum of %d", 999, 64);
    KSLOG_PARITY("Too many reserved threads (%d). Max is %d", 64, 32);
    KSLOG_PARITY("No second-level page for index %d", 42);
    KSLOG_PARITY("Restoring exception ports to index %d: %s", 3, "ok");
    KSLOG_PARITY("Protection obtained: %d", 7);
    KSLOG_PARITY("Unsupported CFA rule type: %d", 5);
    KSLOG_PARITY("Invalid register number: %d", 99);
    KSLOG_PARITY("Skipped reading crash info: invalid version '%d'", 3);
    KSLOG_PARITY("Could not get the name for process %d: %s", 1234, "Not found");
    KSLOG_PARITY("Could not read fd %d: %s", 5, "Bad file descriptor");
    KSLOG_PARITY("Could not read from fd %d: %s", 5, "I/O error");
    KSLOG_PARITY("Could not write to fd %d: %s", 5, "Broken pipe");
    KSLOG_PARITY("Read returns 0 bytes, likely EOF for fd %d: %s", 5, "Success");
    KSLOG_PARITY("Could not seek to %d from end of %s: %s", 100, "/tmp/f", "Invalid argument");
    KSLOG_PARITY("Could not get %s value for %d,%d: %s", "ctl", 1, 2, "Not found");
    KSLOG_PARITY("Could not get timeval value for %d,%d: %s", 1, 2, "Not found");
    KSLOG_PARITY("Error: Could not allocate %u bytes of memory. KSZombie NOT installed!", 4096u);
    KSLOG_PARITY("dyld notifier: %u images added", 12u);
    KSLOG_PARITY("KVS appendRecord called with NULL value but valueLen %u", 16u);
    KSLOG_PARITY("KVS key too long (%u > %u), truncating", 100u, 64u);
    KSLOG_PARITY("KVS string value too long (%u > %u), truncating", 100u, 64u);
    KSLOG_PARITY("Unsupported KVS version %u", 2u);
    KSLOG_PARITY("Invalid encoding index %u", 7u);
    KSLOG_PARITY("Unsupported CIE version: %u", 4u);
    KSLOG_PARITY("Unsupported unwind info version: %u", 3u);
    KSLOG_PARITY("Unknown second-level page kind: %u", 9u);
    KSLOG_PARITY("Command type %u not found", 0x19u);
    KSLOG_PARITY("Getting command by type %u in Mach header at %p", 0x19u, (void *)0x1000);
    KSLOG_PARITY("Getting section by flag %u in segment %s", 0x01u, "__TEXT");
    KSLOG_PARITY("Section with flag %u not found in segment %s", 0x01u, "__TEXT");
    KSLOG_PARITY("CFA base register %u is not available", 31u);
    KSLOG_PARITY("Failed to get return address (reg %u)", 30u);
}

- (void)testCallSiteParity_CharSpecifiers
{
    KSLOG_PARITY("Expected ':' but got '%c'", 'x');
    KSLOG_PARITY("Expected '\"' but got '%c'", 'x');
    KSLOG_PARITY("Expected \"\\u\" but got: \"%c%c\"", 'a', 'b');
    KSLOG_PARITY("Expected \"false\" but got \"f%c%c%c%c\"", 'o', 'o', 'o', 'o');
    KSLOG_PARITY("Expected \"null\" but got \"n%c%c%c\"", 'o', 'o', 'o');
    KSLOG_PARITY("Expected \"true\" but got \"t%c%c%c\"", 'o', 'o', 'o');
    KSLOG_PARITY("Invalid character '%c'", 'Q');
    KSLOG_PARITY("Invalid control character '%c'", '\t');
    KSLOG_PARITY("Not a digit: '%c'", 'z');
    KSLOG_PARITY("Unknown augmentation: %c", 'S');
    KSLOG_PARITY("Invalid unicode sequence: %c%c%c%c", 'a', 'b', 'c', 'd');
}

- (void)testCallSiteParity_HexSpecifiers
{
    KSLOG_PARITY("Filling thread state with flavor %x.", 0x5u);
    KSLOG_PARITY("Invalid KVS magic 0x%x", 0x4ec5c0de);
    KSLOG_PARITY("Unknown ARM32 unwind mode: 0x%x", 0x3u);
    KSLOG_PARITY("Unknown ARM64 unwind mode: 0x%x", 0x3u);
    KSLOG_PARITY("Unknown x86 unwind mode: 0x%x", 0x3u);
    KSLOG_PARITY("Unknown x86_64 unwind mode: 0x%x", 0x3u);
    KSLOG_PARITY("Unknown CFI opcode: 0x%x", 0x0Au);
    KSLOG_PARITY("Unknown pointer format: 0x%x", 0x0Fu);
    KSLOG_PARITY("Unsupported DWARF expression opcode: 0x%x", 0x10u);
    KSLOG_PARITY("Unsupported pointer modifier: 0x%x", 0x80u);
    KSLOG_PARITY("Target offset 0x%x not found in first-level index", 0x1234u);
    KSLOG_PARITY("Thread %s: Handling mach exception %x", "worker", 1u);
    KSLOG_PARITY("thread_resume (0x%x) failed: %d", 0x1234u, -1);
    KSLOG_PARITY("thread_suspend (0x%x) failed: %d", 0x1234u, -1);
    KSLOG_PARITY("%d: %x vs %x", 3, 0xAAu, 0xBBu);
    KSLOG_PARITY("Fill thread 0x%x context into %p. is crashed = %d", 0x1234u, (void *)0x4000, 1);
    KSLOG_PARITY("Writing thread %x (index %d). is crashed: %d", 0x1234u, 2, 0);
    KSLOG_PARITY("Invalid character 0x%02x in string: %s", 0x1Fu, "foo");
    KSLOG_PARITY("Invalid trail surrogate: 0x%04x", 0xABu);
    KSLOG_PARITY("Unexpected trail surrogate: 0x%04x", 0xCDu);
    KSLOG_PARITY("Invalid unicode: 0x%04x", 0x0Au);
    KSLOG_PARITY("thread_resume (%08x): %s", 0x1Au, "ok");
    KSLOG_PARITY("thread_suspend (%08x): %s", 0x1Au, "ok");
}

- (void)testCallSiteParity_PointerSpecifiers
{
    void *p1 = (void *)0x1000;
    void *p2 = (void *)0x20000;
    KSLOG_PARITY("Adding address pair: image=%p, function=%p", p1, p2);
    KSLOG_PARITY("Address %p not found", p1);
    KSLOG_PARITY("Calling original __cxa_throw function at %p", p1);
    KSLOG_PARITY("Error while getting dispatch queue name : %p", p1);
    KSLOG_PARITY("Failed to rebind __cxa_throw at %p", p1);
    KSLOG_PARITY("Failed to restore binding at %p", p1);
    KSLOG_PARITY("Finding address for %p", p1);
    KSLOG_PARITY("Get context from signal user context and put into %p.", p1);
    KSLOG_PARITY("Getting protection for section starting at %p", p1);
    KSLOG_PARITY("Installed dyld image notifier (original=%p)", p1);
    KSLOG_PARITY("Restoring binding at %p to %p", p1, p2);
    KSLOG_PARITY("Section %s found at %p", "__text", p1);
    KSLOG_PARITY("Segment %s found at %p", "__TEXT", p1);
    KSLOG_PARITY("Set isWritingReportCallback to %p", p1);
    KSLOG_PARITY("Setting userInfoJSON to %p", p1);
    KSLOG_PARITY("This thread doesn't have a dispatch queue attached : %p", p1);
    KSLOG_PARITY("Thread %p has an invalid dispatch queue pointer %p", p1, p2);
    KSLOG_PARITY("Thread %p has an invalid thread basic info %p", p1, p2);
    KSLOG_PARITY("Thread %p has an invalid thread identifier info %p", p1, p2);
    KSLOG_PARITY("Using fallback __cxa_throw at %p", p1);
    KSLOG_PARITY("Getting section data for %s,%s from Mach header at %p", "__TEXT", "__text", p1);
    KSLOG_PARITY("Searching for section %s in segment %s of Mach header at %p", "__cstring", "__TEXT", p1);
    KSLOG_PARITY("Segment %s not found in Mach header at %p", "__LINKEDIT", p1);
}

- (void)testCallSiteParity_LongSpecifiers
{
    KSLOG_PARITY("Address 0x%lx is in NULL page - terminating unwind", 0x10UL);
    KSLOG_PARITY("LR 0x%lx is in NULL page - terminating unwind", 0x10UL);
    KSLOG_PARITY("Compact unwind succeeded: returnAddr=0x%lx", 0x1234UL);
    KSLOG_PARITY("DWARF unwind failed for PC 0x%lx", 0x1234UL);
    KSLOG_PARITY("DWARF unwind succeeded: returnAddr=0x%lx", 0x1234UL);
    KSLOG_PARITY("DWARF unwind: returnAddr=0x%lx, newSP=0x%lx, newFP=0x%lx", 0x1UL, 0x2UL, 0x3UL);
    KSLOG_PARITY("EBP-frame unwind: returnAddr=0x%lx, newESP=0x%lx, newEBP=0x%lx", 0x1UL, 0x2UL, 0x3UL);
    KSLOG_PARITY("Encoding 0x%x requires DWARF for PC 0x%lx", 0x5u, 0x1234UL);
    KSLOG_PARITY("Failed to build CFI row for PC 0x%lx", 0x1234UL);
    KSLOG_PARITY("Failed to read frame at FP 0x%lx", 0x1234UL);
    KSLOG_PARITY("Failed to read previous EBP from EBP (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read previous FP from FP (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read previous R7 from R7 (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read previous RBP from RBP (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read return address from EBP+4 (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read return address from ESP (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read return address from ESP+stackSize-4 (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read return address from FP+8 (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read return address from R7+4 (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read return address from RBP+8 (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read return address from RSP (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Failed to read return address from SP+stackSize-8 (0x%lx)", 0x1234UL);
    KSLOG_PARITY("Found entry: func=0x%lx, encoding=0x%x", 0x1234UL, 0x5u);
    KSLOG_PARITY("Frame at FP 0x%lx has NULL return address", 0x1234UL);
    KSLOG_PARITY("Frame pointer unwind succeeded: returnAddr=0x%lx", 0x1234UL);
    KSLOG_PARITY("Frame-based unwind: returnAddr=0x%lx, newSP=0x%lx, newFP=0x%lx", 0x1UL, 0x2UL, 0x3UL);
    KSLOG_PARITY("Frame-based unwind: returnAddr=0x%lx, newSP=0x%lx, newR7=0x%lx", 0x1UL, 0x2UL, 0x3UL);
    KSLOG_PARITY("Frameless immediate: returnAddr=0x%lx, stackSize=%u (encoded=%u)", 0x1234UL, 16u, 1u);
    KSLOG_PARITY("Frameless leaf: returnAddr=0x%lx (from LR)", 0x1234UL);
    KSLOG_PARITY("Frameless leaf: returnAddr=0x%lx", 0x1234UL);
    KSLOG_PARITY("Frameless non-leaf: returnAddr=0x%lx, stackSize=%u", 0x1234UL, 16u);
    KSLOG_PARITY("LR fallback: stack direction violation, new FP 0x%lx <= current FP 0x%lx", 0x1UL, 0x2UL);
    KSLOG_PARITY("LR path: stack direction violation, new FP 0x%lx <= current FP 0x%lx", 0x1UL, 0x2UL);
    KSLOG_PARITY("No DWARF eh_frame info for PC 0x%lx", 0x1234UL);
    KSLOG_PARITY("No FDE found for PC 0x%lx", 0x1234UL);
    KSLOG_PARITY("No compact unwind entry for PC 0x%lx", 0x1234UL);
    KSLOG_PARITY("No compact unwind info for PC 0x%lx", 0x1234UL);
    KSLOG_PARITY("No unwind info, assuming leaf: returnAddr=0x%lx (from LR)", 0x1234UL);
    KSLOG_PARITY("No unwind info, assuming leaf: returnAddr=0x%lx", 0x1234UL);
    KSLOG_PARITY("RBP-frame unwind: returnAddr=0x%lx, newRSP=0x%lx, newRBP=0x%lx", 0x1UL, 0x2UL, 0x3UL);
    KSLOG_PARITY("SP not progressing during FP walk (0x%lx <= 0x%lx) - marking end of stack", 0x1UL, 0x2UL);
    KSLOG_PARITY("Stack direction violation: new FP 0x%lx <= current FP 0x%lx", 0x1UL, 0x2UL);
    KSLOG_PARITY("CFA = 0x%lx (reg %u + %ld)", 0x1234UL, 5u, -8L);
    KSLOG_PARITY("ARM32 decode: encoding=0x%x, mode=0x%x, pc=0x%lx, sp=0x%lx, r7=0x%lx, lr=0x%lx", 0x1u, 0x2u, 0x3UL,
                 0x4UL, 0x5UL, 0x6UL);
    KSLOG_PARITY("ARM64 decode: encoding=0x%x, mode=0x%x, pc=0x%lx, sp=0x%lx, fp=0x%lx, lr=0x%lx", 0x1u, 0x2u, 0x3UL,
                 0x4UL, 0x5UL, 0x6UL);
    KSLOG_PARITY("x86 decode: encoding=0x%x, mode=0x%x, pc=0x%lx, sp=0x%lx, bp=0x%lx", 0x1u, 0x2u, 0x3UL, 0x4UL, 0x5UL);
    KSLOG_PARITY("x86_64 decode: encoding=0x%x, mode=0x%x, pc=0x%lx, sp=0x%lx, bp=0x%lx", 0x1u, 0x2u, 0x3UL, 0x4UL,
                 0x5UL);
}

- (void)testCallSiteParity_SizeSpecifiers
{
    KSLOG_PARITY("Invalid unwind info: %p, size %zu", (void *)0x1000, (size_t)4096);
    KSLOG_PARITY("Section data at %p, size %zu", (void *)0x1000, (size_t)4096);
    KSLOG_PARITY("Cached image %s: unwind=%p(%zu) eh_frame=%p(%zu)", "MyApp", (void *)0x1, (size_t)10, (void *)0x2,
                 (size_t)20);
    KSLOG_PARITY("Image %s exceeds max segments (%d), truncating", "MyApp", 16);
    KSLOG_PARITY("last_run_id has unexpected length %zd (expected %d), ignoring", (ssize_t)7, 8);
}

- (void)testCallSiteParity_LongLongSpecifiers
{
    KSLOG_PARITY("Thread %s: Trapped mach exception code 0x%llx, subcode 0x%llx", "worker", (unsigned long long)0x1ULL,
                 (unsigned long long)0x2ULL);
    KSLOG_PARITY("Hang started (reportID: %llx)", (unsigned long long)0xABCDEF0123456789ULL);
    KSLOG_PARITY("Failed to finalize hang report %llx, deleting to prevent stale stitching",
                 (unsigned long long)0xABCDEF0123456789ULL);
    KSLOG_PARITY("Finalizing non-fatal report %lld", (long long)42);
}

- (void)testCallSiteParity_WatchdogAndMiscFormats
{
    KSLOG_PARITY("Failed to write new run ID to %s", "/tmp/run_id");
    KSLOG_PARITY("Thread %s: Could not set next level exception ports", "worker");
    KSLOG_PARITY("Thread %s: Crash handling complete. Restoring original handlers.", "worker");
    KSLOG_PARITY("Thread %s: Deallocating exception handler", "worker");
    KSLOG_PARITY("Thread %s: Fault address %p, instruction address %p", "worker", (void *)0x1000, (void *)0x2000);
    KSLOG_PARITY("Thread %s: Fetching machine state.", "worker");
    KSLOG_PARITY("Thread %s: Filling out context.", "worker");
    KSLOG_PARITY("Thread %s: Installing mach exception handler", "worker");
    KSLOG_PARITY("Thread %s: Mach exception handler installed on thread %d", "worker", 7);
    KSLOG_PARITY("Thread %s: Mach exception reply sent.", "worker");
    KSLOG_PARITY("Thread %s: Replying KERN_FAILURE so that the process won't try any further action from this "
                 "exception raise, and just crash",
                 "worker");
    KSLOG_PARITY("Thread %s: Replying KERN_SUCCESS so that the process will re-run the instruction that caused the "
                 "fault, fail again, and call the original handlers",
                 "worker");
    KSLOG_PARITY("Thread %s: Replying to exception message", "worker");
    KSLOG_PARITY("Thread %s: Restoring original exception ports", "worker");
    KSLOG_PARITY("Thread %s: Should exit immediately, so returning", "worker");
    KSLOG_PARITY("Thread %s: Still handling an exception, so not deallocating yet", "worker");
    KSLOG_PARITY("Thread %s: Waiting for mach exception", "worker");
    KSLOG_PARITY("mprotect failed for binding at %p: %s", (void *)0x1000, "Permission denied");
    KSLOG_PARITY("mprotect restore failed for binding at %p: %s", (void *)0x1000, "Permission denied");
    KSLOG_PARITY("sigaction (%s): %s", "SIGSEGV", "Invalid argument");
    KSLOG_PARITY("Cannot access binary images");
    KSLOG_PARITY("Unexpected state: dyld_all_image_infos->infoArray is NULL!");
    KSLOG_PARITY("Initializing binary image cache");
    KSLOG_PARITY("Failed to acquire TASK_DYLD_INFO. We won't have access to binary images.");
    KSLOG_PARITY("Writing crash report to %s", "/tmp/r.json");
    KSLOG_PARITY("Writing recrash report to %s", "/tmp/r2.json");
}

- (void)testCallSiteBehavior_FloatPrecisionIgnored
{
    // Our signal-safe formatter intentionally ignores precision (the ".3" in
    // "%.3f"). Instead it uses FLT_DIG/DBL_DIG significant digits. This is the
    // only call site in the codebase that actually uses a float specifier, so
    // we document the behavior here rather than asserting snprintf parity.
    //
    // Source: KSCrashMonitor_Watchdog.c:426
    //   KSLOG_INFO("Hang ended (reportID: %" PRIx64 ", duration: %.3f s)", ...)
    NSString *result = [self captureLogOutput:^{
        i_kslog_logCBasic("Hang ended (reportID: %llx, duration: %.3f s)", (unsigned long long)0xABCDULL, 1.25);
    }];
    XCTAssertTrue([result hasPrefix:@"Hang ended (reportID: abcd, duration: "], @"got: %@", result);
    XCTAssertTrue([result hasSuffix:@" s)"], @"got: %@", result);
    NSRange open = [result rangeOfString:@"duration: "];
    NSRange close = [result rangeOfString:@" s)"];
    NSString *durStr = [result substringWithRange:NSMakeRange(NSMaxRange(open), close.location - NSMaxRange(open))];
    double parsed = strtod(durStr.UTF8String, NULL);
    XCTAssertEqualWithAccuracy(parsed, 1.25, 0.001, @"duration didn't round-trip, got: %@", durStr);
}

#undef KSLOG_PARITY

@end
