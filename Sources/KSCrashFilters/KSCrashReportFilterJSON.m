//
//  KSCrashReportFilterJSON.m
//
//  Created by Karl Stenerud on 2012-05-09.
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

#import "KSCrashReportFilterJSON.h"
#import "KSCrashReport.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

@interface KSCrashReportFilterJSONEncode ()

@property(nonatomic, readwrite, assign) KSJSONEncodeOption encodeOptions;

@end

@implementation KSCrashReportFilterJSONEncode

- (instancetype)initWithOptions:(KSJSONEncodeOption)options
{
    if ((self = [super init])) {
        _encodeOptions = options;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithOptions:KSJSONEncodeOptionNone];
}

- (void)filterReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KSCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KSCrashReportDictionary *report in reports) {
        if ([report isKindOfClass:[KSCrashReportDictionary class]] == NO) {
            KSLOG_ERROR(@"Unexpected non-dictionary report: %@", report);
            continue;
        }

        NSError *error = nil;
        NSData *jsonData = [KSJSONCodec encode:report.value options:self.encodeOptions error:&error];
        if (jsonData == nil) {
            kscrash_callCompletion(onCompletion, filteredReports, error);
            return;
        } else {
            [filteredReports addObject:[KSCrashReportData reportWithValue:jsonData]];
        }
    }

    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end

@interface KSCrashReportFilterJSONDecode ()

@property(nonatomic, readwrite, assign) KSJSONDecodeOption decodeOptions;

@end

@implementation KSCrashReportFilterJSONDecode

- (instancetype)initWithOptions:(KSJSONDecodeOption)options
{
    if ((self = [super init])) {
        _decodeOptions = options;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithOptions:KSJSONDecodeOptionNone];
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
        NSDictionary *decodedReport = [KSJSONCodec decode:report.value options:self.decodeOptions error:&error];
        if (decodedReport == nil || [decodedReport isKindOfClass:[NSDictionary class]] == NO) {
            kscrash_callCompletion(onCompletion, filteredReports, error);
            return;
        } else {
            [filteredReports addObject:[KSCrashReportDictionary reportWithValue:decodedReport]];
        }
    }

    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end
