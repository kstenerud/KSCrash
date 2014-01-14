//
//  Demangle.h
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

#ifndef HDR_Demangle_H
#define HDR_Demangle_H

#ifdef __cplusplus
extern "C" {
#endif


#include <sys/types.h>


#define DEMANGLE_STATUS_SUCCESS 0
#define DEMANGLE_STATUS_ALLOC_FAILURE -1
#define DEMANGLE_STATUS_INVALID_NAME -2
#define DEMANGLE_STATUS_INVALID_ARG -3
#define DEMANGLE_STATUS_TOO_SMALL -4


/**
 * C interface to the C++ ABI's cxa_demangle.
 *
 * @param mangled_name A NUL-terminated character string containing the name to be demangled.
 * @param output_buffer A region of memory, allocated with malloc, of *length bytes, into which
 *                      the demangled name is stored. If output_buffer is not long enough, it is
 *                      expanded using realloc. output_buffer may instead be NULL; in that case,
 *                      the demangled name is placed in a region of memory allocated with malloc.
 * @param length If length is non-NULL, the length of the buffer containing the demangled name is
 *               placed in *length.
 * @param status *status is set to one of the following values:
 *                   0: The demangling operation succeeded.
 *                  -1: A memory allocation failiure occurred.
 *                  -2: mangled_name is not a valid name under the C++ ABI mangling rules.
 *                  -3: One of the arguments is invalid.
 * @return A pointer to the start of the NUL-terminated demangled name, or NULL if the demangling
 *         fails. The caller is responsible for deallocating this memory using free.
 */
char* cpp_demangle(const char* mangled_name, char* output_buffer, size_t* length, int* status);

/**
 * Demangle in an async-safe manner.
 * This function will only demangle if the output buffer is large enough to hold the
 * demangled name. In this case, it just checks to make sure the output buffer is
 * at least as long as the mangled name.
 *
 * @param mangled_name A null-terminated character string containing the name to be demangled.
 * @param output_buffer Buffer to store the demangled name.
 * @param buffer_length The length of the output buffer.
 * @return True if demangling was successful.
 * @return One of the following values:
 *          0: The demangling operation succeeded.
 *         -1: A memory allocation failiure occurred.
 *         -2: mangled_name is not a valid name under the C++ ABI mangling rules.
 *         -3: One of the arguments is invalid.
 *         -4: The buffer was not big enough to hold the demangled name.
 */
bool safe_demangle(const char* mangled_name, char* output_buffer, size_t buffer_length);


#ifdef __cplusplus
}
#endif

#endif // HDR_Demangle_H
