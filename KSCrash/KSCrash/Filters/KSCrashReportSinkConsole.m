//
//  KSCrashReportSinkConsole.m
//  KSCrash
//
//  Created by Karl Stenerud on 5/11/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "KSCrashReportSinkConsole.h"
#import "ARCSafe_MemMgmt.h"
#import "KSCrashReportFilterAppleFmt.h"

@implementation KSCrashReportSinkConsole

+ (KSCrashReportSinkConsole*) filter
{
    return as_autorelease([[self alloc] init]);
}

- (NSArray*) defaultCrashReportFilterSet
{
    return [NSArray arrayWithObjects:
            [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicated],
            self,
            nil];
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    int i = 0;
    for(NSString* report in reports)
    {
        NSLog(@"Report %d:\n%@", ++i, report);
    }
    
    onCompletion(reports, YES, nil);
}


@end
