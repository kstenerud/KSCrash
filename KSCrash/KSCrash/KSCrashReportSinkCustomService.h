//
//  KSCrashReportSinkQuincyHockey.h
//
//  Created by David Velarde on 2014-03-10.
//
//  Copyright (c) 2014 David Velarde. All rights reserved.
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


/** Sends reports to a Custom Service made by you in JSON Format.
 *
 * Input: NSDictionary
 * Output: Same as input (passthrough)
 */
@interface KSCrashReportSinkCustomService : NSObject <KSCrashReportFilter>

/** If YES, wait until the host becomes reachable before trying to send.
 * If NO, it will attempt to send right away, and either succeed or fail.
 *
 * Default: YES
 */
@property(nonatomic,readwrite,assign) BOOL waitUntilReachable;

+ (KSCrashReportSinkCustomService *) sinkWithURL:(NSURL*) url
                               userIDKey:(NSString*) userIDKey
                         contactEmailKey:(NSString*) contactEmailKey
                    crashDescriptionKeys:(NSArray*) crashDescriptionKeys;

- (id) initWithURL:(NSURL*) url
         userIDKey:(NSString*) userIDKey
   contactEmailKey:(NSString*) contactEmailKey
crashDescriptionKeys:(NSArray*) crashDescriptionKeys;

- (id <KSCrashReportFilter>) defaultCrashReportFilterSet;


@end
