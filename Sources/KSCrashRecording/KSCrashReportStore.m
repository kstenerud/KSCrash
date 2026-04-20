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
#import "KSCrashConfiguration+Private.h"
#import "KSCrashReport.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportFilter.h"
#import "KSCrashReportStoreC+Private.h"
#import "KSCrashRunContext.h"
#import "KSCrashRunSummary.h"
#import "KSJSONCodecObjC.h"
#import "KSNSErrorHelper.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

const KSCrashReportID KSCrashReportNoID = 0;

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
        KSCrashReportStoreConfiguration *resolvedConfiguration = configuration ?: [KSCrashReportStoreConfiguration new];
        _cConfig = [resolvedConfiguration toCConfiguration];
        _reportCleanupPolicy = resolvedConfiguration.reportCleanupPolicy;

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

- (KSCrashReportID)nextReportID
{
    KSCrashReportID reportID = KSCrashReportNoID;
    if (kscrs_getReportIDs(&reportID, 1, &_cConfig) <= 0) {
        return KSCrashReportNoID;
    }
    return reportID;
}

- (void)sendAllReportsWithCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSArray<NSNumber *> *allIDs = [self reportIDs];
    NSString *currentRunID = [NSString stringWithUTF8String:kscrash_getRunID()];

    // Load reports, skipping ones from the current run (they may still be updated).
    NSMutableArray *reports = [NSMutableArray arrayWithCapacity:allIDs.count];
    NSMutableArray<NSNumber *> *sentIDs = [NSMutableArray arrayWithCapacity:allIDs.count];
    for (NSNumber *numericID in allIDs) {
        KSCrashReportDictionary *report = [self reportForID:numericID.longLongValue];
        if (report == nil) {
            continue;
        }
        NSString *reportRunID = report.value[@"report"][@"run_id"];
        if ([reportRunID isEqualToString:currentRunID]) {
            KSLOG_INFO(@"Skipping report from current run (run_id: %@)", currentRunID);
            continue;
        }
        [reports addObject:report];
        [sentIDs addObject:numericID];
    }

    KSLOG_INFO(@"Sending %d crash reports", [reports count]);

    __weak __typeof(self) weakSelf = self;
    [self sendReports:reports
         onCompletion:^(NSArray *filteredReports, NSError *error) {
             __strong __typeof(weakSelf) strongSelf = weakSelf;
             if (strongSelf == nil) {
                 kscrash_callCompletion(onCompletion, filteredReports, error);
                 return;
             }
             KSLOG_DEBUG(@"Process finished");
             if (error != nil) {
                 KSLOG_ERROR(@"Failed to send reports: %@", error);
             }
             if ((strongSelf.reportCleanupPolicy == KSCrashReportCleanupPolicyOnSuccess && error == nil) ||
                 strongSelf.reportCleanupPolicy == KSCrashReportCleanupPolicyAlways) {
                 for (NSNumber *reportID in sentIDs) {
                     [strongSelf deleteReportWithID:reportID.longLongValue];
                 }
             }
             kscrs_cleanupOrphanedRunSidecars(&strongSelf->_cConfig);
             kscrash_callCompletion(onCompletion, filteredReports, error);
         }];
}

- (void)sendReportWithID:(KSCrashReportID)reportID completion:(nullable KSCrashReportFilterCompletion)onCompletion
{
    [self sendReportWithID:reportID includeCurrentRun:YES completion:onCompletion];
}

