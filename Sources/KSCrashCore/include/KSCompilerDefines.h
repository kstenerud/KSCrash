//
//  KSCompilerDefines.h
//
//  Created by Nikolay Volosatov on 2024-11-03.
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

#ifndef HDR_KSCompilerDefines_h
#define HDR_KSCompilerDefines_h

/** Disables optimisations to ensure a function remains in stacktrace.
 * Usually used in pair with `KS_THWART_TAIL_CALL_OPTIMISATION`.
 */
#define KS_KEEP_FUNCTION_IN_STACKTRACE __attribute__((disable_tail_calls))

/** Disables inline optimisation.
 * Usually used in pair with `KS_KEEP_FUNCTION_IN_STACKTRACE`.
 */
#define KS_NOINLINE __attribute__((noinline))

/** Extra safety measure to ensure a method is not tail-call optimised.
 * This define should be placed at the end of a function.
 * Usually used in pair with `KS_KEEP_FUNCTION_IN_STACKTRACE`.
 */
#define KS_THWART_TAIL_CALL_OPTIMISATION __asm__ __volatile__("");

#endif  // HDR_KSCompilerDefines_h
