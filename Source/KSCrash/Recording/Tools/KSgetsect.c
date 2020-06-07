//
//  KSgetsect.c
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
// Modification of getsegbyname.c
// https://opensource.apple.com/source/cctools/cctools-921/libmacho/getsegbyname.c.auto.html
// Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
//
// @APPLE_LICENSE_HEADER_START@
//
// This file contains Original Code and/or Modifications of Original Code
// as defined in and that are subject to the Apple Public Source License
// Version 2.0 (the 'License'). You may not use this file except in
// compliance with the License. Please obtain a copy of the License at
// http://www.opensource.apple.com/apsl/ and read it before using this
// file.
//
// The Original Code and all software distributed under the License are
// distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
// EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
// INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
// Please see the License for the specific language governing rights and
// limitations under the License.
//
// @APPLE_LICENSE_HEADER_END@
//

#include "KSgetsect.h"
#include <string.h>

#ifndef __LP64__
const struct segment_command *ksgs_getsegbynamefromheader(const struct mach_header *mhp, char *segname)
{
    struct segment_command *sgp;
    uint32_t i;

    sgp = (struct segment_command *) ((char *) mhp + sizeof(struct mach_header));
    for (i = 0; i < mhp->ncmds; i++)
    {
        if (sgp->cmd == LC_SEGMENT)
        {
            if (strncmp(sgp->segname, segname, sizeof(sgp->segname)) == 0)
            {
                return sgp;
            }
        }
        sgp = (struct segment_command *) ((char *) sgp + sgp->cmdsize);
    }
    return NULL;
}
#else /* defined(__LP64__) */
const struct segment_command_64 *ksgs_getsegbynamefromheader(const struct mach_header_64 *mhp, char *segname)
{
    struct segment_command_64 *sgp;
    uint32_t i;

    sgp = (struct segment_command_64 *) ((char *) mhp + sizeof(struct mach_header_64));
    for (i = 0; i < mhp->ncmds; i++)
    {
        if (sgp->cmd == LC_SEGMENT_64)
        {
            if (strncmp(sgp->segname, segname, sizeof(sgp->segname)) == 0)
            {
                return sgp;
            }
        }
        sgp = (struct segment_command_64 *) ((char *) sgp + sgp->cmdsize);
    }
    return NULL;
}
#endif /* defined(__LP64__) */
