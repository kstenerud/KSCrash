//
//  KSStackCursor_SelfThread_Tests.m
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

#import "KSCompilerDefines.h"
#import "KSStackCursor_SelfThread.h"

#import <dlfcn.h>

@interface KSStackCursorSelfThreadTests : XCTestCase
@end

@implementation KSStackCursorSelfThreadTests

static NSString *symbolNameForAddress(uintptr_t address)
{
    Dl_info info = { 0 };
    if (dladdr((void *)address, &info) == 0 || info.dli_sname == NULL) {
        return nil;
    }
    return [NSString stringWithUTF8String:info.dli_sname];
}

static NSString *firstSelfThreadFrameSymbol(int skipEntries) KS_NOINLINE KS_KEEP_FUNCTION_IN_STACKTRACE;
static NSString *firstSelfThreadFrameSymbol(int skipEntries)
{
    KSStackCursor cursor;
    kssc_initSelfThread(&cursor, skipEntries);
    if (!cursor.advanceCursor(&cursor)) {
        return nil;
    }
    return symbolNameForAddress(cursor.stackEntry.address);
}

static NSString *selfThreadCursorSkipZeroFrame(void) KS_NOINLINE KS_KEEP_FUNCTION_IN_STACKTRACE;
static NSString *selfThreadCursorSkipZeroFrame(void)
{
    NSString *symbol = firstSelfThreadFrameSymbol(0);
    KS_THWART_TAIL_CALL_OPTIMISATION
    return symbol;
}

static NSString *selfThreadCursorSkipOneFrame(void) KS_NOINLINE KS_KEEP_FUNCTION_IN_STACKTRACE;
static NSString *selfThreadCursorSkipOneFrame(void)
{
    NSString *symbol = firstSelfThreadFrameSymbol(1);
    KS_THWART_TAIL_CALL_OPTIMISATION
    return symbol;
}

- (void)assertSelfThreadCursorPreservesSkipEntries
{
    NSString *skipZeroSymbol = selfThreadCursorSkipZeroFrame();
    XCTAssertNotNil(skipZeroSymbol);
    XCTAssertTrue([skipZeroSymbol containsString:@"firstSelfThreadFrameSymbol"],
                  @"skipEntries=0 should make the caller of kssc_initSelfThread the first cursor frame, got %@",
                  skipZeroSymbol);

    NSString *skipOneSymbol = selfThreadCursorSkipOneFrame();
    XCTAssertNotNil(skipOneSymbol);
    XCTAssertTrue([skipOneSymbol containsString:@"selfThreadCursorSkipOneFrame"],
                  @"skipEntries=1 should skip one caller frame after kssc_initSelfThread, got %@", skipOneSymbol);
}

- (void)testInitSelfThreadPreservesSkipEntriesWhenSwiftAsyncStackTracesDisabled
{
    kssc_setSwiftAsyncStackTracesEnabled(false);
    [self assertSelfThreadCursorPreservesSkipEntries];
}

- (void)testInitSelfThreadPreservesSkipEntriesWhenSwiftAsyncStackTracesEnabled
{
    kssc_setSwiftAsyncStackTracesEnabled(true);
    [self assertSelfThreadCursorPreservesSkipEntries];
    kssc_setSwiftAsyncStackTracesEnabled(false);
}

@end
