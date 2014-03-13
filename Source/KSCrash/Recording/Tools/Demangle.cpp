//
//  Demangle.cpp
//
//  Created by Karl Stenerud on 2013-10-02.
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

#include "Demangle.h"
#include <cxxabi.h>
#include <string.h>
#include "KSLogger.h"

char* cpp_demangle(const char* mangled_name, char* output_buffer, size_t* length, int* status)
{
    return __cxxabiv1::__cxa_demangle(mangled_name, output_buffer, length, status);
}

bool safe_demangle(const char* mangled_name, char* output_buffer, size_t buffer_length)
{
    size_t mangled_length = strlen(mangled_name);
    if(mangled_length < buffer_length)
    {
        size_t length = buffer_length;
        int status = DEMANGLE_STATUS_SUCCESS;
        __cxxabiv1::__cxa_demangle(mangled_name, output_buffer, &length, &status);
        return status;
    }
    return DEMANGLE_STATUS_TOO_SMALL;
}
