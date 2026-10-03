//
//  KSCrashStitch.m
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

#import "KSCrashStitch.h"

NSDictionary *ksstitch_stitchedReport(NSDictionary *report, const char *sidecarPath, KSCrashSidecarScope scope,
                                      KSCrashSidecarScope stitchedScope,
                                      KSCrashSidecarReadResult (^NS_NOESCAPE read)(const char *path),
                                      void (^NS_NOESCAPE edit)(NSMutableDictionary *report))
{
    if (report == nil) {
        return nil;
    }
    if (scope != stitchedScope) {
        // Not this stitcher's scope (the final pass reaches every stitcher, with no sidecar).
        return report;
    }
    if (sidecarPath == NULL) {
        return nil;
    }
    KSCrashSidecarReadResult result = read(sidecarPath);
    if (result == KSCrashSidecarReadFailure) {
        return nil;
    }
    if (result != KSCrashSidecarReadOK) {
        // nil is not free: it keeps the report from being finalized, and on the
        // hang-recovery path the watchdog deletes a report whose finalization
        // fails. A sidecar no later read can make sense of is not worth that.
        return report;
    }
    NSMutableDictionary *edited = [report mutableCopy];
    edit(edited);
    return edited;
}

NSMutableDictionary *ksstitch_object(NSMutableDictionary *parent, NSString *key)
{
    id existing = parent[key];
    NSMutableDictionary *object =
        [existing isKindOfClass:[NSDictionary class]] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
    parent[key] = object;
    return object;
}
