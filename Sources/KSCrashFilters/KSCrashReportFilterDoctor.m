//
//  KSCrashReportFilterDoctor.m
//
//  Created by Karl Stenerud on 2024-09-05.
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

#import "KSCrashReportFilterDoctor.h"
#import "KSCrashDoctor.h"
#import "KSCrashReport.h"
#import "KSCrashReportFields.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

@interface KSCrashReportFilterDoctor ()

@end

@implementation KSCrashReportFilterDoctor

+ (NSString *)diagnoseCrash:(NSDictionary *)crashReport
{
    return [[KSCrashDoctor new] diagnoseCrash:crashReport];
}

- (void)filterReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSMutableArray<id<KSCrashReport>> *filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for (KSCrashReportDictionary *report in reports) {
        if ([report isKindOfClass:[KSCrashReportDictionary class]] == NO) {
            KSLOG_ERROR(@"Unexpected non-dictionary report: %@", report);
            continue;
        }

        NSString *diagnose = [[self class] diagnoseCrash:report.value];
        NSMutableDictionary *crashReport = [report.value mutableCopy];
        if (diagnose != nil) {
            if (crashReport[KSCrashField_Crash] != nil) {
                NSMutableDictionary *crashDict = [crashReport[KSCrashField_Crash] mutableCopy];
                crashDict[KSCrashField_Diagnosis] = diagnose;
                crashReport[KSCrashField_Crash] = crashDict;
            }
            if (crashReport[KSCrashField_RecrashReport][KSCrashField_Crash] != nil) {
                NSMutableDictionary *recrashReport = [crashReport[KSCrashField_RecrashReport] mutableCopy];
                NSMutableDictionary *crashDict = [recrashReport[KSCrashField_Crash] mutableCopy];
                crashDict[KSCrashField_Diagnosis] = diagnose;
                recrashReport[KSCrashField_Crash] = crashDict;
                crashReport[KSCrashField_RecrashReport] = recrashReport;
            }
        }

        [filteredReports addObject:[KSCrashReportDictionary reportWithValue:crashReport]];
    }

    kscrash_callCompletion(onCompletion, filteredReports, nil);
}

@end
