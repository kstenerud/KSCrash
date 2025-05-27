//
// KSBacktrace.h
//
// Created by Alexander Cohen on 2025-05-27.
//
// Copyright (c) 2012 Karl Stenerud. All rights reserved.
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

#ifndef HDR_KSBacktrace_h
#define HDR_KSBacktrace_h

#include <CoreFoundation/CoreFoundation.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Captures the backtrace (call stack) for the specified pthread.
 *
 * @param thread      The identifier of the pthread whose backtrace should be captured. Must be a valid, non-null
 * thread.
 * @param addresses   A pointer to a buffer to receive the backtrace addresses. Must not be NULL.
 * @param count       The maximum number of addresses to capture. Must be greater than zero.
 *
 * @return The number of frames captured and written to @c addresses, or 0 if @c addresses is NULL, @c count is zero, or
 * an error occurs.
 *
 * @discussion This function is not async-signal-safe and therefore must not be called from within a signal handler.
 *             It may also briefly suspend the target thread while unwinding its stack.
 */

int ksbt_captureBacktrace(pthread_t _Nonnull thread, uintptr_t *_Nonnull addresses, int count)
    CF_SWIFT_NAME(captureBacktrace(thread:addresses:count:));

/**
 * Information about a symbol and the image in which it resides.
 *
 * @field returnAddress    The return address of the instruction being symbolicated.
 * @field callInstruction    The call address of the instruction being symbolicated.
 * @field symbolAddress    The start address of the resolved symbol.
 * @field symbolName       The name of the symbol, or NULL if unavailable.
 * @field imageName        The filename of the binary image containing this symbol.
 * @field imageUUID        A pointer to the 16-byte UUID of the image, or NULL.
 * @field imageAddress     The load address of the image in memory.
 * @field imageSize        The size of the image in bytes.
 */
struct KSSymbolInformation {
    uintptr_t returnAddress;
    uintptr_t callInstruction;
    uintptr_t symbolAddress;
    const char *_Nullable symbolName;
    const char *_Nullable imageName;
    const uint8_t *_Nullable imageUUID;
    uintptr_t imageAddress;
    uint64_t imageSize;
} CF_SWIFT_NAME(SymbolInformation);

/**
 * Resolves symbol information for a given instruction address.
 *
 * @param address  The instruction address to symbolize.
 * @param result   A pointer to a KSSymbolInformation structure to be populated. Must not be NULL.
 *
 * @return @c true if symbolication succeeded and @c result is populated, @c false otherwise.
 *
 * @discussion On success, @c result will contain the symbol name, symbol address, image name,
 *             image load address, image size, and image UUID associated with @c address.
 */
bool ksbt_symbolicateAddress(uintptr_t address, struct KSSymbolInformation *_Nonnull result)
    CF_SWIFT_NAME(symbolicate(address:result:));

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSBacktrace_h
