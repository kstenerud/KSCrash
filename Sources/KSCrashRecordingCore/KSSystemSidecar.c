//
//  KSSystemSidecar.c
//
//  Created by Alexander Cohen on 2026-09-28.
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

#include "KSSystemSidecar.h"

KSCrashSidecarReadResult kssidecar_readSystem(const char *path, KSCrash_SystemData *out)
{
    static const size_t sizes[] = { KSCrash_System_V1Size, KSCrash_System_V2Size };
    _Static_assert(sizeof(sizes) / sizeof(sizes[0]) == KSCrash_System_CurrentVersion, "one size per system version");
    static const KSSidecarFormat format = { KSSYS_MAGIC, sizes, KSCrash_System_CurrentVersion };
    return kssidecar_read(&format, path, out, sizeof(*out));
}
