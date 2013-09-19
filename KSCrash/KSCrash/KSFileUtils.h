//
//  KSFileUtils.h
//
//  Created by Karl Stenerud on 2012-01-28.
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


/* Basic file reading/writing functions.
 */


#ifndef HDR_KSFileUtils_h
#define HDR_KSFileUtils_h

#ifdef __cplusplus
extern "C" {
#endif


#include <stdbool.h>
#include <stdarg.h>
#include <sys/types.h>


/** Get the last entry in a file path. Assumes UNIX style separators.
 *
 * @param path The file path.
 *
 * @return the last entry in the path.
 */
const char* ksfu_lastPathEntry(const char* path);

/** Write bytes to a file descriptor.
 *
 * @param fd The file descriptor.
 *
 * @param bytes Buffer containing the bytes.
 *
 * @param length The number of bytes to write.
 *
 * @return true if the operation was successful.
 */
bool ksfu_writeBytesToFD(const int fd, const char* bytes, ssize_t length);

/** Read bytes from a file descriptor.
 *
 * @param fd The file descriptor.
 *
 * @param bytes Buffer to store the bytes in.
 *
 * @param length The number of bytes to read.
 *
 * @return true if the operation was successful.
 */
bool ksfu_readBytesFromFD(const int fd, char* bytes, ssize_t length);

/** Read an entire file.
 *
 * @param path The path to the file.
 *
 * @param data Place to store a pointer to the loaded data (must be freed).
 *
 * @param length Place to store the length of the loaded data.
 *
 * @return true if the operation was successful.
 */
bool ksfu_readEntireFile(const char* path, char** data, size_t* length);

/** Write a string to a file.
 *
 * @param fd The file descriptor.
 *
 * @param string The string to write.
 *
 * @return true if successful.
 */
bool ksfu_writeStringToFD(const int fd, const char* string);

/** Write a formatted string to a file.
 *
 * @param fd The file descriptor.
 *
 * @param fmt The format specifier, followed by its arguments.
 *
 * @return true if successful.
 */
bool ksfu_writeFmtToFD(const int fd, const char* fmt, ...);

/** Write a formatted string to a file.
 *
 * @param fd The file descriptor.
 *
 * @param fmt The format specifier.
 *
 * @param args The arguments list.
 *
 * @return true if successful.
 */
bool ksfu_writeFmtArgsToFD(const int fd, const char* fmt, va_list args);

/** Read a single line from a file.
 *
 * @param fd The file descriptor.
 *
 * @param buffer The buffer to read into.
 *
 * @param maxLength The maximum length to read.
 *
 * @return The number of bytes read.
 */
ssize_t ksfu_readLineFromFD(const int fd, char* buffer, int maxLength);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSFileUtils_h
