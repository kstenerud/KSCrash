//
//  KSCrashReportStore.m
//
//  Created by Nikolay Volosatov on 2024-08-28.
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

#import "KSCrashReportStore.h"

#import "KSCrash+Private.h"
#import "KSCrashC.h"
#import "KSCrashConfiguration.h"
#import "KSCrashDoctor.h"
#import "KSCrashReport.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportFilter.h"
#import "KSNSErrorHelper.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

@implementation KSCrashReportStore {
    NSString *_path;
    NSString *_bundleName;
}

+ (instancetype)defaultStoreWithError:(NSError **)error
{
    return [KSCrashReportStore storeWithPath:nil error:error];
}

+ (instancetype)storeWithPath:(NSString *)path error:(NSError **)error
{
    return [[KSCrashReportStore alloc] initWithPath:(path ?: kscrash_getDefaultInstallPath()) error:error];
}

- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error
{
    self = [super init];
    if (self != nil) {
        _path = [path copy];
        _bundleName = kscrash_getBundleName();

        _deleteBehaviorAfterSendAll = KSCDeleteAlways;

        KSCrashInstallErrorCode result = kscrash_setupReportsStore(_bundleName.UTF8String, _path.UTF8String);
        if (result != KSCrashInstallErrorNone) {
            if (error != NULL) {
                *error = [KSCrash errorForInstallErrorCode:result];
            }
            return NO;
        }
    }
    return self;
}

- (void)sendAllReportsWithCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSArray *reports = [self allReports];

    KSLOG_INFO(@"Sending %d crash reports", [reports count]);

    [self sendReports:reports
         onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
             KSLOG_DEBUG(@"Process finished with completion: %d", completed);
             if (error != nil) {
                 KSLOG_ERROR(@"Failed to send reports: %@", error);
             }
             if ((self.deleteBehaviorAfterSendAll == KSCDeleteOnSucess && completed) ||
                 self.deleteBehaviorAfterSendAll == KSCDeleteAlways) {
                 kscrash_deleteAllReports();
             }
             kscrash_callCompletion(onCompletion, filteredReports, completed, error);
         }];
}

- (void)deleteAllReports
{
    kscrash_deleteAllReports();
}

- (void)deleteReportWithID:(int64_t)reportID
{
    kscrash_deleteReportWithID(reportID);
}

#pragma mark - Private API

- (NSInteger)reportCount
{
    return kscrash_getReportCount();
}

- (void)sendReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    if ([reports count] == 0) {
        kscrash_callCompletion(onCompletion, reports, YES, nil);
        return;
    }

    if (self.sink == nil) {
        kscrash_callCompletion(onCompletion, reports, NO,
                               [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                           code:0
                                                    description:@"No sink set. Crash reports not sent."]);
        return;
    }

    [self.sink filterReports:reports
                onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
                    kscrash_callCompletion(onCompletion, filteredReports, completed, error);
                }];
}

- (NSData *)loadCrashReportJSONWithID:(int64_t)reportID
{
    char *report = kscrash_readReport(reportID);
    if (report != NULL) {
        return [NSData dataWithBytesNoCopy:report length:strlen(report) freeWhenDone:YES];
    }
    return nil;
}

- (void)doctorReport:(NSMutableDictionary *)report
{
    NSMutableDictionary *crashReport = report[KSCrashField_Crash];
    if (crashReport != nil) {
        crashReport[KSCrashField_Diagnosis] = [[KSCrashDoctor doctor] diagnoseCrash:report];
    }
    crashReport = report[KSCrashField_RecrashReport][KSCrashField_Crash];
    if (crashReport != nil) {
        crashReport[KSCrashField_Diagnosis] = [[KSCrashDoctor doctor] diagnoseCrash:report];
    }
}

- (NSArray<NSNumber *> *)reportIDs
{
    int reportCount = kscrash_getReportCount();
    int64_t reportIDsC[reportCount];
    reportCount = kscrash_getReportIDs(reportIDsC, reportCount);
    NSMutableArray *reportIDs = [NSMutableArray arrayWithCapacity:(NSUInteger)reportCount];
    for (int i = 0; i < reportCount; i++) {
        [reportIDs addObject:[NSNumber numberWithLongLong:reportIDsC[i]]];
    }
    return [reportIDs copy];
}

- (KSCrashReportDictionary *)reportForID:(int64_t)reportID
{
    NSData *jsonData = [self loadCrashReportJSONWithID:reportID];
    if (jsonData == nil) {
        return nil;
    }

    NSError *error = nil;
    NSMutableDictionary *crashReport =
        [KSJSONCodec decode:jsonData
                    options:KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject |
                            KSJSONDecodeOptionKeepPartialObject
                      error:&error];
    if (error != nil) {
        KSLOG_ERROR(@"Encountered error loading crash report %" PRIx64 ": %@", reportID, error);
    }
    if (crashReport == nil) {
        KSLOG_ERROR(@"Could not load crash report");
        return nil;
    }
    [self doctorReport:crashReport];

    return [KSCrashReportDictionary reportWithValue:crashReport];
}

- (NSArray<KSCrashReportDictionary *> *)allReports
{
    int reportCount = kscrash_getReportCount();
    int64_t reportIDs[reportCount];
    reportCount = kscrash_getReportIDs(reportIDs, reportCount);
    NSMutableArray<KSCrashReportDictionary *> *reports = [NSMutableArray arrayWithCapacity:(NSUInteger)reportCount];
    for (int i = 0; i < reportCount; i++) {
        KSCrashReportDictionary *report = [self reportForID:reportIDs[i]];
        if (report != nil) {
            [reports addObject:report];
        }
    }

    return reports;
}

@end
