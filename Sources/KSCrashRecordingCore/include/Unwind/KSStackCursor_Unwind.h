//
// KSStackCursor_Unwind.h
//
// Created by Alexander Cohen on 2025-01-16.
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

#ifndef KSStackCursor_Unwind_h
#define KSStackCursor_Unwind_h

#include "KSStackCursor.h"

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Unwind Method Tracking

/**
 * The method used to unwind a particular stack frame.
 */
typedef enum {
    /** No unwind method used yet (initial state or first frame). */
    KSUnwindMethod_None = 0,

    /** Unwound using Apple's Compact Unwind (__unwind_info section). */
    KSUnwindMethod_CompactUnwind,

    /** Unwound using DWARF CFI (__eh_frame section). */
    KSUnwindMethod_Dwarf,

    /** Unwound using frame pointer walking (fallback). */
    KSUnwindMethod_FramePointer
} KSUnwindMethod;

/**
 * Get a human-readable string for an unwind method.
 *
 * @param method The unwind method.
 * @return A static string describing the method (e.g., "compact_unwind", "dwarf", "frame_pointer").
 */
const char *kssc_unwindMethodName(KSUnwindMethod method);

/**
 * Get the unwind method used for the current frame.
 *
 * This function returns the method that was used to unwind to the current
 * frame. Call this after advanceCursor() to see how the frame was unwound.
 *
 * @param cursor The stack cursor (must have been initialized with kssc_initWithUnwind).
 * @return The unwind method used for the current frame, or KSUnwindMethod_None if
 *         the cursor is not an unwind cursor or hasn't advanced yet.
 */
KSUnwindMethod kssc_getUnwindMethod(const KSStackCursor *cursor);

// MARK: - Initialization

/**
 * Initialize a stack cursor using compact unwind data with fallback chain.
 *
 * This cursor attempts to unwind the stack using the following methods in order:
 * 1. Compact Unwind (Apple's __unwind_info section)
 * 2. DWARF CFI (__eh_frame section) - fallback for complex functions
 * 3. Frame Pointer walking - final fallback
 *
 * This provides accurate stack traces even for code compiled with
 * -fomit-frame-pointer.
 *
 * @param cursor The cursor to initialize.
 * @param maxStackDepth The maximum depth to search before giving up.
 * @param machineContext The machine context to read registers from.
 */
void kssc_initWithUnwind(KSStackCursor *cursor, int maxStackDepth, const struct KSMachineContext *machineContext);

#ifdef __cplusplus
}
#endif

#endif  // KSStackCursor_Unwind_h
