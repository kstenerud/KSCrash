//
//  KSCrashFilterSets.m
//
//  Created by Karl Stenerud on 2012-08-21.
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

#import "KSCrashReportFilterSets.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportFilterBasic.h"
#import "KSCrashReportFilterGZip.h"
#import "KSCrashReportFilterJSON.h"

@implementation KSCrashFilterSets

+ (id<KSCrashReportFilter>)appleFmtWithUserAndSystemData:(KSAppleReportStyle)reportStyle compressed:(BOOL)compressed
{
    NSString *const kAppleReportName = @"Apple Report";
    NSString *const kUserSystemDataName = @"User & System Data";

    id<KSCrashReportFilter> appleFilter = [[KSCrashReportFilterAppleFmt alloc] initWithReportStyle:reportStyle];
    id<KSCrashReportFilter> userSystemFilter = [self createUserSystemFilterPipeline];

    id<KSCrashReportFilter> combineFilter = [[KSCrashReportFilterCombine alloc]
        initWithFilters:@{ kAppleReportName : appleFilter, kUserSystemDataName : userSystemFilter }];

    id<KSCrashReportFilter> concatenateFilter =
        [[KSCrashReportFilterConcatenate alloc] initWithSeparatorFmt:@"\n\n-------- %@ --------\n\n"
                                                                keys:@[ kAppleReportName, kUserSystemDataName ]];

    NSMutableArray *mainFilters = [NSMutableArray arrayWithObjects:combineFilter, concatenateFilter, nil];

    if (compressed) {
        [mainFilters addObject:[KSCrashReportFilterStringToData new]];
        [mainFilters addObject:[[KSCrashReportFilterGZipCompress alloc] initWithCompressionLevel:-1]];
    }

    return [[KSCrashReportFilterPipeline alloc] initWithFilters:mainFilters];
}

+ (id<KSCrashReportFilter>)createUserSystemFilterPipeline
{
    return [[KSCrashReportFilterPipeline alloc] initWithFilters:@[
        [[KSCrashReportFilterSubset alloc] initWithKeys:@[ KSCrashField_System, KSCrashField_User ]],
        [[KSCrashReportFilterJSONEncode alloc] initWithOptions:KSJSONEncodeOptionPretty | KSJSONEncodeOptionSorted],
        [KSCrashReportFilterDataToString new]
    ]];
}

@end
