//
//  KSCrashReportMemoryIntrospection.h
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

/** Memory introspection utilities for crash report writing.
 *
 * These functions are used to inspect memory contents and write detailed
 * information about memory addresses to crash reports.
 */

#ifndef HDR_KSCrashReportMemoryIntrospection_h
#define HDR_KSCrashReportMemoryIntrospection_h

#include <stdbool.h>
#include <stdint.h>

#include "KSCrashReportWriter.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Default depth for memory search when following references. */
#define kDefaultMemorySearchDepth 15

/** Minimum string length to consider a memory region a valid string. */
#define kMinStringLength 4

/** Enable or disable memory introspection during crash reporting.
 *
 * @param shouldIntrospectMemory true to enable introspection.
 */
void kscrmi_setIntrospectMemory(bool shouldIntrospectMemory);

/** Check if memory introspection is enabled.
 *
 * @return true if memory introspection is enabled.
 */
bool kscrmi_isIntrospectionEnabled(void);

/** Set the classes that should not have their ivars introspected.
 *
 * @param doNotIntrospectClasses An array of class names.
 *
 * @param length The length of the array.
 */
void kscrmi_setDoNotIntrospectClasses(const char **doNotIntrospectClasses, int length);

/** Check if a memory address points to a valid null terminated UTF-8 string.
 *
 * @param address The address to check.
 *
 * @return true if the address points to a string.
 */
bool kscrmi_isValidString(const void *address);

/** Check if an address is valid for reading.
 *
 * @param address The address to check.
 *
 * @return true if the address is valid.
 */
bool kscrmi_isValidPointer(uintptr_t address);

/** Check if an address points to notable content worth reporting.
 *
 * @param address The address to check.
 *
 * @return true if the address points to notable content.
 */
bool kscrmi_isNotableAddress(uintptr_t address);

/** Write the contents of a memory location.
 * Also writes meta information about the data.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param address The memory address.
 *
 * @param limit How many more subreferenced objects to write, if any.
 */
void kscrmi_writeMemoryContents(const KSCrashReportWriter *writer, const char *key, uintptr_t address, int *limit);

/** Write memory contents only if the address is notable.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param address The memory address.
 */
void kscrmi_writeMemoryContentsIfNotable(const KSCrashReportWriter *writer, const char *key, uintptr_t address);

/** Look for a hex value in a string and try to write whatever it references.
 *
 * @param writer The writer.
 *
 * @param key The object key, if needed.
 *
 * @param string The string to search.
 */
void kscrmi_writeAddressReferencedByString(const KSCrashReportWriter *writer, const char *key, const char *string);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashReportMemoryIntrospection_h
