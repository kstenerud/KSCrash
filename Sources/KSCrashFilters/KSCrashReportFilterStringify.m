//
//  KSCrashReportFilterStringify.m
//  KSCrash
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

#import "KSCrashReportFilterStringify.h"
#import "KSCrashReport.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

@implementation KSCrashReportFilterStringify

+ (instancetype) filter
{
    return [[self alloc] init];
}

- (NSString*) stringifyReport:(KSCrashReport*) report
{
    if(report.stringValue != nil)
    {
        return report.stringValue;
    }
    if(report.dataValue != nil)
    {
        return [[NSString alloc] initWithData:report.dataValue encoding:NSUTF8StringEncoding];
    }
    if(report.dictionaryValue != nil)
    {
        if([NSJSONSerialization isValidJSONObject:report.dictionaryValue])
        {
            NSData* data = [NSJSONSerialization dataWithJSONObject:report.dictionaryValue options:0 error:nil];
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        return [NSString stringWithFormat:@"%@", report.dictionaryValue];
    }
    return [NSString stringWithFormat:@"%@", report];
}

- (void) filterReports:(NSArray<KSCrashReport*>*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    NSMutableArray<KSCrashReport*>* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(KSCrashReport* report in reports)
    {
        NSString *reportString = [self stringifyReport:report];
        [filteredReports addObject:[KSCrashReport reportWithString:reportString]];
    }
    
    kscrash_callCompletion(onCompletion, filteredReports, YES, nil);
}

@end
