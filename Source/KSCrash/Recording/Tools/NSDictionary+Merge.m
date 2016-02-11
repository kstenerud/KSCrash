//
//  NSDictionary+Merge.m
//
//  Created by Karl Stenerud on 2012-10-01.
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


#import "NSDictionary+Merge.h"


@implementation NSDictionary (KSMerge)

- (NSDictionary*) mergedInto:(NSDictionary*) dest
{
    if([dest count] == 0)
    {
        return self;
    }
    if([self count] == 0)
    {
        return dest;
    }

    NSMutableDictionary* dict = [dest mutableCopy];
    for(id key in [self allKeys])
    {
        id srcEntry = [self objectForKey:key];
        id dstEntry = [dest objectForKey:key];
        if([dstEntry isKindOfClass:[NSDictionary class]] &&
           [srcEntry isKindOfClass:[NSDictionary class]])
        {
            srcEntry = [srcEntry mergedInto:dstEntry];
        }
        [dict setObject:srcEntry forKey:key];
    }
    return dict;
}

@end

@interface NSDictionary_Merge_O8FG4A : NSObject @end @implementation NSDictionary_Merge_O8FG4A @end
