//
//  KSCrashMonitor_CPPException+Private.h
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

#ifndef HDR_KSCrashMonitor_CPPException_Private_h
#define HDR_KSCrashMonitor_CPPException_Private_h

#ifdef __cplusplus

#include <typeinfo>

#include "KSSystemCapabilities.h"

#if KSCRASH_HAS_OBJC
#if defined(__has_include)
#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#define KSCRASH_CPP_EXCEPTION_HAS_PTRAUTH 1
#endif
#endif
#ifndef KSCRASH_CPP_EXCEPTION_HAS_PTRAUTH
#define KSCRASH_CPP_EXCEPTION_HAS_PTRAUTH 0
#endif

// The ObjC runtime uses a custom C++ type_info subclass (objc_typeinfo) for all Objective-C exceptions. Its vtable
// pointer is set to objc_ehtype_vtable + 2 (the +2 skips the Itanium C++ ABI vtable prefix: offset-to-top and RTTI
// pointer).
//
// objc_typeinfo struct definition:
// https://github.com/apple-oss-distributions/objc4/blob/fb265098/runtime/objc-exception.mm#L313-L320
//
// objc_ehtype_vtable is exported from libobjc on Apple platforms and declared in Apple's internal objc-abi.h:
// https://github.com/apple-oss-distributions/objc4/blob/fb265098/runtime/objc-abi.h#L377-L380
extern "C" const void *const objc_ehtype_vtable[];

static inline const void *kscm_cppexception_stripCxxVTablePointer(const void *pointer)
{
#if KSCRASH_CPP_EXCEPTION_HAS_PTRAUTH
    return ptrauth_strip(pointer, ptrauth_key_cxx_vtable_pointer);
#else
    return pointer;
#endif
}
#endif  // KSCRASH_HAS_OBJC

// Check if a C++ exception type_info represents an Objective-C exception.
static inline bool kscm_cppexception_isObjCException(const std::type_info *tinfo)
{
#if KSCRASH_HAS_OBJC
    if (tinfo == nullptr) {
        return false;
    }

    // The first pointer-sized field in any type_info object is the vtable pointer.
    const void *tinfoVTable = *reinterpret_cast<const void *const *>(tinfo);
    const void *objcVTable = reinterpret_cast<const void *>(objc_ehtype_vtable + 2);

    // On arm64e, vtable pointers are signed with pointer authentication codes (PAC). Strip the signatures before
    // comparing so the raw objc_ehtype_vtable address can match the signed pointer stored in tinfo.
    return kscm_cppexception_stripCxxVTablePointer(tinfoVTable) == kscm_cppexception_stripCxxVTablePointer(objcVTable);
#else
    (void)tinfo;
    return false;
#endif
}

#endif  // __cplusplus

#endif  // HDR_KSCrashMonitor_CPPException_Private_h
