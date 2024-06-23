//
//  KSCrashReport.m
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

#import "KSCrashReport.h"

@implementation KSCrashReport

- (instancetype)initWithDictionaryValue:(NSDictionary<NSString *,id> *)dictionaryValue
                            stringValue:(NSString *)stringValue
                              dataValue:(NSData *)dataValue
{
    self = [super init];
    if(self != nil)
    {
        _dictionaryValue = [dictionaryValue copy];
        _stringValue = [stringValue copy];
        _dataValue = [dataValue copy];
    }
    return self;
}

+ (instancetype) reportWithDictionary:(NSDictionary<NSString*, id>*) dictionaryValue
{
    return [[KSCrashReport alloc] initWithDictionaryValue:dictionaryValue stringValue:nil dataValue:nil];
}

+ (instancetype) reportWithString:(NSString*) stringValue
{
    return [[KSCrashReport alloc] initWithDictionaryValue:nil stringValue:stringValue dataValue:nil];
}

+ (instancetype) reportWithData:(NSData*) dataValue
{
    return [[KSCrashReport alloc] initWithDictionaryValue:nil stringValue:nil dataValue:dataValue];
}

@end
