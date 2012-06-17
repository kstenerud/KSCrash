//
//  KSCrashReportSinkConsole.h
//  KSCrash
//
//  Created by Karl Stenerud on 5/11/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "KSCrashReportFilter.h"

@interface KSCrashReportSinkConsole : NSObject <KSCrashReportFilter, KSCrashReportDefaultFilterSet>

+ (KSCrashReportSinkConsole*) filter;

@end
