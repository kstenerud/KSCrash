//
//  KSCrashReportFilterGZip.h
//  KSCrash
//
//  Created by Karl Stenerud on 5/10/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "KSCrashReportFilter.h"

/** Gzip compresses reports.
 *
 * Input: NSData
 * Output: NSData
 */
@interface KSCrashReportFilterGZipCompress : NSObject <KSCrashReportFilter>

+ (KSCrashReportFilterGZipCompress*) filterWithCompressionLevel:(int) compressionLevel;

- (id) initWithCompressionLevel:(int) compressionLevel;

@end

/** Gzip decompresses reports.
 *
 * Input: NSData
 * Output: NSData
 */
@interface KSCrashReportFilterGZipDecompress : NSObject <KSCrashReportFilter>

+ (KSCrashReportFilterGZipDecompress*) filter;

@end
