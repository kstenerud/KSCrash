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
#import "KSCrashInstallConfiguration+Private.h"
#import "KSCrashReport.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportFilter.h"
#import "KSCrashReportStoreC+Private.h"
#import "KSCrashRunContext.h"
#import "KSCrashRunSummary.h"
#import "KSCrashSendConfiguration.h"
#import "KSJSONCodecObjC.h"
#import "KSNSErrorHelper.h"

#import <os/lock.h>

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

const KSCrashReportID KSCrashReportNoID = 0;

@interface KSCrashReportStore ()

- (void)sendReports:(NSArray<id<KSCrashReport>> *)reports
            filters:(NSArray<id<KSCrashReportFilter>> *)filters
       onCompletion:(KSCrashReportFilterCompletion)onCompletion;

- (void)runReportFilterChain:(NSArray<id<KSCrashReportFilter>> *)filters
                     reports:(NSArray<id<KSCrashReport>> *)reports
                onCompletion:(KSCrashReportFilterCompletion)onCompletion;

- (void)runRunFilterChain:(NSArray<id<KSCrashRunFilter>> *)filters
                     runs:(NSArray<KSCrashRunSummary *> *)runs
             onCompletion:(KSCrashRunFilterCompletion)onCompletion;

@end

@implementation KSCrashReportStore {
    KSCrashReportStoreCConfiguration _cConfig;
    // Guards all on-disk run-summary work (prune, enumerate, decode, delete)
    // and the _isSendingRunSummaries reentrancy flag.
    os_unfair_lock _runSummaryLock;
    // True from the moment a send is accepted until its sink completion has
    // run. A second concurrent sendAllRunSummariesWithConfiguration: short-circuits
    // with an error rather than re-decoding the same files and handing the sink
    // duplicates.
    BOOL _isSendingRunSummaries;
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
        _runSummaryLock = OS_UNFAIR_LOCK_INIT;

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

- (void)sendAllReportsWithConfiguration:(KSCrashSendConfiguration *)configuration
                             completion:(KSCrashReportFilterCompletion)onCompletion
{
    NSArray<id<KSCrashReportFilter>> *filters = configuration.reportFilters;
    KSCrashReportCleanupPolicy cleanupPolicy = configuration.reportCleanupPolicy;

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
              filters:filters
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
             if ((cleanupPolicy == KSCrashReportCleanupPolicyOnSuccess && error == nil) ||
                 cleanupPolicy == KSCrashReportCleanupPolicyAlways) {
                 for (NSNumber *reportID in sentIDs) {
                     [strongSelf deleteReportWithID:reportID.longLongValue];
                 }
             }
             kscrs_cleanupOrphanedRunSidecars(&strongSelf->_cConfig);
             kscrash_callCompletion(onCompletion, filteredReports, error);
         }];
}

- (void)sendReportWithID:(KSCrashReportID)reportID
           configuration:(KSCrashSendConfiguration *)configuration
              completion:(nullable KSCrashReportFilterCompletion)onCompletion
{
    [self sendReportWithID:reportID includeCurrentRun:YES configuration:configuration completion:onCompletion];
}

