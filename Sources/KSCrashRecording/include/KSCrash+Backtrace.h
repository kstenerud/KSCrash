//
//  KSCrash+Backtrace.h
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

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <pthread.h>

#import "KSBacktrace.h"
#import "KSCrash.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Backtrace capture and symbolication methods for KSCrash.
 */
@interface KSCrash (Backtrace)

#pragma mark - Backtrace Capture -

/**
 * Captures the backtrace (call stack) for the specified mach thread.
 *
 * @param machThread The identifier of the mach thread whose backtrace should be captured.
 * @param addresses  A pointer to a buffer to receive the backtrace addresses. Must not be NULL.
 * @param count      The maximum number of addresses to capture. Must be greater than zero.
 *
 * @return The number of frames captured and written to @c addresses.
 */
- (int)captureBacktraceFromMachThread:(thread_t)machThread addresses:(uintptr_t *_Nonnull)addresses count:(int)count;

/**
 * Captures the backtrace (call stack) for the specified pthread.
 *
 * @param thread    The identifier of the pthread whose backtrace should be captured.
 * @param addresses A pointer to a buffer to receive the backtrace addresses. Must not be NULL.
 * @param count     The maximum number of addresses to capture. Must be greater than zero.
 *
 * @return The number of frames captured and written to @c addresses.
 */
- (int)captureBacktraceFromThread:(pthread_t _Nonnull)thread addresses:(uintptr_t *_Nonnull)addresses count:(int)count;

/**
 * Captures the backtrace (call stack) for the specified mach thread with truncation detection.
 *
 * @param machThread   The identifier of the mach thread whose backtrace should be captured.
 * @param addresses    A pointer to a buffer to receive the backtrace addresses. Must not be NULL.
 * @param count        The maximum number of addresses to capture. Must be greater than zero.
 * @param isTruncated  Optional. If non-NULL, set to @c YES when the stack is deeper than @c count
 *                     (i.e. the backtrace was truncated), or @c NO otherwise.
 *
 * @return The number of frames captured and written to @c addresses.
 */
- (int)captureBacktraceFromMachThread:(thread_t)machThread
                            addresses:(uintptr_t *_Nonnull)addresses
                                count:(int)count
                          isTruncated:(BOOL *_Nullable)isTruncated;

/**
 * Captures the backtrace (call stack) for the specified pthread with truncation detection.
 *
 * @param thread       The identifier of the pthread whose backtrace should be captured.
 * @param addresses    A pointer to a buffer to receive the backtrace addresses. Must not be NULL.
 * @param count        The maximum number of addresses to capture. Must be greater than zero.
 * @param isTruncated  Optional. If non-NULL, set to @c YES when the stack is deeper than @c count
 *                     (i.e. the backtrace was truncated), or @c NO otherwise.
 *
 * @return The number of frames captured and written to @c addresses.
 */
- (int)captureBacktraceFromThread:(pthread_t _Nonnull)thread
                        addresses:(uintptr_t *_Nonnull)addresses
                            count:(int)count
                      isTruncated:(BOOL *_Nullable)isTruncated;

#pragma mark - Symbolication -

/**
 * Resolves symbol information for a given instruction address.
 *
 * @param address  The instruction address to symbolize.
 * @param result   A pointer to a KSSymbolInformation structure to be populated. Must not be NULL.
 *
 * @return @c YES if symbolication succeeded and @c result is populated, @c NO otherwise.
 */
- (BOOL)symbolicateAddress:(uintptr_t)address result:(struct KSSymbolInformation *_Nonnull)result;

/**
 * Quickly resolves symbol information for a given instruction address.
 *
 * This is a faster variant that omits the image size and UUID fields.
 *
 * @param address  The instruction address to symbolize.
 * @param result   A pointer to a KSSymbolInformation structure to be populated. Must not be NULL.
 *
 * @return @c YES if symbolication succeeded and @c result is populated, @c NO otherwise.
 */
- (BOOL)quickSymbolicateAddress:(uintptr_t)address result:(struct KSSymbolInformation *_Nonnull)result;

@end

NS_ASSUME_NONNULL_END
