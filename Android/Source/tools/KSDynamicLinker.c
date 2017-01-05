//
//  KSDynamicLinker.c
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

#include "KSDynamicLinker.h"

#include <limits.h>
#include <string.h>

#include "KSLogger.h"


uint32_t ksdl_imageNamed(const char* const imageName, bool exactMatch)
{
    // TODO
    return UINT32_MAX;
}

const uint8_t* ksdl_imageUUID(const char* const imageName, bool exactMatch)
{
    // TODO
    return NULL;
}

bool ksdl_dladdr(const uintptr_t address, Dl_info* const info)
{
    return dladdr((void*)address, info);
}

int ksdl_imageCount()
{
    // TODO
    return 0;
}

bool ksdl_getBinaryImage(int index, KSBinaryImage* buffer)
{
    // TODO
    return false;
}
