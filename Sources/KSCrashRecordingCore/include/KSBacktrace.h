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

#include <pthread.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Captures a backtrace (call stack) for the specified thread.
 *
 * @param thread    The non-null pthread_t identifier of the thread whose backtrace should be captured.
 * @param addresses A non-null pointer to a buffer where captured backtrace addresses will be stored.
 * @param count     The maximum number of address entries to write into @c addresses.
 *
 * @return The number of stack frames actually captured and stored in @c addresses.
 *         Returns 0 if @p addresses is NULL, @p count is zero, or an error occurs.
 *
 * @note This function is not async-signal-safe and must not be called from a signal handler.
 */

int ks_captureBacktrace(pthread_t _Nonnull thread, uintptr_t *_Nonnull addresses, int count);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSBacktrace_h

