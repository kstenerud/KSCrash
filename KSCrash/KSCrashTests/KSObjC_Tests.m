//
//  KSObjC_Tests.m
//
//  Created by Karl Stenerud on 2012-08-30.
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


#import <SenTestingKit/SenTestingKit.h>
#import "KSObjC.h"


@interface KSObjC_Tests : SenTestCase @end

@implementation KSObjC_Tests

- (void) testGetObjectClassName
{
    NSObject* obj = [NSObject new];
    const char* expected = "NSObject";
    const char* actual = ksobjc_className((__bridge void *)(obj));
    STAssertTrue(actual != NULL, @"result was NULL");
    if(actual != NULL)
    {
        bool equal = strncmp(expected, actual, strlen(expected)+1) == 0;
        STAssertTrue(equal, @"expected %s but got %s", expected, actual);
    }
}

- (void) testGetClassName
{
    Class cls = [NSString class];
    const char* expected = "NSString";
    const char* actual = ksobjc_className((__bridge void *)(cls));
    STAssertTrue(actual != NULL, @"result was NULL");
    if(actual != NULL)
    {
        bool equal = strncmp(expected, actual, strlen(expected)+1) == 0;
        STAssertTrue(equal, @"expected %s but got %s", expected, actual);
    }
}

- (void) testGetClassNameInvalidMemory
{
    void* ptr = (void*) -1;
    const char* name = ksobjc_className(ptr);
    STAssertTrue(name == NULL, @"result should be NULL");
}

- (void) testGetClassNameNullPtr
{
    void* ptr = NULL;
    const char* name = ksobjc_className(ptr);
    STAssertTrue(name == NULL, @"result should be NULL");
}

- (void) testGetClassNamePartial
{
    struct objc_object objcClass;
    objcClass.isa = (__bridge Class)((void*)-1);
    const char* name = ksobjc_className(&objcClass);
    STAssertTrue(name == NULL, @"result should be NULL");
}

- (void) testClassIsClass
{
    Class cls = [KSObjC_Tests class];
    ObjCObjectType objectType = ksobjc_objectType((__bridge void *)(cls));
    STAssertTrue(objectType == kObjCObjectTypeClass, @"");
}

- (void) testObjectIsObject
{
    id object = [KSObjC_Tests new];
    ObjCObjectType objectType = ksobjc_objectType((__bridge void *)(object));
    STAssertTrue(objectType == kObjCObjectTypeObject, @"");
}

@end
