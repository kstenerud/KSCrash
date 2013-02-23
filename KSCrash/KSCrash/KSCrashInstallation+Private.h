//
//  KSCrashReportFieldProperties.h
//
//  Created by Karl Stenerud on 2013-02-10.
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

#import "KSCrashInstallation.h"
#import "ARCSafe_MemMgmt.h"

#define IMPLEMENT_REPORT_KEY_PROPERTY(NAME, NAMEUPPER) \
@synthesize NAME##Key = _##NAME##Key; \
- (void) set##NAMEUPPER##Key:(NSString*) value \
{ \
    as_autorelease(_##NAME##Key); \
    _##NAME##Key = as_retain(value); \
    [self reportFieldForProperty:@#NAME setKey:value]; \
}

#define IMPLEMENT_REPORT_VALUE_PROPERTY(NAME, NAMEUPPER, TYPE) \
@synthesize NAME = _##NAME; \
- (void) set##NAMEUPPER:(TYPE) value \
{ \
    as_autorelease(_##NAME); \
    _##NAME = as_retain(value); \
    [self reportFieldForProperty:@#NAME setValue:value]; \
}

#define IMPLEMENT_REPORT_PROPERTY(NAMESPACE, NAME, NAMEUPPER, TYPE) \
IMPLEMENT_REPORT_VALUE_PROPERTY(NAME, NAMEUPPER, TYPE) \
IMPLEMENT_REPORT_KEY_PROPERTY(NAME, NAMEUPPER)


@interface KSCrashInstallation ()

- (id) initWithMaxReportFieldCount:(size_t) maxReportFieldCount
                requiredProperties:(NSArray*) requiredProperties;

- (void) reportFieldForProperty:(NSString*) propertyName setKey:(id) key;

- (void) reportFieldForProperty:(NSString*) propertyName setValue:(id) value;

- (id<KSCrashReportFilter>) sink;

@end
