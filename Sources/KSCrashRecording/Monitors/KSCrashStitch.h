//
//  KSCrashStitch.h
//
//  Created by Alexander Cohen on 2026-10-03.
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

/* Helpers the built-in stitchers share, so each one says what it adds to a
 * report and not how the createStitchedReport contract is kept.
 */

#ifndef HDR_KSCrashStitch_h
#define HDR_KSCrashStitch_h

#import <Foundation/Foundation.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/** The createStitchedReport contract for a stitcher that reads one sidecar.
 *
 *  Another scope than `stitchedScope` returns the report unchanged. A read the
 *  environment failed returns nil, the slot's retry signal. A sidecar that is
 *  gone or corrupt never reads better, so the report is returned unchanged and
 *  delivers without it. Otherwise `edit` changes a mutable copy of the report,
 *  which is returned. The reader logs its own failures.
 *
 * @param report The report as stitched so far. Never modified.
 * @param sidecarPath The sidecar to read, as the slot received it. NULL in the
 *                    final pass, which has no sidecar.
 * @param scope The scope the slot was called for.
 * @param stitchedScope The one scope this stitcher reads a sidecar in; every
 *                      other scope leaves the report as it is.
 * @param read Reads the sidecar at `path` into the caller's own storage and
 *             says how it went. Called once, only in `stitchedScope`. Holds
 *             on to anything `edit` must release only when it returns OK.
 * @param edit Adds what was read to the mutable copy of the report it is
 *             handed. Always called exactly once after `read` returns OK, and
 *             never otherwise, so it can release what `read` acquired.
 *
 * @return A copy of the report that `edit` changed, after a read that returned
 *         OK; `report` itself for another scope, or when the sidecar is gone
 *         or corrupt; or nil, the slot's retry signal (a read the environment
 *         failed, or no report or sidecar path to work with).
 */
// clang-format off
NSDictionary *ksstitch_stitchedReport(NSDictionary *report,
                                      const char *sidecarPath,
                                      KSCrashSidecarScope scope,
                                      KSCrashSidecarScope stitchedScope,
                                      KSCrashSidecarReadResult (^NS_NOESCAPE read)(const char *path),
                                      void (^NS_NOESCAPE edit)(NSMutableDictionary *report));
// clang-format on

/** Finds or creates the object a stitcher writes into.
 *
 * @param parent The object that holds it. Changed in place: the returned
 *               object is stored back under `key`.
 * @param key The key it lives under.
 *
 * @return A mutable copy of the object at `key`, or a new empty one when
 *         `parent` holds no object there (absent, or a value of another kind,
 *         which it replaces).
 */
NSMutableDictionary *ksstitch_object(NSMutableDictionary *parent, NSString *key);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashStitch_h
