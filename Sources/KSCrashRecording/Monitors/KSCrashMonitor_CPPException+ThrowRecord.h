//
//  KSCrashMonitor_CPPException+ThrowRecord.h
//
//  Created by Mischan Toosarani-Hausberger on 2026-11-19.
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

#ifndef KSCrashMonitor_CPPException_ThrowRecord_h
#define KSCrashMonitor_CPPException_ThrowRecord_h

#include "KSCxaThrowSwapper.h"
#include "KSStackCursor.h"

#ifdef __cplusplus
extern "C" {
#endif

// Reserve a cursor for this exception without incrementing its reference count.
// If all candidate slots are busy, return NULL; the caller must leave the original destructor in place.
KSStackCursor *kstr_reserve(void *object);

// After filling the reserved cursor, publish it for the same exception and save its
// original destructor (which may be NULL). Only then install kstr_release as its destructor.
void kstr_publish(KSStackCursor *cursor, void *object, ksct_destructor destructor);

// Return the saved cursor, or NULL if this exception has no published record.
// The caller must keep the primary exception alive until it has finished reading the cursor.
const KSStackCursor *kstr_find(void *object);

// Called by libc++abi when it destroys a recorded exception. Free the slot first,
// then call the original destructor exactly once if it was non-NULL.
void kstr_release(void *object);

#ifdef __cplusplus
}
#endif

#endif
