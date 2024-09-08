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
#import "KSCrashConfiguration+Private.h"
#import "KSCrashReport.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportFilter.h"
#import "KSCrashReportStoreC.h"
#import "KSJSONCodecObjC.h"
#import "KSNSErrorHelper.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

@implementation KSCrashReportStore {
    KSCrashReportStoreCConfiguration _cConfig;
}

+ (NSString *)defaultInstallSubfolder
{
    return @KSCRS_DEFAULT_REPORTS_FOLDER;
}

+ (instancetype)defaultStoreWithError:(NSError **)error
{
    return [KSCrashReportStore storeWithConfiguration:nil error:error];
}

+ (instancetype)storeWithConfiguration:(KSCrashReportStoreConfiguration *)configuration error:(NSError **)error
{
    return [[KSCrashReportStore alloc] initWithConfiguration:configuration error:error];
}

- (nullable instancetype)initWithConfiguration:(KSCrashReportStoreConfiguration *)configuration error:(NSError **)error
{
    self = [super init];
    if (self != nil) {
        _cConfig = [(configuration ?: [KSCrashReportStoreConfiguration new]) toCConfiguration];
        _reportCleanupPolicy = KSCrashReportCleanupPolicyAlways;

        kscrs_initialize(&_cConfig);
    }
    return self;
}

- (void)dealloc
{
    KSCrashReportStoreCConfiguration_Release(&_cConfig);
}

- (NSInteger)reportCount
{
    return kscrs_getReportCount(&_cConfig);
}

- (void)sendAllReportsWithCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSArray *reports = [self allReports];

    KSLOG_INFO(@"Sending %d crash reports", [reports count]);

    __weak __typeof(self) weakSelf = self;
    [self sendReports:reports
         onCompletion:^(NSArray *filteredReports, NSError *error) {
             KSLOG_DEBUG(@"Process finished with completion: %d", completed);
             if (error != nil) {
                 KSLOG_ERROR(@"Failed to send reports: %@", error);
             }
             if ((self.reportCleanupPolicy == KSCrashReportCleanupPolicyOnSuccess && error == nil) ||
                 self.reportCleanupPolicy == KSCrashReportCleanupPolicyAlways) {
                 [weakSelf deleteAllReports];
             }
             kscrash_callCompletion(onCompletion, filteredReports, error);
         }];
}

- (void)deleteAllReports
{
    kscrs_deleteAllReports(&_cConfig);
}

- (void)deleteReportWithID:(int64_t)reportID
{
    kscrs_deleteReportWithID(reportID, &_cConfig);
}

#pragma mark - Private API

- (void)sendReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    if ([reports count] == 0) {
        kscrash_callCompletion(onCompletion, reports, nil);
        return;
    }

    if (self.sink == nil) {
        kscrash_callCompletion(onCompletion, reports,
                               [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                           code:0
                                                    description:@"No sink set. Crash reports not sent."]);
        return;
    }

    [self.sink filterReports:reports
                onCompletion:^(NSArray *filteredReports, NSError *error) {
                    kscrash_callCompletion(onCompletion, filteredReports, error);
                }];
}

- (NSData *)loadCrashReportJSONWithID:(int64_t)reportID
{
    char *report = kscrs_readReport(reportID, &_cConfig);
    if (report != NULL) {
        return [NSData dataWithBytesNoCopy:report length:strlen(report) freeWhenDone:YES];
    }
    return nil;
}

- (NSArray<NSNumber *> *)reportIDs
{
    int reportCount = kscrs_getReportCount(&_cConfig);
    int64_t reportIDsC[reportCount];
    reportCount = kscrs_getReportIDs(reportIDsC, reportCount, &_cConfig);
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

    return [KSCrashReportDictionary reportWithValue:crashReport];
}

- (NSArray<KSCrashReportDictionary *> *)allReports
{
    int reportCount = kscrs_getReportCount(&_cConfig);
    int64_t reportIDs[reportCount];
    reportCount = kscrs_getReportIDs(reportIDs, reportCount, &_cConfig);
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
