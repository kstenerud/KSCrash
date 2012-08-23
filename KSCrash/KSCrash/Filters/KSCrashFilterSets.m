//
//  KSCrashFilterSets.m
//  KSCrash
//
//  Created by Karl Stenerud on 8/21/12.
//
//

#import "KSCrashFilterSets.h"
#import "KSCrashReportFilterBasic.h"
#import "KSCrashReportFilterJSON.h"
#import "KSCrashReportFilterGZip.h"

@implementation KSCrashFilterSets

+ (id<KSCrashReportFilter>) appleFmtWithUserAndSystemData:(KSAppleReportStyle) reportStyle
                                               compressed:(BOOL) compressed
{
    id<KSCrashReportFilter> appleFilter = [KSCrashReportFilterAppleFmt filterWithReportStyle:reportStyle];
    id<KSCrashReportFilter> userSystemFilter = [KSCrashReportFilterPipeline filterWithFilters:
                                                [KSCrashReportFilterSubset filterWithKeys:@"system", @"user", nil],
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
