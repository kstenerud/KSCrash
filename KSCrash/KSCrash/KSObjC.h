//
//  KSObjC.h
//
//  Created by Karl Stenerud on 2012-08-30.
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


#ifndef HDR_KSObjC_h
#define HDR_KSObjC_h

#ifdef __cplusplus
extern "C" {
#endif


#include <stdbool.h>


typedef enum
{
    kObjCObjectTypeNone,
    kObjCObjectTypeClass,
    kObjCObjectTypeObject,
} ObjCObjectType;

/** Interpret a pointer as an object or class and attempt to get its class name.
 *
 * @param potentialObject The pointer that may be an object.
 *
 * @return The class name or NULL if not found.
 */
const char* ksobjc_className(void* potentialObject);

/** Get the type of object at the specified pointer.
 *
 * Note: This only checks that the pointers for isa and superclass check out.
 *       You should also call ksobjc_className() to be sure it really is valid.
 *       This method doesn't call it automatically because ksobjc_className()
 *       is potentially expensive.
 *
 * @param potentialClass The pointer to test.
 *
 * @return The kind of object, or kObjCObjectTypeNone if it couldn't be determined.
 */
ObjCObjectType ksobjc_objectType(void* address);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSObjC_h
