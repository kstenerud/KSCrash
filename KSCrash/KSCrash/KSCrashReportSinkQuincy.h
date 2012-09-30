//
//  KSCrashReportSinkQuincy.h
//
//  Created by Karl Stenerud on 2012-02-26.
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


#import "KSCrashReportFilter.h"


/** Convert reports to Quincy usable format.
 *
 * Input: NSDictionary {"standard": NSDictionary, "apple": NSString Apple side-by-side format}
 * Output: NSString (Quincy format)
 */
@interface KSCrashReportFilterQuincy: NSObject <KSCrashReportFilter>

+ (KSCrashReportFilterQuincy*) filter;

+ (KSCrashReportFilterQuincy*) filterWithUserIDKey:(NSString*) userIDKey
                                   contactEmailKey:(NSString*) contactEmailKey
                               crashDescriptionKey:(NSString*) crashDescriptionKey;

- (id) initWithUserIDKey:(NSString*) userIDKey
         contactEmailKey:(NSString*) contactEmailKey
     crashDescriptionKey:(NSString*) crashDescriptionKey;

@end


/** Sends reports to Quincy.
 *
 * Input: NSString (Quincy format)
 * Output: Same as input (passthrough)
 */
@interface KSCrashReportSinkQuincy : NSObject <KSCrashReportFilter, KSCrashReportDefaultFilterSet>

/** Constructor.
 *
 * @param url The URL to connect to.
 *
 * @param onSuccess Called when reports are successfully pushed.
 *
 * @param onFailure Called when report pushing fails.
 */
+ (KSCrashReportSinkQuincy*) sinkWithURL:(NSURL*) url
                               onSuccess:(void(^)(NSString* response)) onSuccess;

/** Constructor.
 *
 * @param url The URL to connect to.
 *
 * @param onSuccess Called when reports are successfully pushed.
 */
- (id) initWithURL:(NSURL*) url
         onSuccess:(void(^)(NSString* response)) onSuccess;

- (NSArray*) defaultCrashReportFilterSetWithUserIDKey:(NSString*) userIDKey
                                      contactEmailKey:(NSString*) contactEmailKey
                                  crashDescriptionKey:(NSString*) crashDescriptionKey;

@end


@interface KSCrashReportSinkHockey : KSCrashReportSinkQuincy

/** Constructor.
 *
 * @param appIdentifier Your Hockey app identifier.
 *
 * @param onSuccess Called when reports are successfully pushed.
 */
+ (KSCrashReportSinkHockey*) sinkWithAppIdentifier:(NSString*) appIdentifier
                                         onSuccess:(void(^)(NSString* response)) onSuccess;

/** Constructor.
 *
 * @param appIdentifier Your Hockey app identifier.
 *
 * @param onSuccess Called when reports are successfully pushed.
 */
- (id) initWithAppIdentifier:(NSString*) appIdentifier
                   onSuccess:(void(^)(NSString* response)) onSuccess;

@end
