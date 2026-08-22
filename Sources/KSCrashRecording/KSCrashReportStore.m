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
#import "KSCrashInstallConfiguration+Private.h"
#import "KSCrashReportStoreC+Private.h"
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

        KSCrashInstallErrorCode result = kscrs_initialize(&_cConfig);
        if (result != KSCrashInstallErrorNone) {
            if (error != NULL) {
                *error = [KSCrash errorForInstallErrorCode:result];
            }
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    KSCrashReportStoreCConfiguration_Release(&_cConfig);
}

- (NSInteger)reportCount
{
    // The property is a count: an enumeration failure (the C store's -1)
    // reads as no reports here, and surfaces through listReportIDsWithError:.
    return MAX(kscrs_getReportCount(&_cConfig), 0);
}

- (void)deleteAllReports
{
    kscrs_deleteAllReports(&_cConfig);
}

- (void)reclaimOrphanedRunData
{
    kscrs_reclaimOrphanedRunData(&_cConfig);
}

- (nullable NSData *)loadCrashReportJSONWithID:(int64_t)reportID error:(NSError **)error
{
    KSCrashReportReadStatus status = KSCrashReportReadStatusOK;
    char *report = kscrs_readReport(reportID, &_cConfig, &status);
    if (report != NULL) {
        return [NSData dataWithBytesNoCopy:report length:strlen(report) freeWhenDone:YES];
    }
    if (status == KSCrashReportReadStatusUndecodable) {
        [KSNSErrorHelper fillError:error
                        withDomain:NSCocoaErrorDomain
                              code:NSFileReadCorruptFileError
                       description:@"The report file does not hold a JSON report."];
    } else {
        [KSNSErrorHelper fillError:error
                        withDomain:NSCocoaErrorDomain
                              code:NSFileReadUnknownError
                       description:@"The report could not be read."];
    }
    return nil;
}

- (nullable NSArray<NSNumber *> *)listReportIDsWithError:(NSError **)error
{
    int capacity = kscrs_getReportCount(&_cConfig);
    if (capacity < 0) {
        [KSNSErrorHelper fillError:error
                        withDomain:NSCocoaErrorDomain
                              code:NSFileReadUnknownError
                       description:@"The reports directory could not be enumerated."];
        return nil;
    }
    if (capacity == 0) {
        return @[];
    }
    // The count and the fill are separate scans, so a report added between
    // them could otherwise push a pending one past the cap in directory
    // order. Slack absorbs arrivals, a fill strictly below capacity proves
    // the listing is complete, and a full buffer rescans with the larger
    // count.
    for (;;) {
        capacity += 8;
        int64_t *reportIDsC = malloc(sizeof(int64_t) * (size_t)capacity);
        if (reportIDsC == NULL) {
            [KSNSErrorHelper fillError:error
                            withDomain:NSCocoaErrorDomain
                                  code:NSFileReadUnknownError
                           description:@"Could not allocate the report listing."];
            return nil;
        }
        int found = kscrs_getReportIDs(reportIDsC, capacity, &_cConfig);
        if (found < 0) {
            free(reportIDsC);
            [KSNSErrorHelper fillError:error
                            withDomain:NSCocoaErrorDomain
                                  code:NSFileReadUnknownError
                           description:@"The reports directory could not be enumerated."];
            return nil;
        }
        if (found == capacity) {
            free(reportIDsC);
            capacity = found;
            continue;
        }
        NSMutableArray *reportIDs = [NSMutableArray arrayWithCapacity:(NSUInteger)found];
        for (int i = 0; i < found; i++) {
            [reportIDs addObject:[NSNumber numberWithLongLong:reportIDsC[i]]];
        }
        free(reportIDsC);
        return [reportIDs copy];
    }
}

- (BOOL)removeReportWithID:(int64_t)reportID error:(NSError **)error
{
    if (kscrs_deleteReportWithID(reportID, &_cConfig)) {
        return YES;
    }
    [KSNSErrorHelper fillError:error
                    withDomain:NSCocoaErrorDomain
                          code:NSFileWriteUnknownError
                   description:@"Report %lld could not be deleted.", reportID];
    return NO;
}

- (NSData *)reportDataForID:(int64_t)reportID error:(NSError **)error
{
    return [self loadCrashReportJSONWithID:reportID error:error];
}

- (NSString *)runIDForReportID:(int64_t)reportID
{
    char *runID = kscrs_copyReportRunID(reportID, &_cConfig);
    if (runID == NULL) {
        return nil;
    }
    NSString *result = [NSString stringWithUTF8String:runID];
    free(runID);
    return result;
}

@end
