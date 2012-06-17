//
//  KSCrashReportFilterBasic.m
//  KSCrash
//
//  Created by Karl Stenerud on 5/11/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "KSCrashReportFilterBasic.h"
#import "ARCSafe_MemMgmt.h"


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
    
    onCompletion(filteredReports, YES, nil);
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
        [filteredReports addObject:converted];
    }
    
    onCompletion(filteredReports, YES, nil);
}

@end
