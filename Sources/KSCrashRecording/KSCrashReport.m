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

- (instancetype) initWithValueType:(KSCrashReportValueType) valueType
                   dictionaryValue:(nullable NSDictionary<NSString*, id>*) dictionaryValue
                       stringValue:(nullable NSString*) stringValue
                         dataValue:(nullable NSData*) dataValue
{
    self = [super init];
    if(self != nil)
    {
        _valueType = valueType;
        _dictionaryValue = [dictionaryValue copy];
        _stringValue = [stringValue copy];
        _dataValue = [dataValue copy];
    }
    return self;
}

+ (instancetype) reportWithDictionary:(NSDictionary<NSString*, id>*) dictionaryValue
{
    return [[KSCrashReport alloc] initWithValueType:KSCrashReportValueTypeDictionary
                                    dictionaryValue:dictionaryValue
                                        stringValue:nil
                                          dataValue:nil];
}

+ (instancetype) reportWithString:(NSString*) stringValue
{
    return [[KSCrashReport alloc] initWithValueType:KSCrashReportValueTypeString
                                    dictionaryValue:nil
                                        stringValue:stringValue
                                          dataValue:nil];
}

+ (instancetype) reportWithData:(NSData*) dataValue
{
    return [[KSCrashReport alloc] initWithValueType:KSCrashReportValueTypeData
                                    dictionaryValue:nil
                                        stringValue:nil
                                          dataValue:dataValue];
}

- (BOOL) isEqual:(id) object
{
    if([object isKindOfClass:[KSCrashReport class]] == NO)
    {
        return NO;
    }
    KSCrashReport *other = object;
#define SAME_OR_EQUAL(GETTER) ((self.GETTER) == (other.GETTER) || [(self.GETTER) isEqual:(other.GETTER)])
    return self.valueType == other.valueType
        && SAME_OR_EQUAL(stringValue)
        && SAME_OR_EQUAL(dictionaryValue)
        && SAME_OR_EQUAL(dataValue);
#undef SAME_OR_EQUAL
}

- (NSString*) description
{
    switch(self.valueType)
    {
        case KSCrashReportValueTypeDictionary:
            return [self.dictionaryValue description];
        case KSCrashReportValueTypeString:
            return [self.stringValue description];
        case KSCrashReportValueTypeData:
            return [self.dataValue description];
    }
}

@end
