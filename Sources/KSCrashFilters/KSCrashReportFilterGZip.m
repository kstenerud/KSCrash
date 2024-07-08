//
//  KSCrashReportFilterGZip.m
//
//  Created by Karl Stenerud on 2012-05-10.
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

#import "KSCrashReportFilterGZip.h"
#import "KSCrashReport.h"
#import "KSGZipHelper.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

@interface KSCrashReportFilterGZipCompress ()

@property(nonatomic, readwrite, assign) NSInteger compressionLevel;

@end

@implementation KSCrashReportFilterGZipCompress

+ (instancetype)filterWithCompressionLevel:(NSInteger)compressionLevel
{
    return [[self alloc] initWithCompressionLevel:compressionLevel];
}

- (instancetype)initWithCompressionLevel:(NSInteger)compressionLevel
{
    if ((self = [super init])) {
        _compressionLevel = compressionLevel;
    }
    return self;
}

- (void)filterReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KSCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KSCrashReportData *report in reports) {
        if ([report isKindOfClass:[KSCrashReportData class]] == NO) {
            KSLOG_ERROR(@"Unexpected non-data report: %@", report);
            continue;
        }

        NSError *error = nil;
        NSData *compressedData = [KSGZipHelper gzippedData:report.value
                                          compressionLevel:(int)self.compressionLevel
                                                     error:&error];
        if (compressedData == nil) {
            kscrash_callCompletion(onCompletion, filteredReports, NO, error);
            return;
        } else {
            [filteredReports addObject:[KSCrashReportData reportWithValue:compressedData]];
        }
    }

    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end

@implementation KSCrashReportFilterGZipDecompress

+ (instancetype)filter
{
    return [[self alloc] init];
}

- (void)filterReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KSCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KSCrashReportData *report in reports) {
        if ([report isKindOfClass:[KSCrashReportData class]] == NO) {
            KSLOG_ERROR(@"Unexpected non-data report: %@", report);
            continue;
        }

        NSError *error = nil;
        NSData *decompressedData = [KSGZipHelper gunzippedData:report.value error:&error];
        if (decompressedData == nil) {
            kscrash_callCompletion(onCompletion, filteredReports, NO, error);
            return;
        } else {
            [filteredReports addObject:[KSCrashReportData reportWithValue:decompressedData]];
        }
    }

    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end
