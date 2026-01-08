//
//  KSCrashSystemInfo.h
//
//  Created by Alexander Cohen on 2026-01-07.
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

#ifndef KSCrashSystemInfo_h
#define KSCrashSystemInfo_h

#include <stdint.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Set storage info (called by DiscSpace monitor).
 */
void kscm_system_setStorageInfo(uint64_t storageSize, uint64_t freeStorageSize);

/** Set boot time (called by BootTime monitor).
 */
void kscm_system_setBootTime(const char *bootTime);

/** Get boot time string for testing.
 */
const char *kscm_system_getBootTime(void);

/** Get storage size for testing.
 */
uint64_t kscm_system_getStorageSize(void);

#ifdef __cplusplus
}
#endif

#endif  // KSCrashSystemInfo_h
