//
//  KSCrashReportFilterJSON.h
//
//  Created by Karl Stenerud on 2012-05-09.
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
#import "KSJSONCodecObjC.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Converts reports from dict to JSON.
 *
 * Input: NSDictionary
 * Output: NSData
 */
NS_SWIFT_NAME(CrashReportFilterJSONEncode)
@interface KSCrashReportFilterJSONEncode : NSObject <KSCrashReportFilter>

/** Initialize with encoding options.
 * @param options The JSON encoding options to use.
 * @return The initialized instance.
 */
- (instancetype)initWithOptions:(KSJSONEncodeOption)options;

/** Default initializer.
 * @return The initialized instance with KSJSONEncodeOptionNone.
 */
- (instancetype)init;

@end

/** Converts reports from JSON to dict.
 *
 * Input: NSData
 * Output: NSDictionary
 */
NS_SWIFT_NAME(CrashReportFilterJSONDecode)
@interface KSCrashReportFilterJSONDecode : NSObject <KSCrashReportFilter>

/** Initialize with decoding options.
 * @param options The JSON decoding options to use.
 * @return The initialized instance.
 */
- (instancetype)initWithOptions:(KSJSONDecodeOption)options;

/** Default initializer.
 * @return The initialized instance with KSJSONDecodeOptionNone.
 */
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
