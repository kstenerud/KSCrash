//
//  KSDemangle_Swift.cc
//
//  Created by Karl Stenerud on 2016-11-04.
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

#include "KSDemangle_Swift.h"

#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

/// https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/Demangle.cpp#L987
/// Demangles a Swift symbol name.
///
/// \param mangledName is the symbol name that needs to be demangled.
/// \param mangledNameLength is the length of the string that should be
/// demangled.
/// \param outputBuffer is the user provided buffer where the demangled name
/// will be placed. If nullptr, a new buffer will be malloced. In that case,
/// the user of this API is responsible for freeing the returned buffer.
/// \param outputBufferSize is the size of the output buffer. If the demangled
/// name does not fit into the outputBuffer, the output will be truncated and
/// the size will be updated, indicating how large the buffer should be.
/// \param flags can be used to select the demangling style. TODO: We should
//// define what these will be.
/// \returns the demangled name. Returns nullptr if the input String is not a
/// Swift mangled name.
typedef char *(swift_demangle_func)(const char *mangledName,
                                    size_t mangledNameLength,
                                    char *outputBuffer,
                                    size_t *outputBufferSize,
                                    uint32_t flags);

static char* default_swift_demangle(__unused const char *mangledName,
                                    __unused size_t mangledNameLength,
                                    __unused char *outputBuffer,
                                    __unused size_t *outputBufferSize,
                                    __unused uint32_t flags) {
    return nullptr;
}

static swift_demangle_func* swift_demangle = nullptr;

extern "C" char *ksdm_demangleSwift(const char *mangledSymbol)
{
    if (swift_demangle == nullptr) {
        void* handle = dlopen(NULL, RTLD_NOW);
        if (handle != nullptr) {
            void* symbol = dlsym(handle, "swift_demangle");
            if(symbol != nullptr) {
                swift_demangle = (swift_demangle_func*)symbol;
            } else {
                swift_demangle = default_swift_demangle;
            }
            dlclose(handle);
        }
    }

    size_t outputBufferSize = 0;
    return swift_demangle(mangledSymbol, strlen(mangledSymbol), nullptr, &outputBufferSize, 0);
}
