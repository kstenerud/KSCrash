//
//  KSExcResource.h
//
//  Created by Alexander Cohen on 2026-04-09.
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

// EXC_RESOURCE encoding/decoding for CPU monitor exceptions.
//
// The kernel header kern/exc_resource.h defines decode macros but is only
// available in the macOS SDK (not iOS/tvOS/watchOS). We provide our own
// encode and decode macros matching the documented bit layout:
//
//   code:  [63:61] resource type | [60:58] flavor | [31:7] interval (sec) | [6:0] limit (%)
//   subcode: [6:0] observed (%)

#ifndef KSExcResource_h
#define KSExcResource_h

#include <stdint.h>

// Resource types
#ifndef RESOURCE_TYPE_CPU
#define RESOURCE_TYPE_CPU 1
#endif

// CPU monitor flavors
#ifndef FLAVOR_CPU_MONITOR
#define FLAVOR_CPU_MONITOR 1
#define FLAVOR_CPU_MONITOR_FATAL 2
#endif

// Decode
#ifndef EXC_RESOURCE_CPUMONITOR_DECODE_PERCENTAGE
#define EXC_RESOURCE_CPUMONITOR_DECODE_INTERVAL(code) (((code) >> 7) & 0x1FFFFFFULL)
#define EXC_RESOURCE_CPUMONITOR_DECODE_PERCENTAGE(code) ((code) & 0x7FULL)
#define EXC_RESOURCE_CPUMONITOR_DECODE_PERCENTAGE_OBSERVED(subcode) ((subcode) & 0x7FULL)
#endif

// Encode
#define KSEXC_RESOURCE_CPU_ENCODE_CODE(resourceType, flavor, intervalSec, limitPct) \
    ((int64_t)(((uint64_t)(resourceType) << 61) | ((uint64_t)(flavor) << 58) |      \
               (((uint64_t)(intervalSec) & 0x1FFFFFFULL) << 7) | ((uint64_t)(limitPct) & 0x7FULL)))

#define KSEXC_RESOURCE_CPU_ENCODE_SUBCODE(observedPct) ((int64_t)((uint64_t)(observedPct) & 0x7FULL))

#endif  // KSExcResource_h