- (void)sendReportWithID:(KSCrashReportID)reportID
       includeCurrentRun:(BOOL)includeCurrentRun
              completion:(nullable KSCrashReportFilterCompletion)onCompletion
{
    KSCrashReportDictionary *report = [self reportForID:reportID];
    if (report == nil) {
        kscrash_callCompletion(onCompletion, @[],
                               [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                           code:0
                                                    description:@"Report not found."]);
        return;
    }

    if (!includeCurrentRun) {
        NSString *currentRunID = [NSString stringWithUTF8String:kscrash_getRunID()];
        NSString *reportRunID = report.value[@"report"][@"run_id"];
        if ([reportRunID isEqualToString:currentRunID]) {
            KSLOG_INFO(@"Skipping report from current run (run_id: %@)", currentRunID);
            kscrash_callCompletion(
                onCompletion, @[],
                [KSNSErrorHelper errorWithDomain:[[self class] description]
                                            code:0
                                     description:@"Report belongs to the current run and may still be updated."]);
            return;
        }
    }

    __weak __typeof(self) weakSelf = self;
    [self sendReports:@[ report ]
         onCompletion:^(NSArray *filteredReports, NSError *error) {
             __strong __typeof(weakSelf) strongSelf = weakSelf;
             if (strongSelf == nil) {
                 kscrash_callCompletion(onCompletion, filteredReports, error);
                 return;
             }
             if (error != nil) {
                 KSLOG_ERROR(@"Failed to send report: %@", error);
             }
             if ((strongSelf.reportCleanupPolicy == KSCrashReportCleanupPolicyOnSuccess && error == nil) ||
                 strongSelf.reportCleanupPolicy == KSCrashReportCleanupPolicyAlways) {
                 [strongSelf deleteReportWithID:reportID];
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

- (void)cleanupOrphanedRunSidecars
{
    kscrs_cleanupOrphanedRunSidecars(&_cConfig);
}

#pragma mark - Run summaries

- (void)sendAllRunSummariesWithCompletion:(KSCrashRunFilterCompletion)onCompletion
{
    id<KSCrashRunFilter> runSink = self.runSink;
    if (runSink == nil) {
        if (onCompletion) {
            onCompletion(@[], [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                          code:0
                                                   description:@"No run sink set. Run summaries not sent."]);
        }
        return;
    }

    const char *runsDirC = _cConfig.runSummariesPath;
    if (runsDirC == NULL || runsDirC[0] == '\0') {
        if (onCompletion) {
            onCompletion(@[], nil);
        }
        return;
    }

    // Snapshot the path into an NSString so the block doesn't depend on `self`
    // outliving the dispatch.
    NSString *runsDir = [NSString stringWithUTF8String:runsDirC];
    dispatch_queue_t queue = ksruncontext_getRunSummaryQueue();

    dispatch_async(queue, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:runsDir error:nil];
        NSMutableArray<KSCrashRunSummary *> *summaries = [NSMutableArray arrayWithCapacity:entries.count];
        // runID → file path. Populated from decoded summaries so we can later
        // delete only the files whose runIDs the sink confirmed shipped.
        NSMutableDictionary<NSString *, NSString *> *runIDToPath =
            [NSMutableDictionary dictionaryWithCapacity:entries.count];
        for (NSString *entry in entries) {
            if (![entry.pathExtension.lowercaseString isEqualToString:@"run"]) {
                continue;
            }
            NSString *path = [runsDir stringByAppendingPathComponent:entry];
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (data == nil) {
                continue;
            }
            KSCrashRunSummary *summary = [KSCrashRunSummary summaryFromJSONData:data error:nil];
            if (summary == nil) {
                // Corrupt file — leave it alone, will be pruned by the backlog
                // cap on the next install if it keeps failing.
                KSLOG_ERROR(@"Failed to decode run summary at %@", path);
                continue;
            }
            [summaries addObject:summary];
            if (summary.runID.length > 0) {
                runIDToPath[summary.runID] = path;
            }
        }

        if (summaries.count == 0) {
            if (onCompletion) {
                onCompletion(@[], nil);
            }
            return;
        }

        [runSink filterRuns:summaries
               onCompletion:^(NSArray<KSCrashRunSummary *> *_Nullable filteredRuns, NSError *_Nullable error) {
                   // Back onto the summary queue for deletion so we don't race
                   // any other persist/send happening in parallel, and so the
                   // final completion fires after file I/O is settled.
                   dispatch_async(queue, ^{
                       if (error != nil) {
                           KSLOG_ERROR(@"Run summary send reported an error: %@", error);
                       }
                       // Delete only files whose runID is present in filteredRuns
                       // — the sink signals per-run success by including it.
                       // Runs omitted from filteredRuns (or all runs, on full
                       // failure) stay on disk for the next call to retry.
                       NSFileManager *innerFM = [NSFileManager defaultManager];
                       for (KSCrashRunSummary *summary in filteredRuns) {
                           NSString *path = runIDToPath[summary.runID];
                           if (path != nil) {
                               [innerFM removeItemAtPath:path error:nil];
                           }
                       }
                       if (onCompletion) {
                           onCompletion(filteredRuns, error);
                       }
                   });
               }];
    });
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

- (nullable NSData *)loadCrashReportJSONWithID:(int64_t)reportID
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
    if (reportCount <= 0) {
        return @[];
    }
    int64_t *reportIDsC = malloc(sizeof(int64_t) * (size_t)reportCount);
    if (!reportIDsC) {
        return @[];
    }
    reportCount = kscrs_getReportIDs(reportIDsC, reportCount, &_cConfig);
    NSMutableArray *reportIDs = [NSMutableArray arrayWithCapacity:(NSUInteger)reportCount];
    for (int i = 0; i < reportCount; i++) {
        [reportIDs addObject:[NSNumber numberWithLongLong:reportIDsC[i]]];
    }
    free(reportIDsC);
    return [reportIDs copy];
}

- (KSCrashReportData *)reportDataForID:(int64_t)reportID
{
    NSData *jsonData = [self loadCrashReportJSONWithID:reportID];
    if (jsonData == nil) {
        return nil;
    }
    return [KSCrashReportData reportWithValue:jsonData];
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
    if (reportCount <= 0) {
        return @[];
    }
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
