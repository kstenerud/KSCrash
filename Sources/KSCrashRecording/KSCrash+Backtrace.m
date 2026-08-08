//
//  KSCrash+Backtrace.m
//
//  Created by Alexander Cohen on 2025-01-28.
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

#import "KSCrash+Backtrace.h"

@implementation KSCrash (Backtrace)

// ============================================================================
#pragma mark - Backtrace Capture -
// ============================================================================

- (int)captureBacktraceFromMachThread:(thread_t)machThread addresses:(uintptr_t *)addresses count:(int)count
{
    return ksbt_captureBacktraceFromMachThread(machThread, addresses, count);
}

- (int)captureBacktraceFromThread:(pthread_t)thread addresses:(uintptr_t *)addresses count:(int)count
{
    return ksbt_captureBacktrace(thread, addresses, count);
}

- (int)captureBacktraceFromMachThread:(thread_t)machThread
                            addresses:(uintptr_t *)addresses
                                count:(int)count
                          isTruncated:(BOOL *)isTruncated
{
    bool truncated = false;
    int result = ksbt_captureBacktraceFromMachThreadWithTruncation(machThread, addresses, count, &truncated);
    if (isTruncated) {
        *isTruncated = truncated;
    }
    return result;
}

- (int)captureBacktraceFromThread:(pthread_t)thread
                        addresses:(uintptr_t *)addresses
                            count:(int)count
                      isTruncated:(BOOL *)isTruncated
{
    bool truncated = false;
    int result = ksbt_captureBacktraceWithTruncation(thread, addresses, count, &truncated);
    if (isTruncated) {
        *isTruncated = truncated;
    }
    return result;
}

// ============================================================================
#pragma mark - Symbolication -
// ============================================================================

- (BOOL)symbolicateAddress:(uintptr_t)address result:(struct KSSymbolInformation *)result
{
    return ksbt_symbolicateAddress(address, result);
}

- (BOOL)quickSymbolicateAddress:(uintptr_t)address result:(struct KSSymbolInformation *)result
{
    return ksbt_quickSymbolicateAddress(address, result);
}

@end
