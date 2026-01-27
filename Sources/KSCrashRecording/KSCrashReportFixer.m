//
//  KSCrashReportFixer.m
//
//  Created by Karl Stenerud on 2016-11-07.
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

#import "KSCrashReportFixer.h"

#import <Foundation/Foundation.h>

#import "KSCrashReportFields.h"
#import "KSJSONCodecObjC.h"
#import "KSLogger.h"

#pragma mark - Version Parsing

static void parseVersion(NSString *versionString, int *major, int *minor, int *patch)
{
    *major = 0;
    *minor = 0;
    *patch = 0;

    if (versionString == nil) {
        return;
    }

    NSArray *parts = [versionString componentsSeparatedByString:@"."];
    if (parts.count > 0) {
        *major = [parts[0] intValue];
    }
    if (parts.count > 1) {
        *minor = [parts[1] intValue];
    }
    if (parts.count > 2) {
        *patch = [parts[2] intValue];
    }
}

static BOOL isVersionAtLeast(int major, int minor, int patch, int reqMajor, int reqMinor, int reqPatch)
{
    if (major > reqMajor) return YES;
    if (major < reqMajor) return NO;
    if (minor > reqMinor) return YES;
    if (minor < reqMinor) return NO;
    return patch >= reqPatch;
}

#pragma mark - Date Formatting

static NSString *dateStringFromMicroseconds(int64_t microseconds)
{
    // Extract seconds and microseconds parts
    time_t seconds = (time_t)(microseconds / 1000000);
    long micros = (long)(microseconds % 1000000);

    struct tm result = { 0 };
    if (gmtime_r(&seconds, &result) == NULL) {
        return nil;
    }

    // Format: yyyy-MM-ddTHH:mm:ss.xxxxxxZ (6 decimal places for microseconds)
    return [NSString stringWithFormat:@"%04d-%02d-%02dT%02d:%02d:%02d.%06ldZ", result.tm_year + 1900, result.tm_mon + 1,
                                      result.tm_mday, result.tm_hour, result.tm_min, result.tm_sec, micros];
}

static NSString *dateStringFromTimestamp(int64_t timestamp)
{
    time_t seconds = (time_t)timestamp;

    struct tm result = { 0 };
    if (gmtime_r(&seconds, &result) == NULL) {
        return nil;
    }

    // Format: yyyy-MM-ddTHH:mm:ssZ
    return [NSString stringWithFormat:@"%04d-%02d-%02dT%02d:%02d:%02dZ", result.tm_year + 1900, result.tm_mon + 1,
                                      result.tm_mday, result.tm_hour, result.tm_min, result.tm_sec];
}

#pragma mark - Fixup Logic

static void fixupTimestamp(NSMutableDictionary *reportDict, BOOL useMicroseconds)
{
    if (reportDict == nil) {
        return;
    }

    id timestamp = reportDict[KSCrashField_Timestamp];
    if ([timestamp isKindOfClass:[NSNumber class]]) {
        int64_t value = [timestamp longLongValue];
        NSString *dateString;
        if (useMicroseconds) {
            dateString = dateStringFromMicroseconds(value);
        } else {
            dateString = dateStringFromTimestamp(value);
        }
        if (dateString != nil) {
            reportDict[KSCrashField_Timestamp] = dateString;
        }
    }
}

static void fixupReport(NSMutableDictionary *report)
{
    // Get version to determine timestamp format
    NSMutableDictionary *reportInfo = report[KSCrashField_Report];
    NSString *versionString = reportInfo[KSCrashField_Version];

    int major, minor, patch;
    parseVersion(versionString, &major, &minor, &patch);

    // Version 3.3.0+ uses microseconds for timestamps
    BOOL useMicroseconds = isVersionAtLeast(major, minor, patch, 3, 3, 0);

    // Fix timestamp in report
    fixupTimestamp(reportInfo, useMicroseconds);

    // Fix timestamp in recrash report if present
    NSMutableDictionary *recrash = report[KSCrashField_RecrashReport];
    if (recrash != nil) {
        NSMutableDictionary *recrashReportInfo = recrash[KSCrashField_Report];
        fixupTimestamp(recrashReportInfo, useMicroseconds);
    }
}

#pragma mark - Public C API

char *kscrf_fixupCrashReport(const char *crashReport)
{
    if (crashReport == NULL) {
        return NULL;
    }

    @autoreleasepool {
        NSData *jsonData = [NSData dataWithBytesNoCopy:(void *)crashReport length:strlen(crashReport) freeWhenDone:NO];

        NSError *error = nil;
        NSMutableDictionary *report =
            [KSJSONCodec decode:jsonData
                        options:KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject |
                                KSJSONDecodeOptionKeepPartialObject
                          error:&error];
        if (report == nil) {
            KSLOG_ERROR(@"Could not decode report for fixup: %@", error);
            return NULL;
        }

        fixupReport(report);

        NSData *outputData = [KSJSONCodec encode:report options:KSJSONEncodeOptionPretty error:&error];
        if (outputData == nil) {
            KSLOG_ERROR(@"Could not encode fixed report: %@", error);
            return NULL;
        }

        char *result = malloc(outputData.length + 1);
        if (result == NULL) {
            return NULL;
        }
        memcpy(result, outputData.bytes, outputData.length);
        result[outputData.length] = '\0';

        return result;
    }
}
