//
// RFC3339DateTool.h
//
// Copyright 2010 Karl Stenerud
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


/**
 * Tool for converting to/from RFC3339 compliant date strings.
 */
@interface RFC3339DateTool : NSObject

/** Convert a date to an RFC3339 string representation.
 *
 * @param date The date to convert.
 *
 * @return The RFC3339 date string.
 */
+ (NSString*) stringFromDate:(NSDate*) date;

/** Convert an RFC3339 string representation to a date.
 *
 * @param string The string to convert.
 *
 * @return The date.
 */
+ (NSDate*) dateFromString:(NSString*) string;

/** Convert a UNIX timestamp to an RFC3339 string representation.
 *
 * @param date The date to convert.
 *
 * @return The RFC3339 date string.
 */
+ (NSString*) stringFromUNIXTimestamp:(unsigned long long) timestamp;

/** Convert an RFC3339 string representation to a UNIX timestamp.
 *
 * @param string The string to convert.
 *
 * @return The timestamp.
 */
+ (unsigned long long) UNIXTimestampFromString:(NSString*) string;

@end
