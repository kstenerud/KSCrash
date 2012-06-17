//
//  KSCrashReportFilterBasic.h
//  KSCrash
//
//  Created by Karl Stenerud on 5/11/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "KSCrashReportFilter.h"

@interface KSCrashReportFilterDataToString : NSObject <KSCrashReportFilter>

+ (KSCrashReportFilterDataToString*) filter;

@end


@interface KSCrashReportFilterStringToData : NSObject <KSCrashReportFilter>

+ (KSCrashReportFilterStringToData*) filter;

@end
