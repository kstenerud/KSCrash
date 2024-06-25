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

typedef NS_ENUM(NSUInteger, KSCrashReportValueType) {
    KSCrashReportValueTypeDictionary,
    KSCrashReportValueTypeString,
    KSCrashReportValueTypeData,
} NS_SWIFT_NAME(CrashReportValueType);

/**
 * A class that represent a recorded crash report.
 * Under the hood it can be a dictionary or a serialized data (e.g. JSON data or formatted string).
 */
NS_SWIFT_NAME(CrashReport)
@interface KSCrashReport : NSObject

/**
 * The type of the value of this crash report (dictionary, string, data)
 */
@property (nonatomic, readonly, assign) KSCrashReportValueType valueType;

/**
 * A structured dictionary version of crash report.
 * This is usually a raw report that can be serialized to JSON.
 */
@property (nonatomic, readonly, nullable, copy) NSDictionary<NSString*, id>* dictionaryValue;

/**
 * A serialized or formatted string version of crash report.
 */
@property (nonatomic, readonly, nullable, copy) NSString* stringValue;

/**
 * A serialized data version of crash report.
 * This usually contain a serialized JSON.
 */
@property (nonatomic, readonly, nullable, copy) NSData* dataValue;

- (instancetype) init NS_UNAVAILABLE;
+ (instancetype) new NS_UNAVAILABLE;

- (instancetype) initWithValueType:(KSCrashReportValueType) valueType
                   dictionaryValue:(nullable NSDictionary<NSString*, id>*) dictionaryValue
                       stringValue:(nullable NSString*) stringValue
                         dataValue:(nullable NSData*) dataValue NS_DESIGNATED_INITIALIZER;

+ (instancetype) reportWithDictionary:(NSDictionary<NSString*, id>*) dictionaryValue;
+ (instancetype) reportWithString:(NSString*) stringValue;
+ (instancetype) reportWithData:(NSData*) dataValue;

@end

NS_ASSUME_NONNULL_END
