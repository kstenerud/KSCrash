//
//  KSCrashReportFinalizer.m
//
//  Created by Alexander Cohen on 2026-03-21.
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

#import "KSCrashReportStoreC+Private.h"

#import "KSCrashReportFields.h"
#import "KSFileUtils.h"
#import "KSJSONCodecObjC.h"
#import "KSLogger.h"

#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <sys/param.h>
#include <unistd.h>

// Check report.report.finalized by parsing the JSON properly.
// Less efficient than a byte scan, but correct regardless of key ordering
// or user payload contents. The stitch pipeline refactor will eliminate
// this extra parse by checking the already-decoded dict directly.
bool kscrs_isReportFinalized(const char *report)
{
    if (report == NULL) {
        return false;
    }
    @autoreleasepool {
        NSData *data = [NSData dataWithBytesNoCopy:(void *)report length:strlen(report) freeWhenDone:NO];
        NSDictionary *decoded = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
        if (![decoded isKindOfClass:[NSDictionary class]]) {
            return false;
        }
        id reportSection = decoded[KSCrashField_Report];
        if (![reportSection isKindOfClass:[NSDictionary class]]) {
            return false;
        }
        id val = reportSection[KSCrashField_Finalized];
        if ([val isKindOfClass:[NSNumber class]]) {
            return [val boolValue];
        }
        return false;
    }
}

// Decode a stitched report, inject report.report.finalized = true,
// and re-encode with pretty printing. Returns a new malloc'd string,
// or NULL on failure. Caller must free the result.
//
// The extra decode/encode round-trip here will be eliminated by the
// stitch pipeline refactor, which will pass the already-decoded dict.
char *kscrs_injectFinalizedFlag(const char *stitchedReport)
{
    if (stitchedReport == NULL) {
        return NULL;
    }

    @autoreleasepool {
        NSData *data = [NSData dataWithBytesNoCopy:(void *)stitchedReport
                                            length:strlen(stitchedReport)
                                      freeWhenDone:NO];
        NSDictionary *decoded = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
        if (![decoded isKindOfClass:[NSDictionary class]]) {
            KSLOG_ERROR(@"Failed to decode report JSON for finalization");
            return NULL;
        }
        NSMutableDictionary *dict = [decoded mutableCopy];

        id reportSection = dict[KSCrashField_Report];
        NSMutableDictionary *reportDict;
        if ([reportSection isKindOfClass:[NSDictionary class]]) {
            reportDict = [reportSection mutableCopy];
        } else {
            reportDict = [NSMutableDictionary dictionary];
        }
        reportDict[KSCrashField_Finalized] = @YES;
        dict[KSCrashField_Report] = reportDict;

        NSError *error = nil;
        NSData *encoded = [KSJSONCodec encode:dict options:KSJSONEncodeOptionPretty error:&error];
        if (!encoded) {
            KSLOG_ERROR(@"Failed to encode finalized report: %@", error);
            return NULL;
        }

        char *result = (char *)malloc(encoded.length + 1);
        if (!result) {
            return NULL;
        }
        memcpy(result, encoded.bytes, encoded.length);
        result[encoded.length] = '\0';
        return result;
    }
}
