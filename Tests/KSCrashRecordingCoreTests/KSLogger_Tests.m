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

@end
