//
//  KSCrashReportFilterJSON.h
//  KSCrash
//
//  Created by Karl Stenerud on 5/9/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "KSCrashReportFilter.h"
#import "KSJSONCodecObjC.h"


/** Converts reports from dict to JSON.
 *
 * Input: NSDictionary
 * Output: NSData
 */
@interface KSCrashReportFilterJSONEncode : NSObject <KSCrashReportFilter>

+ (KSCrashReportFilterJSONEncode*) filterWithOptions:(KSJSONEncodeOption) options;

- (id) initWithOptions:(KSJSONEncodeOption) options;

@end


/** Converts reports from JSON to dict.
 *
 * Input: NSData
 * Output: NSDictionary
 */
@interface KSCrashReportFilterJSONDecode : NSObject <KSCrashReportFilter>

+ (KSCrashReportFilterJSONDecode*) filterWithOptions:(KSJSONDecodeOption) options;

- (id) initWithOptions:(KSJSONDecodeOption) options;

@end
