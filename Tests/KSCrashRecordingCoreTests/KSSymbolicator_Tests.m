//
//  KSSymbolicator_Tests.m
//
//  Created by Gleb Linnik on 28.07.2026.
//
//  Copyright (c) 2016 Karl Stenerud. All rights reserved.
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

#import <dlfcn.h>

#import "KSDynamicLinker.h"
#import "KSStackCursor.h"
#import "KSStackCursor_Backtrace.h"
#import "KSSymbolicator.h"

@interface KSSymbolicator_Tests : XCTestCase
@end

@implementation KSSymbolicator_Tests

+ (void)setUp
{
    [super setUp];
    // Only the symbolicate tests need the dynamic linker cache, and it survives the class.
    ksdl_resetCache();
    ksdl_init();
}

/** Canonical start address of a real symbol, used as a stand-in for a Swift async
 * continuation funclet: both are instruction-aligned symbol starts.
 *
 * Taken via dladdr() rather than from `&function` because the tests build as arm64e,
 * where a raw function pointer can carry a pointer-authentication signature.
 */
- (uintptr_t)symbolStartAddress
{
    Dl_info info = { 0 };
    XCTAssertNotEqual(dladdr((const void *)&kssymbolicator_callInstructionAddress, &info), 0);
    XCTAssertTrue(info.dli_saddr != NULL);
    return (uintptr_t)info.dli_saddr;
}

/** Symbolicates a single-frame backtrace and returns the resolved symbol start address. */
- (uintptr_t)symbolAddressForBacktraceAddress:(uintptr_t)address
{
    const uintptr_t backtrace[] = { address };
    KSStackCursor cursor;
    kssc_initWithBacktrace(&cursor, backtrace, 1, 0);

    XCTAssertTrue(cursor.advanceCursor(&cursor));
    XCTAssertTrue(cursor.symbolicate(&cursor));
    return cursor.stackEntry.symbolAddress;
}

/** A frame-pointer-walked return address is the instruction *after* the call, so
 * symbolication must step back into the call instruction itself.
 */
- (void)testCallInstructionAddressStepsBackFromReturnAddress
{
    uintptr_t returnAddress = 0x4000;
    XCTAssertEqual(kssymbolicator_callInstructionAddress(returnAddress), returnAddress - 1);
}

/** The unbiased case must keep resolving to the calling function, so that fixing
 * the async path does not regress ordinary frame-pointer backtraces.
 */
- (void)testSymbolicateResolvesReturnAddressToCallingFunction
{
    uintptr_t functionStart = [self symbolStartAddress];
    // An address a few instructions into the function, as a return address would be.
    XCTAssertEqual([self symbolAddressForBacktraceAddress:functionStart + 8], functionStart);
}

// The two tests below are excluded on armv7, where the low bit is the Thumb-mode flag and
// genuinely is a tag rather than the continuation bias described in KSSymbolicator.c.
#if !defined(__arm__)

/** `backtrace_async()` biases continuation addresses by +1; the bias must survive to the
 * subtraction rather than being masked off first.
 */
- (void)testCallInstructionAddressKeepsAsyncContinuationBias
{
    uintptr_t funcletStart = 0x4000;
    XCTAssertEqual(kssymbolicator_callInstructionAddress(funcletStart + 1), funcletStart);
}

/** End-to-end: a biased continuation address must symbolicate to its own symbol,
 * not to the one before it.
 */
- (void)testSymbolicateResolvesBiasedContinuationToItsOwnSymbol
{
    uintptr_t funcletStart = [self symbolStartAddress];
    XCTAssertEqual([self symbolAddressForBacktraceAddress:funcletStart + 1], funcletStart,
                   @"biased continuation address resolved to the preceding symbol");
}

#endif

@end
