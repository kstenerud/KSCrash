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

@end
