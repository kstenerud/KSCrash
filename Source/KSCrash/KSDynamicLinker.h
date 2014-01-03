//
//  KSDynamicLinker.h
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

#ifndef HDR_KSDynamicLinker_h
#define HDR_KSDynamicLinker_h

#ifdef __cplusplus
extern "C" {
#endif


#include <dlfcn.h>
#include <mach-o/dyld.h>


/** Find a loaded binary image with the specified name.
 *
 * @param imageName The image name to look for.
 *
 * @param exactMatch If true, look for an exact match instead of a partial one.
 *
 * @return the index of the matched image, or UINT32_MAX if not found.
 */
uint32_t ksdl_imageNamed(const char* const imageName, bool exactMatch);

/** Get the UUID of a loaded binary image with the specified name.
 *
 * @param imageName The image name to look for.
 *
 * @param exactMatch If true, look for an exact match instead of a partial one.
 *
 * @return A pointer to the binary (16 byte) UUID of the image, or NULL if it
 *         wasn't found.
 */
const uint8_t* ksdl_imageUUID(const char* const imageName, bool exactMatch);

/** Get the address of the first command following a header (which will be of
 * type struct load_command).
 *
 * @param header The header to get commands for.
 *
 * @return The address of the first command, or NULL if none was found (which
 *         should not happen unless the header or image is corrupt).
 */
uintptr_t ksdl_firstCmdAfterHeader(const struct mach_header* header);

/** Get the image index that the specified address is part of.
 *
 * @param address The address to examine.
 * @return The index of the image it is part of, or UINT_MAX if none was found.
 */
uint32_t ksdl_imageIndexContainingAddress(const uintptr_t address);

/** Get the segment base address of the specified image.
 *
 * This is required for any symtab command offsets.
 *
 * @param index The image index.
 * @return The image's base address, or 0 if none was found.
 */
uintptr_t ksdl_segmentBaseOfImageIndex(const uint32_t idx);

/** async-safe version of dladdr.
 *
 * This method searches the dynamic loader for information about any image
 * containing the specified address. It may not be entirely successful in
 * finding information, in which case any fields it could not find will be set
 * to NULL.
 *
 * Unlike dladdr(), this method does not make use of locks, and does not call
 * async-unsafe functions.
 *
 * @param address The address to search for.
 * @param info Gets filled out by this function.
 * @return true if at least some information was found.
 */
bool ksdl_dladdr(const uintptr_t address, Dl_info* const info);

/** Get the address of a symbol in the specified image.
 *
 * @param imageIdx The index of the image to search.
 * @param symbolName The symbol to search for.
 * @return The address of the symbol or NULL if not found.
 */
const void* ksdl_getSymbolAddrInImage(uint32_t imageIdx, const char* symbolName);

/** Get the address of a symbol in any image.
 * Searches all images starting at index 0.
 *
 * @param symbolName The symbol to search for.
 * @return The address of the symbol or NULL if not found.
 */
const void* ksdl_getSymbolAddrInAnyImage(const char* symbolName);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSDynamicLinker_h
