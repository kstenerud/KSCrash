//
//  KSCxaThrowSwapper.h
//
//  Copyright (c) 2019 YANDEX LLC. All rights reserved.
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

#ifndef KSCxaThrowSwapper_h
#define KSCxaThrowSwapper_h

#include "KSCrashNamespace.h"

#ifdef __cplusplus

#include <typeinfo>

extern "C" {

typedef std::type_info ksct_type_info;
#else
typedef void ksct_type_info;
#endif

typedef void (*ksct_destructor)(void *);
typedef ksct_destructor (*ksct_filter)(void *, ksct_type_info *, ksct_destructor);
/** Install a throw filter. Its return value becomes the exception's destructor. Return the original
 * unchanged, or a replacement that calls the original exactly once if it was non-NULL.
 */
int ksct_swap(ksct_filter filter);
void ksct_swapReset(void);

#ifdef __cplusplus
}
#endif

#endif /* KSCxaThrowSwapper_h */
