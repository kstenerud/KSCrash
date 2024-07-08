//
//  KSCrashReport.h
//
//  Created by Nikolay Volosatov on 2024-06-23.
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A protocol that represent a recorded or a filtered crash report.
 *
 * @see `KSCrashReportDictionary`, `KSCrashReportString` and `KSCrashReportData` are
 *      the types of reports that provided and used by KSCrash.
 */
NS_SWIFT_NAME(CrashReport)
@protocol KSCrashReport <NSObject>

/**
 * An underlying report value of any type (string, dictionary, data etc)
 *
 * @note It's preferable to safely cast to one of the implementations of `KSCrashReport`
 *       and use a strongly typed value from there.
 */
@property(nonatomic, readonly, nullable, strong) id untypedValue;

@end

NS_SWIFT_NAME(CrashReportDictionary)
@interface KSCrashReportDictionary : NSObject <KSCrashReport>

/**
 * A structured dictionary version of crash report.
 * This is usually a raw report that can be serialized to JSON.
 */
@property(nonatomic, readonly, copy) NSDictionary<NSString *, id> *value;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

+ (instancetype)reportWithValue:(NSDictionary<NSString *, id> *)value;

@end

NS_SWIFT_NAME(CrashReportString)
@interface KSCrashReportString : NSObject <KSCrashReport>

/**
 * A serialized or formatted string version of crash report.
 */
@property(nonatomic, readonly, copy) NSString *value;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

+ (instancetype)reportWithValue:(NSString *)value;

@end

NS_SWIFT_NAME(CrashReportData)
@interface KSCrashReportData : NSObject <KSCrashReport>

/**
 * A serialized data version of crash report.
 * This usually contain a serialized JSON.
 */
@property(nonatomic, readonly, copy) NSData *value;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

+ (instancetype)reportWithValue:(NSData *)value;

@end

NS_ASSUME_NONNULL_END
