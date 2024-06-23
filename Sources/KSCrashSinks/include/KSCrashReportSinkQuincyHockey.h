//
//  KSCrashReportSinkQuincyHockey.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Sends reports to Quincy.
 *
 * Input: NSDictionary
 * Output: Same as input (passthrough)
 */
NS_SWIFT_NAME(CrashReportSinkQuincy)
@interface KSCrashReportSinkQuincy : NSObject <KSCrashReportFilter>

/** If YES, wait until the host becomes reachable before trying to send.
 * If NO, it will attempt to send right away, and either succeed or fail.
 *
 * Default: YES
 */
@property(nonatomic,readwrite,assign) BOOL waitUntilReachable;

+ (instancetype) sinkWithURL:(NSURL*) url
                   userIDKey:(nullable NSString*) userIDKey
                 userNameKey:(nullable NSString*) userNameKey
             contactEmailKey:(nullable NSString*) contactEmailKey
        crashDescriptionKeys:(nullable NSArray*) crashDescriptionKeys;

- (instancetype) initWithURL:(NSURL*) url
                   userIDKey:(nullable NSString*) userIDKey
                 userNameKey:(nullable NSString*) userNameKey
             contactEmailKey:(nullable NSString*) contactEmailKey
        crashDescriptionKeys:(nullable NSArray*) crashDescriptionKeys;

- (id <KSCrashReportFilter>) defaultCrashReportFilterSet;

@end


/** Sends reports to Hockey.
 *
 * Input: NSDictionary
 * Output: Same as input (passthrough)
 */
NS_SWIFT_NAME(CrashReportSinkHockey)
@interface KSCrashReportSinkHockey : KSCrashReportSinkQuincy

+ (instancetype) sinkWithAppIdentifier:(NSString*) appIdentifier
                             userIDKey:(nullable NSString*) userIDKey
                           userNameKey:(nullable NSString*) userNameKey
                       contactEmailKey:(nullable NSString*) contactEmailKey
                  crashDescriptionKeys:(nullable NSArray*) crashDescriptionKeys;

- (instancetype) initWithAppIdentifier:(NSString*) appIdentifier
                             userIDKey:(nullable NSString*) userIDKey
                           userNameKey:(nullable NSString*) userNameKey
                       contactEmailKey:(nullable NSString*) contactEmailKey
                  crashDescriptionKeys:(nullable NSArray*) crashDescriptionKeys;

@end

NS_ASSUME_NONNULL_END
