//
// RFC3339DateTool.m
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


#import "RFC3339DateTool.h"


@implementation RFC3339DateTool

static NSDateFormatter* g_formatter;

+ (void) initialize
{
    g_formatter = [[NSDateFormatter alloc] init];
    NSLocale* locale = [[NSLocale alloc]
                        initWithLocaleIdentifier:@"en_US_POSIX"];
    [g_formatter setLocale:locale];
    [g_formatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
    [g_formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
}

+ (NSString*) stringFromDate:(NSDate*) date
{
    if(![date isKindOfClass:[NSDate class]])
    {
        return nil;
    }
    return [g_formatter stringFromDate:date];
}

+ (NSDate*) dateFromString:(NSString*) string
{
    if(![string isKindOfClass:[NSString class]])
    {
        return nil;
    }
    return [g_formatter dateFromString:string];
}

+ (NSString*) stringFromUNIXTimestamp:(unsigned long long) timestamp
{
    return [self stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}

+ (unsigned long long) UNIXTimestampFromString:(NSString*) string
{
    return (unsigned long long)[[self dateFromString:string] timeIntervalSince1970];
}

@end
