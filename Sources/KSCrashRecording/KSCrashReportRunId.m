//
//  KSCrashReportRunId.m
//
//  Created by Alexander Cohen on 2026-02-19.
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
#import "KSJSONCodecObjC.h"

#import <Foundation/Foundation.h>
#import <uuid/uuid.h>

bool kscrs_extractRunIdFromReport(const char *report, char *runIdBuffer, size_t bufferLength)
{
    if (report == NULL || runIdBuffer == NULL || bufferLength == 0) {
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

        NSString *runId = reportSection[KSCrashField_RunID];
        if (![runId isKindOfClass:[NSString class]] || runId.length == 0) {
            return false;
        }

        if (![runId getCString:runIdBuffer maxLength:bufferLength encoding:NSUTF8StringEncoding]) {
            return false;
        }

        // Defense-in-depth: run_id is used as a path component, so reject anything
        // that isn't a valid UUID to prevent path traversal via crafted report JSON.
        // uuid_parse returns -1 for any non-UUID string; NULL input is UB but
        // runIdBuffer is guaranteed non-NULL and null-terminated by getCString above.
        uuid_t unused;
        if (uuid_parse(runIdBuffer, unused) != 0) {
            runIdBuffer[0] = '\0';
            return false;
        }
        return true;
    }
}