- (void)sendReportWithID:(KSCrashReportID)reportID
       includeCurrentRun:(BOOL)includeCurrentRun
           configuration:(KSCrashSendConfiguration *)configuration
              completion:(nullable KSCrashReportFilterCompletion)onCompletion
{
    NSArray<id<KSCrashReportFilter>> *filters = configuration.reportFilters;
    KSCrashReportCleanupPolicy cleanupPolicy = configuration.reportCleanupPolicy;

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
              filters:filters
         onCompletion:^(NSArray *filteredReports, NSError *error) {
             __strong __typeof(weakSelf) strongSelf = weakSelf;
             if (strongSelf == nil) {
                 kscrash_callCompletion(onCompletion, filteredReports, error);
                 return;
             }
             if (error != nil) {
                 KSLOG_ERROR(@"Failed to send report: %@", error);
             }
             if ((cleanupPolicy == KSCrashReportCleanupPolicyOnSuccess && error == nil) ||
                 cleanupPolicy == KSCrashReportCleanupPolicyAlways) {
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

- (void)sendAllRunSummariesWithConfiguration:(KSCrashSendConfiguration *)configuration
                                  completion:(nullable KSCrashRunFilterCompletion)onCompletion
{
    NSArray<id<KSCrashRunFilter>> *filters = configuration.runSummaryFilters;

    if (filters.count == 0) {
        if (onCompletion) {
            onCompletion(@[], [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                          code:0
                                                   description:@"No run filters set. Run summaries not sent."]);
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
    // Reentrancy guard: only one send pipeline runs at a time. Two concurrent
    // calls would each decode the same files and pass duplicates to the sink;
    // the second delete pass would also see ENOENT for everything the first
    // pass deleted. Take the flag synchronously here so the second caller gets
    // immediate feedback rather than silently joining a duplicate batch.
    os_unfair_lock_lock(&_runSummaryLock);
    if (_isSendingRunSummaries) {
        os_unfair_lock_unlock(&_runSummaryLock);
        if (onCompletion) {
            onCompletion(@[], [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                          code:0
                                                   description:@"Run summary send already in progress."]);
        }
        return;
    }
    _isSendingRunSummaries = YES;
    os_unfair_lock_unlock(&_runSummaryLock);

    NSString *runsDir = [NSString stringWithUTF8String:runsDirC];
    int maxCount = _cConfig.maxRunSummaryCount;

    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                // Self is gone, so the flag dies with it — no need to clear.
                if (onCompletion) onCompletion(@[], nil);
                return;
            }

            // runID → list of on-disk paths that decoded to that runID. A
            // list (not a single path) because the sink contract is keyed
            // by runID and we must not lose a file to a duplicate-runID
            // collision — on collision we still want to delete every file
            // the sink confirmed as shipped.
            NSMutableArray<KSCrashRunSummary *> *summaries = nil;
            NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *runIDToPaths = nil;

            os_unfair_lock_lock(&strongSelf->_runSummaryLock);

            ksruncontext_pruneRunSummaries(runsDirC, maxCount);

            NSFileManager *fm = [NSFileManager defaultManager];
            NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:runsDir error:nil];
            summaries = [NSMutableArray arrayWithCapacity:entries.count];
            runIDToPaths = [NSMutableDictionary dictionaryWithCapacity:entries.count];
            for (NSString *entry in entries) {
                @autoreleasepool {
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
                        KSLOG_ERROR(@"Failed to decode run summary at %@", path);
                        continue;
                    }
                    // Summaries with no runID can't be tied back to a sink
                    // acknowledgement, so skip them entirely rather than
                    // shipping a record we'd never be able to delete.
                    // Pruning by maxRunSummaryCount eventually reclaims them.
                    if (summary.runID.length == 0) {
                        KSLOG_ERROR(@"Run summary at %@ has empty runID; skipping", path);
                        continue;
                    }
                    [summaries addObject:summary];
                    NSMutableArray<NSString *> *bucket = runIDToPaths[summary.runID];
                    if (bucket == nil) {
                        bucket = [NSMutableArray arrayWithCapacity:1];
                        runIDToPaths[summary.runID] = bucket;
                    }
                    [bucket addObject:path];
                }
            }

            os_unfair_lock_unlock(&strongSelf->_runSummaryLock);

            if (summaries.count == 0) {
                os_unfair_lock_lock(&strongSelf->_runSummaryLock);
                strongSelf->_isSendingRunSummaries = NO;
                os_unfair_lock_unlock(&strongSelf->_runSummaryLock);
                if (onCompletion) onCompletion(@[], nil);
                return;
            }

            [strongSelf
                runRunFilterChain:filters
                             runs:summaries
                     onCompletion:^(NSArray<KSCrashRunSummary *> *_Nullable filteredRuns, NSError *_Nullable error) {
                         __strong __typeof(weakSelf) deleteSelf = weakSelf;
                         if (error != nil) {
                             KSLOG_ERROR(@"Run summary send reported an error: %@", error);
                         }
                         if (deleteSelf != nil) {
                             // Delete every file whose runID the sink confirmed
                             // as shipped. Runs omitted (or all, on full failure)
                             // stay on disk for retry. Flag clear is in the same
                             // critical section as the deletes so a follow-up
                             // sender finds a clean directory state.
                             os_unfair_lock_lock(&deleteSelf->_runSummaryLock);
                             NSFileManager *innerFM = [NSFileManager defaultManager];
                             for (KSCrashRunSummary *summary in filteredRuns) {
                                 if (summary.runID.length == 0) {
                                     continue;
                                 }
                                 // Pop rather than lookup so a sink that
                                 // returns the same runID twice doesn't try
                                 // to delete the same file twice and log a
                                 // spurious ENOENT on the second pass.
                                 NSArray<NSString *> *pathsToDelete = runIDToPaths[summary.runID];
                                 if (pathsToDelete == nil) {
                                     continue;
                                 }
                                 [runIDToPaths removeObjectForKey:summary.runID];
                                 for (NSString *path in pathsToDelete) {
                                     NSError *removeError = nil;
                                     if (![innerFM removeItemAtPath:path error:&removeError]) {
                                         KSLOG_ERROR(@"Failed to delete run summary at %@: %@", path, removeError);
                                     }
                                 }
                             }
                             deleteSelf->_isSendingRunSummaries = NO;
                             os_unfair_lock_unlock(&deleteSelf->_runSummaryLock);
                         }
                         if (onCompletion) onCompletion(filteredRuns, error);
                     }];
        }
    });
}

