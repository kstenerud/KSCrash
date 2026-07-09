//
//  KSStackCursor_SelfThread.c
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

#include "KSStackCursor_SelfThread.h"

#include <Availability.h>
#include <execinfo.h>
#include <stdatomic.h>

#include "KSCompilerDefines.h"
#include "KSStackCursor_Backtrace.h"

// #define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#define MAX_BACKTRACE_LENGTH (KSSC_CONTEXT_SIZE - sizeof(KSStackCursor_Backtrace_Context) / sizeof(void *) - 1)

typedef struct {
    KSStackCursor_Backtrace_Context SelfThreadContextSpacer;
    uintptr_t backtrace[0];
} SelfThreadContext;

#if defined(__clang_major__) && __clang_major__ >= 13 &&                                                             \
    ((defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && defined(__MAC_12_0) &&                                              \
      __MAC_OS_X_VERSION_MAX_ALLOWED >= __MAC_12_0) ||                                                               \
     (defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && defined(__IPHONE_15_0) &&                                          \
      __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_15_0) ||                                                           \
     (defined(__TV_OS_VERSION_MAX_ALLOWED) && defined(__TVOS_15_0) && __TV_OS_VERSION_MAX_ALLOWED >= __TVOS_15_0) || \
     (defined(__WATCH_OS_VERSION_MAX_ALLOWED) && defined(__WATCHOS_8_0) &&                                           \
      __WATCH_OS_VERSION_MAX_ALLOWED >= __WATCHOS_8_0) ||                                                            \
     (defined(__VISION_OS_VERSION_MAX_ALLOWED) && defined(__VISIONOS_1_0) &&                                         \
      __VISION_OS_VERSION_MAX_ALLOWED >= __VISIONOS_1_0))
#define KSCRASH_HAS_BACKTRACE_ASYNC 1
#else
#define KSCRASH_HAS_BACKTRACE_ASYNC 0
#endif

static atomic_bool g_swiftAsyncStackTracesEnabled = false;

void kssc_setSwiftAsyncStackTracesEnabled(bool enabled)
{
    atomic_store_explicit(&g_swiftAsyncStackTracesEnabled, enabled, memory_order_relaxed);
}

static int captureBacktrace(void **backtraceBuffer, int maxBacktraceLength)
{
#if KSCRASH_HAS_BACKTRACE_ASYNC
    if (atomic_load_explicit(&g_swiftAsyncStackTracesEnabled, memory_order_relaxed)) {
        if (__builtin_available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)) {
            return (int)backtrace_async(backtraceBuffer, (size_t)maxBacktraceLength, NULL);
        }
    }
#endif
    return backtrace(backtraceBuffer, maxBacktraceLength);
}

void kssc_initSelfThread(KSStackCursor *cursor, int skipEntries) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    SelfThreadContext *context = (SelfThreadContext *)cursor->context;
    int backtraceLength = captureBacktrace((void **)context->backtrace, MAX_BACKTRACE_LENGTH);
    kssc_initWithBacktrace(cursor, context->backtrace, backtraceLength, skipEntries + 1);
    KS_THWART_TAIL_CALL_OPTIMISATION
}
