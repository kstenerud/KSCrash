//
//  KSCPU.h
//
//  Created by Karl Stenerud on 2012-01-29.
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

#include "KSCPU.h"

#include <mach-o/arch.h>
#include <mach/mach.h>

#include "KSSystemCapabilities.h"

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000  // Xcode 14
#include <mach-o/utils.h>
#define _HAS_MACH_O_UTILS 1
#else
#define _HAS_MACH_O_UTILS 0
#endif

// #define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#if !_HAS_MACH_O_UTILS || !KSCRASH_HOST_VISION
static inline const char *currentArch_nx(void)
{
    const NXArchInfo *archInfo = NXGetLocalArchInfo();
    return archInfo == NULL ? NULL : archInfo->name;
}

static inline const char *archForCPU_nx(cpu_type_t majorCode, cpu_subtype_t minorCode)
{
    const NXArchInfo *info = NXGetArchInfoFromCpuType(majorCode, minorCode);
    return info == NULL ? NULL : info->name;
}
#endif

const char *kscpu_currentArch(void)
{
#if _HAS_MACH_O_UTILS
#if !KSCRASH_HOST_VISION
    if (__builtin_available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 8.0, *))
#endif
    {
        return macho_arch_name_for_mach_header(NULL);
    }
#if !KSCRASH_HOST_VISION
    else {
        return currentArch_nx();
    }
#endif
#else   // _HAS_MACH_O_UTILS
    return currentArch_nx();
#endif  // _HAS_MACH_O_UTILS
}

const char *kscpu_archForCPU(cpu_type_t majorCode, cpu_subtype_t minorCode)
{
#if _HAS_MACH_O_UTILS
#if !KSCRASH_HOST_VISION
    if (__builtin_available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 8.0, *))
#endif
    {
        return macho_arch_name_for_cpu_type(majorCode, minorCode);
    }
#if !KSCRASH_HOST_VISION
    else {
        return archForCPU_nx(majorCode, minorCode);
    }
#endif
#else   // _HAS_MACH_O_UTILS
    return archForCPU_nx(majorCode, minorCode);
#endif  // _HAS_MACH_O_UTILS
}

#if KSCRASH_HAS_THREADS_API
bool kscpu_i_fillState(const thread_t thread, const thread_state_t state, const thread_state_flavor_t flavor,
                       const mach_msg_type_number_t stateCount)
{
    KSLOG_TRACE("Filling thread state with flavor %x.", flavor);
    mach_msg_type_number_t stateCountBuff = stateCount;
    kern_return_t kr;

    kr = thread_get_state(thread, flavor, state, &stateCountBuff);
    if (kr != KERN_SUCCESS) {
        KSLOG_ERROR("thread_get_state: %s", mach_error_string(kr));
        return false;
    }
    return true;
}
#else
bool kscpu_i_fillState(__unused const thread_t thread, __unused const thread_state_t state,
                       __unused const thread_state_flavor_t flavor, __unused const mach_msg_type_number_t stateCount)
{
    return false;
}

#endif
