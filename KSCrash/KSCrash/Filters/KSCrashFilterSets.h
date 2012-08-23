//
//  KSCrashFilterSets.h
//  KSCrash
//
//  Created by Karl Stenerud on 8/21/12.
//
//

#import "KSCrashReportFilter.h"
#import "KSCrashReportFilterAppleFmt.h"

@interface KSCrashFilterSets : NSObject

+ (id<KSCrashReportFilter>) appleFmtWithUserAndSystemData:(KSAppleReportStyle) reportStyle
                                               compressed:(BOOL) compressed;

@end
