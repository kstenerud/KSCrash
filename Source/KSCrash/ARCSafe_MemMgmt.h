//
//  ARCSafe_MemMgmt.h
//
//  Copyright (c) 2011 Karl Stenerud. All rights reserved.
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


#ifndef HDR_ARCSafe_MemMgmt_h
#define HDR_ARCSafe_MemMgmt_h


/** Memory management macros and defines that allow you to write code that
 * compiles in both ARC and non-ARC modes.
 *
 *
 * Ownership Handling Macros:
 *
 * - as_retain(id object): Retain an object. Returns the retained object.
 *
 * - as_release(id object): Release an object.
 *
 * - as_autorelease(id object): Autorelease an object. Returns the object.
 *
 * - as_autorelease_noref(id object): Same as as_autorelease(), but does not
 *                                    return a value. Use for standalone
 *                                    autorelease with no assignment.
 *
 * - as_superdealloc(): Call [super dealloc] in non-ARC. Do nothing in ARC.
 *
 *
 * Property Qualifiers:
 *
 * - as_weakprop: "weak" for ARC, "assign" for non-ARC.
 *
 * - as_strongprop: "strong" for ARC, "retain" for non-ARC.
 *
 *
 * Storage Qualifiers:
 *
 * - as_weak: "__weak" for ARC, nothing for non-ARC.
 *
 * - as_strong: "__strong" for ARC, nothing for non-ARC.
 *
 * - as_unsafe_unretained: "__unsafe_unretained" for ARC, nothing for non-ARC.
 *
 * - as_autoreleasing: "__autoreleasing" for ARC, nothing for non-ARC.
 *
 *
 * ARC Bridging:
 *
 * - as_bridge: bridge between retainable and non-retainable types.
 *
 * - as_bridge_retained: bridge from retainable to non-retainable type.
 *
 * - as_bridge_transfer: bridge from non-retainable to retainable type.
 *
 *
 * Autorelease Pools (Only needed for GCC support):
 *
 * - as_autoreleasepool_start(NAME): Start an autorelease pool.
 *
 * - as_autoreleasepool_end(NAME): End an autorelease pool.
 */
#if __has_feature(objc_arc)

    #define as_retain(X)             (X)
    #define as_release(X)
    #define as_autorelease(X)        (X)
    #define as_autorelease_noref(X)
    #define as_superdealloc()

    #define as_weakprop              weak
    #define as_strongprop            strong

    #define as_weak                  __weak
    #define as_strong                __strong
    #define as_unsafe_unretained     __unsafe_unretained
    #define as_autoreleasing         __autoreleasing

    #define as_bridge                __bridge
    #define as_bridge_retained       __bridge_retained
    #define as_bridge_transfer       __bridge_transfer

    #define as_autoreleasepool_start(NAME) @autoreleasepool {
    #define as_autoreleasepool_end(NAME)   }

#else

    #define as_retain(X)            [(X) retain]
    #define as_release(X)           [(X) release]
    #define as_autorelease(X)       [(X) autorelease]
    #define as_autorelease_noref(X) [(X) autorelease]
    #define as_superdealloc()       [super dealloc]

    #define as_weakprop             assign
    #define as_strongprop           retain

    #define as_weak
    #define as_strong
    #define as_unsafe_unretained
    #define as_autoreleasing

    #define as_bridge
    #define as_bridge_retained
    #define as_bridge_transfer

#ifdef __clang__
    #define as_autoreleasepool_start(NAME) @autoreleasepool {
    #define as_autoreleasepool_end(NAME)   }
#else
    #define as_autoreleasepool_start(NAME) NSAutoreleasePool* NAME = [[NSAutoreleasePool alloc] init];
    #define as_autoreleasepool_end(NAME)   [NAME release];
#endif

#endif


#endif // HDR_ARCSafe_MemMgmt_h
