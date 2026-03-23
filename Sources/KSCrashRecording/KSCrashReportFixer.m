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
    id reportInfo = report[KSCrashField_Report];
    if (![reportInfo isKindOfClass:[NSDictionary class]]) {
        return;
    }
    id versionVal = reportInfo[KSCrashField_Version];

    // Determine timestamp format: 3.3.0+ writes microseconds, older writes seconds.
    // Missing or non-string version is treated as legacy (seconds) so that
    // numeric timestamps in user/custom reports are still normalized correctly.
    BOOL useMicroseconds = NO;
    if ([versionVal isKindOfClass:[NSString class]]) {
        int major, minor, patch;
        parseVersion(versionVal, &major, &minor, &patch);
        useMicroseconds = isVersionAtLeast(major, minor, patch, 3, 3, 0);
    }

    // Fix timestamp in report (mutableCopy because the input is immutable)
    NSMutableDictionary *mutableReportInfo = [reportInfo mutableCopy];
    fixupTimestamp(mutableReportInfo, useMicroseconds);
    report[KSCrashField_Report] = mutableReportInfo;

    // Fix timestamp in recrash report if present
    id recrash = report[KSCrashField_RecrashReport];
    if ([recrash isKindOfClass:[NSDictionary class]]) {
        id recrashReportInfo = recrash[KSCrashField_Report];
        if ([recrashReportInfo isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *mutableRecrash = [recrash mutableCopy];
            NSMutableDictionary *mutableRecrashInfo = [recrashReportInfo mutableCopy];
            fixupTimestamp(mutableRecrashInfo, useMicroseconds);
            mutableRecrash[KSCrashField_Report] = mutableRecrashInfo;
            report[KSCrashField_RecrashReport] = mutableRecrash;
        }
    }
}

#pragma mark - Public API

NSDictionary *kscrf_fixupReportDict(NSDictionary *report)
{
    NSMutableDictionary *mutable = [report mutableCopy];
    fixupReport(mutable);
    return mutable;
}
