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
#import "KSCrashReportFilterBasic.h"
#import "KSCrashReportFilterJSON.h"
#import "KSCrashReportFilterGZip.h"
#import "KSCrashReportFields.h"

@implementation KSCrashFilterSets

+ (id<KSCrashReportFilter>) appleFmtWithUserAndSystemData:(KSAppleReportStyle) reportStyle
                                               compressed:(BOOL) compressed
{
    id<KSCrashReportFilter> appleFilter = [KSCrashReportFilterAppleFmt filterWithReportStyle:reportStyle];
    id<KSCrashReportFilter> userSystemFilter = [KSCrashReportFilterPipeline filterWithFilters:
                                                [KSCrashReportFilterSubset filterWithKeys:
                                                 @KSCrashField_System,
                                                 @KSCrashField_User,
                                                 nil],
                                                [KSCrashReportFilterJSONEncode filterWithOptions:KSJSONEncodeOptionPretty | KSJSONEncodeOptionSorted],
                                                [KSCrashReportFilterDataToString filter],
                                                nil];

    NSString* appleName = @"Apple Report";
    NSString* userSystemName = @"User & System Data";

    NSMutableArray* filters = [NSMutableArray arrayWithObjects:
                               [KSCrashReportFilterCombine filterWithFiltersAndKeys:
                                appleFilter, appleName,
                                userSystemFilter, userSystemName,
                                nil],
                               [KSCrashReportFilterConcatenate filterWithSeparatorFmt:@"\n\n-------- %@ --------\n\n" keys:
                                appleName, userSystemName, nil],
                               nil];

    if(compressed)
    {
        [filters addObject:[KSCrashReportFilterStringToData filter]];
        [filters addObject:[KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1]];
    }

    return [KSCrashReportFilterPipeline filterWithFilters:filters, nil];
}

@end