#pragma mark - Private API

- (void)sendReports:(NSArray<id<KSCrashReport>> *)reports
            filters:(NSArray<id<KSCrashReportFilter>> *)filters
       onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    if ([reports count] == 0) {
        kscrash_callCompletion(onCompletion, reports, nil);
        return;
    }

    if (filters.count == 0) {
        kscrash_callCompletion(onCompletion, reports,
                               [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                           code:0
                                                    description:@"No filters set. Crash reports not sent."]);
        return;
    }

    [self runReportFilterChain:filters
                       reports:reports
                  onCompletion:^(NSArray *filteredReports, NSError *error) {
                      kscrash_callCompletion(onCompletion, filteredReports, error);
                  }];
}

/** Run reports through an ordered filter chain: each filter's output feeds the
 * next, the last filter is the terminal sink. Implemented here (rather than via
 * a filter-composition class) so KSCrashRecording needs no dependency on
 * KSCrashFilters. Runs at send time only (next launch / normal context), never
 * in a crash handler, so ObjC and dispatch are safe.
 */
- (void)runReportFilterChain:(NSArray<id<KSCrashReportFilter>> *)filters
                     reports:(NSArray<id<KSCrashReport>> *)reports
                onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSUInteger filterCount = filters.count;
    if (filterCount == 0) {
        kscrash_callCompletion(onCompletion, reports, nil);
        return;
    }

    __block NSUInteger iFilter = 0;
    __block KSCrashReportFilterCompletion filterCompletion;
    __block __weak KSCrashReportFilterCompletion weakFilterCompletion = nil;
    dispatch_block_t disposeOfCompletion = [^{
        // Release the self-reference on the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            filterCompletion = nil;
        });
    } copy];
    filterCompletion = [^(NSArray<id<KSCrashReport>> *filteredReports, NSError *filterError) {
        if (filterError != nil || filteredReports == nil) {
            if (filterError != nil) {
                kscrash_callCompletion(onCompletion, filteredReports, filterError);
            } else {
                kscrash_callCompletion(onCompletion, filteredReports,
                                       [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                                   code:0
                                                            description:@"filteredReports was nil"]);
            }
            disposeOfCompletion();
            return;
        }

        if (++iFilter < filterCount) {
            id<KSCrashReportFilter> filter = [filters objectAtIndex:iFilter];
            [filter filterReports:filteredReports onCompletion:weakFilterCompletion];
            return;
        }

        // All filters complete.
        kscrash_callCompletion(onCompletion, filteredReports, filterError);
        disposeOfCompletion();
    } copy];
    weakFilterCompletion = filterCompletion;

    id<KSCrashReportFilter> filter = [filters objectAtIndex:iFilter];
    [filter filterReports:reports onCompletion:filterCompletion];
}

/** Run-summary equivalent of runReportFilterChain:reports:onCompletion:. */
- (void)runRunFilterChain:(NSArray<id<KSCrashRunFilter>> *)filters
                     runs:(NSArray<KSCrashRunSummary *> *)runs
             onCompletion:(KSCrashRunFilterCompletion)onCompletion
{
    NSUInteger filterCount = filters.count;
    if (filterCount == 0) {
        if (onCompletion) onCompletion(runs, nil);
        return;
    }

    __block NSUInteger iFilter = 0;
    __block KSCrashRunFilterCompletion filterCompletion;
    __block __weak KSCrashRunFilterCompletion weakFilterCompletion = nil;
    dispatch_block_t disposeOfCompletion = [^{
        dispatch_async(dispatch_get_main_queue(), ^{
            filterCompletion = nil;
        });
    } copy];
    filterCompletion = [^(NSArray<KSCrashRunSummary *> *filteredRuns, NSError *filterError) {
        if (filterError != nil || filteredRuns == nil) {
            NSError *error = filterError
                                 ?: [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                                code:0
                                                         description:@"filteredRuns was nil"];
            if (onCompletion) onCompletion(filteredRuns, error);
            disposeOfCompletion();
            return;
        }

        if (++iFilter < filterCount) {
            id<KSCrashRunFilter> filter = [filters objectAtIndex:iFilter];
            [filter filterRuns:filteredRuns onCompletion:weakFilterCompletion];
            return;
        }

        if (onCompletion) onCompletion(filteredRuns, filterError);
        disposeOfCompletion();
    } copy];
    weakFilterCompletion = filterCompletion;

    id<KSCrashRunFilter> filter = [filters objectAtIndex:iFilter];
    [filter filterRuns:runs onCompletion:filterCompletion];
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
