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

#import "KSCrashInstallConfiguration+Private.h"
#import "KSCrashReport.h"
#import "KSCrashReportStoreC+Private.h"
#import "KSJSONCodecObjC.h"

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

- (void)deleteAllReports
{
    kscrs_deleteAllReports(&_cConfig);
}

- (void)deleteReportWithID:(int64_t)reportID
{
    kscrs_deleteReportWithID(reportID, &_cConfig);
}

- (void)reclaimOrphanedRunData
{
    kscrs_reclaimOrphanedRunData(&_cConfig);
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
    return [self listReportIDsWithError:NULL] ?: @[];
}

- (nullable NSArray<NSNumber *> *)listReportIDsWithError:(NSError **)error
{
    int reportCount = kscrs_getReportCount(&_cConfig);
    if (reportCount < 0) {
        [self setEnumerationError:error];
        return nil;
    }
    if (reportCount == 0) {
        return @[];
    }
    int64_t *reportIDsC = malloc(sizeof(int64_t) * (size_t)reportCount);
    if (!reportIDsC) {
        [self setEnumerationError:error];
        return nil;
    }
    reportCount = kscrs_getReportIDs(reportIDsC, reportCount, &_cConfig);
    if (reportCount < 0) {
        free(reportIDsC);
        [self setEnumerationError:error];
        return nil;
    }
    NSMutableArray *reportIDs = [NSMutableArray arrayWithCapacity:(NSUInteger)reportCount];
    for (int i = 0; i < reportCount; i++) {
        [reportIDs addObject:[NSNumber numberWithLongLong:reportIDsC[i]]];
    }
    free(reportIDsC);
    return [reportIDs copy];
}

- (void)setEnumerationError:(NSError **)error
{
    if (error != NULL) {
        *error = [NSError
            errorWithDomain:NSCocoaErrorDomain
                       code:NSFileReadUnknownError
                   userInfo:@{ NSLocalizedDescriptionKey : @"The reports directory could not be enumerated." }];
    }
}

- (BOOL)removeReportWithID:(int64_t)reportID error:(NSError **)error
{
    if (kscrs_deleteReportWithID(reportID, &_cConfig)) {
        return YES;
    }
    if (error != NULL) {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSFileWriteUnknownError
                                 userInfo:@{
                                     NSLocalizedDescriptionKey :
                                         [NSString stringWithFormat:@"Report %lld could not be deleted.", reportID]
                                 }];
    }
    return NO;
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
