//
//  KSStackCursor_Backtrace.h
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


#ifndef KSStackCursor_Backtrace_h
#define KSStackCursor_Backtrace_h

#ifdef __cplusplus
extern "C" {
#endif
    
    
#include "KSStackCursor.h"

/** Initialize a stack cursor for an existing backtrace (array of addresses).
 *
 * @param cursor The stack cursor to initialize.
 *
 * @param maxStackDepth The stack depth at which to consider it a stack overflow and give up.
 *
 * @param backtrace The existing backtrace to walk.
 *
 * @oaram backtraceLength The length of the backtrace.
 */
void kssc_initWithBacktrace(KSStackCursor *cursor, int maxStackDepth, const uintptr_t* backtrace, int backtraceLength);
    
    
#ifdef __cplusplus
}
#endif

#endif // KSStackCursor_Backtrace_h
