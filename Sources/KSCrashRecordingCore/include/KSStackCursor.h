//
//  KSStackCursor.h
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

#ifndef KSStackCursor_h
#define KSStackCursor_h

#include <stdbool.h>
#include <sys/types.h>

#include "KSCrashNamespace.h"
#include "KSMachineContext.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KSSC_CONTEXT_SIZE 100

/** Point at which to give up walking a stack and consider it a stack overflow. */
#define KSSC_STACK_OVERFLOW_THRESHOLD 150

/** The max depth to search before giving up. */
#define KSSC_MAX_STACK_DEPTH 500

typedef struct KSStackCursor {
    struct {
        /** Current address in the stack trace. */
        uintptr_t address;

        /** The name (if any) of the binary image the current address falls inside. */
        const char *imageName;

        /** The starting address of the binary image the current address falls inside. */
        uintptr_t imageAddress;

        /** The name (if any) of the closest symbol to the current address. */
        const char *symbolName;

        /** The address of the closest symbol to the current address. */
        uintptr_t symbolAddress;
    } stackEntry;
    struct {
        /** Current depth as we walk the stack (1-based). */
        int currentDepth;

        /** If true, cursor has given up walking the stack. */
        bool hasGivenUp;
    } state;

    /** Reset the cursor back to the beginning. */
    void (*resetCursor)(struct KSStackCursor *);

    /** Advance the cursor to the next stack entry. */
    bool (*advanceCursor)(struct KSStackCursor *);

    /** Attempt to symbolicate the current address, filling in the fields in stackEntry. */
    bool (*symbolicate)(struct KSStackCursor *);

    /** Internal context-specific information. */
    void *context[KSSC_CONTEXT_SIZE];
} KSStackCursor;

/** Common initialization routine for a stack cursor.
 *  Note: This is intended primarily for other cursors to call.
 *
 * @param cursor The cursor to initialize.
 *
 * @param resetCursor Function that will reset the cursor (NULL = default: Do nothing).
 *
 * @param advanceCursor Function to advance the cursor (NULL = default: Do nothing and return false).
 */
void kssc_initCursor(KSStackCursor *cursor, void (*resetCursor)(KSStackCursor *),
                     bool (*advanceCursor)(KSStackCursor *));

/** Reset a cursor.
 *  INTERNAL METHOD. Do not call!
 *
 * @param cursor The cursor to reset.
 */
void kssc_resetCursor(KSStackCursor *cursor);

#ifdef __cplusplus
}
#endif

#endif  // KSStackCursor_h
