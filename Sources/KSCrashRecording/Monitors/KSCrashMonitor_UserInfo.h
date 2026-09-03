//
//  KSCrashMonitor_UserInfo.h
//
//  Created by Alexander Cohen on 2026-03-01.
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

/**
 * @file KSCrashMonitor_UserInfo.h
 * @brief Delivery-time stitching of the run's user metadata sidecar.
 *
 * The live store is owned by the Swift metadata layer, which writes the
 * UserInfo run sidecar as keys change. This monitor only stitches: at report
 * delivery it reads that sidecar, resolves last-write-wins per key, and
 * merges the result into the report's "user" section.
 */

#ifndef HDR_KSCrashMonitor_UserInfo_h
#define HDR_KSCrashMonitor_UserInfo_h

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Access the Monitor API. */
KSCrashMonitorAPI *kscm_userinfo_getAPI(void);

/** Stitch user info sidecar data into a report at delivery time.
 *  See KSCrashMonitorAPI.h createStitchedReport for the full contract.
 */
CFDictionaryRef kscm_userinfo_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                   KSCrashSidecarScope scope, void *context);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashMonitor_UserInfo_h
