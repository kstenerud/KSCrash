//
//  KSCrashReportFilterBasic.m
//
//  Created by Karl Stenerud on 2012-05-11.
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


#import "KSCrashReportFilterBasic.h"
#import "ARCSafe_MemMgmt.h"
#import "KSSafeCollections.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"


static inline void callCompletion(KSCrashReportFilterCompletion onCompletion,
                                  NSArray* filteredReports,
                                  BOOL completed,
                                  NSError* error)
{
    if(onCompletion)
    {
        onCompletion(filteredReports, completed, error);
    }
}

static inline NSError* makeNSError(NSString* domain, NSInteger code, NSString* fmt, ...)
{
    va_list args;
    va_start(args, fmt);

    NSString* desc = as_autorelease([[NSString alloc] initWithFormat:fmt
                                                           arguments:args]);
    va_end(args);

    return [NSError errorWithDomain:domain
                               code:code
                           userInfo:[NSDictionary dictionaryWithObject:desc
                                                                forKey:NSLocalizedDescriptionKey]];
}


@implementation KSCrashReportFilterDataToString

+ (KSCrashReportFilterDataToString*) filter
{
    return as_autorelease([[self alloc] init]);
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSData* report in reports)
    {
        NSString* converted = as_autorelease([[NSString alloc] initWithData:report
                                                                   encoding:NSUTF8StringEncoding]);
        [filteredReports addObject:converted];
    }

    callCompletion(onCompletion, filteredReports, YES, nil);
}

@end


@implementation KSCrashReportFilterStringToData

+ (KSCrashReportFilterStringToData*) filter
{
    return as_autorelease([[self alloc] init]);
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    NSMutableArray* filteredReports = [NSMutableArray arrayWithCapacity:[reports count]];
    for(NSString* report in reports)
    {
        NSData* converted = [report dataUsingEncoding:NSUTF8StringEncoding];
        if(converted == nil)
        {
            callCompletion(onCompletion, filteredReports,
                           NO,
                           makeNSError([[self class] description],
                                       0,
                                       @"Could not convert report to UTF-8"));
            return;
        }
        else
        {
            [filteredReports addObject:converted];
        }
    }

    callCompletion(onCompletion, filteredReports, YES, nil);
}

@end
