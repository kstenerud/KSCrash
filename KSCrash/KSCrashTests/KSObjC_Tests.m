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
#import "ARCSafe_MemMgmt.h"
#import <objc/runtime.h>

#import "KSObjC.h"


@interface SomeObjCClass: NSObject
{
    int someIvar;
    id anotherIvar;
}

@property(nonatomic,readwrite,assign) int someIvar;

@end

@implementation SomeObjCClass

@synthesize someIvar = someIvar;

@end

@interface SomeSubclass: SomeObjCClass

@end

@implementation SomeSubclass

@end

@interface KSObjC_Tests : SenTestCase @end

@implementation KSObjC_Tests

- (NSArray*) componentsOfBasicDescription:(NSString*) description
{
    NSError* error = nil;
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"^<(\\w+): [^>]+>" options:0 error:&error];
    NSTextCheckingResult* result = [regex firstMatchInString:description options:0 range:NSMakeRange(0, [description length])];
    NSString* className = [description substringWithRange:[result rangeAtIndex:1]];
    return [NSArray arrayWithObjects:className, nil];
}

- (NSArray*) componentsOfComplexDescription:(NSString*) description
{
    NSError* error = nil;
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"^<(\\w+): [^>]+>: (.*)$" options:0 error:&error];
    NSTextCheckingResult* result = [regex firstMatchInString:description options:0 range:NSMakeRange(0, [description length])];
    NSString* className = [description substringWithRange:[result rangeAtIndex:1]];
    NSString* theRest = [description substringWithRange:[result rangeAtIndex:2]];
    return [NSArray arrayWithObjects:className, theRest, nil];
}

- (void) testObjectTypeInvalidMemory
{
    void* ptr = (void*) -1;
    KSObjCType type = ksobjc_objectType(ptr);
    STAssertEquals(type, KSObjCTypeUnknown, @"Type was %d", type);
}

- (void) testObjectTypeNullPtr
{
    void* ptr = NULL;
    KSObjCType type = ksobjc_objectType(ptr);
    STAssertEquals(type, KSObjCTypeUnknown, @"Type was %d", type);
}

- (void) testObjectTypeCorrupt
{
    struct objc_object objcClass;
    objcClass.isa = (__bridge Class)((void*)-1);
    KSObjCType type = ksobjc_objectType(&objcClass);
    STAssertEquals(type, KSObjCTypeUnknown, @"Type was %d", type);
}

- (void) testObjectTypeClass
{
    Class cls = [KSObjC_Tests class];
    void* clsPtr = (as_bridge void*)cls;
    KSObjCType type = ksobjc_objectType(clsPtr);
    STAssertTrue(type == KSObjCTypeClass, @"Type was %d", type);
}

- (void) testObjectTypeObject
{
    id object = [KSObjC_Tests new];
    KSObjCType type = ksobjc_objectType((as_bridge void *)(object));
    STAssertTrue(type == KSObjCTypeObject, @"");
}

- (void) testObjectTypeObject2
{
    id object = @"Test";
    KSObjCType type = ksobjc_objectType((as_bridge void *)(object));
    STAssertTrue(type == KSObjCTypeObject, @"");
}

- (void) testObjectTypeBlock
{
    dispatch_block_t block;
    const void* blockPtr;
    const void* isaPtr;
    KSObjCType type;
    
    block = ^{};
    blockPtr = (as_bridge void*)block;
    isaPtr = ksobjc_isaPointer(blockPtr);
    type = ksobjc_objectType(isaPtr);
    STAssertTrue(type == KSObjCTypeBlock, @"");
    
    block = as_autorelease([^{} copy]);
    blockPtr = (as_bridge void*)block;
    isaPtr = ksobjc_isaPointer(blockPtr);
    type = ksobjc_objectType(isaPtr);
    STAssertTrue(type == KSObjCTypeBlock, @"");
    
    block = ^{NSLog(@"%d", type);};
    blockPtr = (as_bridge void*)block;
    isaPtr = ksobjc_isaPointer(blockPtr);
    type = ksobjc_objectType(isaPtr);
    STAssertTrue(type == KSObjCTypeBlock, @"");
    
    block = as_autorelease([^{NSLog(@"%d", type);} copy]);
    blockPtr = (as_bridge void*)block;
    isaPtr = ksobjc_isaPointer(blockPtr);
    type = ksobjc_objectType(isaPtr);
    STAssertTrue(type == KSObjCTypeBlock, @"");
    
    __block int value = 0;
    
    block = ^{value = 1;};
    blockPtr = (as_bridge void*)block;
    isaPtr = ksobjc_isaPointer(blockPtr);
    type = ksobjc_objectType(isaPtr);
    STAssertTrue(type == KSObjCTypeBlock, @"");
    
    block = as_autorelease([^{value = 1;} copy]);
    blockPtr = (as_bridge void*)block;
    isaPtr = ksobjc_isaPointer(blockPtr);
    type = ksobjc_objectType(isaPtr);
    STAssertTrue(type == KSObjCTypeBlock, @"");
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

- (void) testGetObjectClassName
{
    NSObject* obj = [NSObject new];
    void* objPtr = (as_bridge void*)obj;
    KSObjCType type = ksobjc_objectType(objPtr);
    STAssertEquals(type, KSObjCTypeObject, @"");

    const char* expected = "NSObject";
    const void* classPtr = ksobjc_isaPointer(objPtr);
    const char* actual = ksobjc_className(classPtr);
    STAssertTrue(actual != NULL, @"result was NULL");
    if(actual != NULL)
    {
        bool equal = strncmp(expected, actual, strlen(expected)+1) == 0;
        STAssertTrue(equal, @"expected %s but got %s", expected, actual);
    }
}

- (void) testStringIsValid
{
    NSString* string = @"test";
    void* stringPtr = (as_bridge void*)string;
    bool valid = ksobjc_isValidObject(stringPtr);
    STAssertTrue(valid, @"");
}

- (void) testStringIsValid2
{
    NSString* string = [NSString stringWithFormat:@"%d", 1];
    void* stringPtr = (as_bridge void*)string;
    bool valid = ksobjc_isValidObject(stringPtr);
    STAssertTrue(valid, @"");
}

- (void) testStringIsValid3
{
    NSMutableString* string = [NSMutableString stringWithFormat:@"%d", 1];
    void* stringPtr = (as_bridge void*)string;
    bool valid = ksobjc_isValidObject(stringPtr);
    STAssertTrue(valid, @"");
}

- (void) testCFStringIsValid
{
    char* expected = "test";
    size_t expectedLength = strlen(expected);
    CFStringRef stringPtr = CFStringCreateWithBytes(NULL, (uint8_t*)expected, (CFIndex)expectedLength, kCFStringEncodingUTF8, FALSE);
    bool valid = ksobjc_isValidObject(stringPtr);
    STAssertTrue(valid, @"");
    CFRelease(stringPtr);
}

- (void) testStringLength
{
    NSString* string = @"test";
    void* stringPtr = (as_bridge void*)string;
    size_t expectedLength = [string length];
    size_t length = ksobjc_stringLength(stringPtr);
    STAssertEquals(length, expectedLength, @"");
}

- (void) testStringLength2
{
    NSString* string = [NSString stringWithFormat:@"%d", 1];
    void* stringPtr = (as_bridge void*)string;
    size_t expectedLength = [string length];
    size_t length = ksobjc_stringLength(stringPtr);
    STAssertEquals(length, expectedLength, @"");
}

- (void) testStringLength3
{
    NSMutableString* string = [NSMutableString stringWithFormat:@"%d", 1];
    void* stringPtr = (as_bridge void*)string;
    size_t expectedLength = [string length];
    size_t length = ksobjc_stringLength(stringPtr);
    STAssertEquals(length, expectedLength, @"");
}

- (void) testCFStringLength
{
    char* expected = "test";
    size_t expectedLength = strlen(expected);
    CFStringRef stringPtr = CFStringCreateWithBytes(NULL, (uint8_t*)expected, (CFIndex)expectedLength, kCFStringEncodingUTF8, FALSE);
    size_t length = ksobjc_stringLength(stringPtr);
    STAssertEquals(length, expectedLength, @"");
}

- (void) testCopyStringContents
{
    NSString* string = @"test";
    const char* expected = [string UTF8String];
    size_t expectedLength = [string length];
    char actual[100];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContents2
{
    NSString* string = [NSString stringWithFormat:@"%d", 1];
    const char* expected = [string UTF8String];
    size_t expectedLength = [string length];
    char actual[100];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContents3
{
    NSMutableString* string = [NSMutableString stringWithFormat:@"%d", 1];
    const char* expected = [string UTF8String];
    size_t expectedLength = [string length];
    char actual[100];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContentsEmpty
{
    NSString* string = @"";
    const char* expected = [string UTF8String];
    size_t expectedLength = [string length];
    char actual[100];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContentsTruncate
{
    NSString* string = @"A longish string";
    const char* expected = "A lo";
    size_t expectedLength = 4;
    char actual[5];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContents0Length
{
    NSString* string = @"A longish string";
    const char expected = 0x7f;
    size_t expectedLength = 0;
    char actual = expected;
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, &actual, 0);
    STAssertEquals(copied, expectedLength, @"");
    STAssertEquals(actual, expected, @"");
}

- (void) testCopyStringContentsUTF16
{
    NSString* string = @"123 テスト 123";
    const char* expected = [string UTF8String];
    size_t expectedLength = strlen(expected);
    char actual[100];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContentsUTF16_2Byte
{
    NSString* string = @"Ÿ";
    const char* expected = [string UTF8String];
    size_t expectedLength = strlen(expected);
    char actual[100];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContentsUTF16_3Byte
{
    NSString* string = @"ঠ";
    const char* expected = [string UTF8String];
    size_t expectedLength = strlen(expected);
    char actual[100];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContentsUTF16_4Byte
{
    NSString* string = @"𐅐";
    const char* expected = [string UTF8String];
    size_t expectedLength = strlen(expected);
    char actual[100];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContentsMutable
{
    NSMutableString* string = [NSMutableString stringWithFormat:@"%@", @"test"];
    const char* expected = [string UTF8String];
    size_t expectedLength = [string length];
    char actual[100];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContentsMutableLong
{
    NSMutableString* string = [NSMutableString string];
    for(int i = 0; i < 1000; i++)
    {
        [string appendString:@"1"];
    }
    const char* expected = [string UTF8String];
    size_t expectedLength = [string length];
    char actual[2000];
    size_t copied = ksobjc_copyStringContents((as_bridge void*)string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testCopyStringContentsCFString
{
    char* expected = "test";
    size_t expectedLength = strlen(expected);
    CFStringRef string = CFStringCreateWithBytes(NULL, (uint8_t*)expected, (CFIndex)expectedLength, kCFStringEncodingUTF8, FALSE);
    char actual[100];
    size_t copied = ksobjc_copyStringContents(string, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
    CFRelease(string);
}

- (void) testStringDescription
{
    NSString* string = @"A string";
    void* stringPtr = (as_bridge void*)string;
    NSString* expectedClassName = [NSString stringWithCString:class_getName([string class]) encoding:NSUTF8StringEncoding];
    NSString* expectedTheRest = @"\"A string\"";
    char buffer[100];
    size_t copied = ksobjc_getDescription(stringPtr, buffer, sizeof(buffer));
    STAssertTrue(copied > 0, @"");
    NSString* description = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
    NSArray* components = [self componentsOfComplexDescription:description];
    NSString* className = [components objectAtIndex:0];
    NSString* theRest = [components objectAtIndex:1];
    STAssertEqualObjects(className, expectedClassName, @"");
    STAssertEqualObjects(theRest, expectedTheRest, @"");
}

- (void) testURLIsValid
{
    NSURL* URL =  [NSURL URLWithString:@"http://www.google.com"];
    void* URLPtr = (as_bridge void*)URL;
    bool valid = ksobjc_isValidObject(URLPtr);
    STAssertTrue(valid, @"");
}

- (void) testCopyURLContents
{
    NSURL* URL =  [NSURL URLWithString:@"http://www.google.com"];
    NSString* string = [URL absoluteString];
    const char* expected = [string UTF8String];
    size_t expectedLength = [string length];
    char actual[100];
    size_t copied = ksobjc_copyURLContents((as_bridge void*)URL, actual, sizeof(actual));
    STAssertEquals(copied, expectedLength, @"");
    int result = strcmp(actual, expected);
    STAssertTrue(result == 0, @"String %s did not equal %s", actual, expected);
}

- (void) testURLDescription
{
    NSURL* URL =  [NSURL URLWithString:@"http://www.google.com"];
    void* URLPtr = (as_bridge void*)URL;
    NSString* expectedClassName = [NSString stringWithCString:class_getName([URL class]) encoding:NSUTF8StringEncoding];
    NSString* expectedTheRest = @"\"http://www.google.com\"";
    char buffer[100];
    size_t copied = ksobjc_getDescription(URLPtr, buffer, sizeof(buffer));
    STAssertTrue(copied > 0, @"");
    NSString* description = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
    NSArray* components = [self componentsOfComplexDescription:description];
    NSString* className = [components objectAtIndex:0];
    NSString* theRest = [components objectAtIndex:1];
    STAssertEqualObjects(className, expectedClassName, @"");
    STAssertEqualObjects(theRest, expectedTheRest, @"");
}

- (void) testDateIsValid
{
    NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate:10.0];
    void* datePtr = (as_bridge void*)date;
    bool valid = ksobjc_isValidObject(datePtr);
    STAssertTrue(valid, @"");
}

- (void) testGetDateContents
{
    NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate:10.0];
    void* datePtr = (as_bridge void*)date;
    NSTimeInterval expected = [date timeIntervalSinceReferenceDate];
    NSTimeInterval actual = ksobjc_dateContents(datePtr);
    STAssertEquals(actual, expected, @"");
}

- (void) testDateDescription
{
    NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate:10.0];
    void* datePtr = (as_bridge void*)date;
    NSString* expectedClassName = [NSString stringWithCString:class_getName([date class]) encoding:NSUTF8StringEncoding];
    NSString* expectedTheRest = @"10.000000";
    char buffer[100];
    size_t copied = ksobjc_getDescription(datePtr, buffer, sizeof(buffer));
    STAssertTrue(copied > 0, @"");
    NSString* description = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
    NSArray* components = [self componentsOfComplexDescription:description];
    NSString* className = [components objectAtIndex:0];
    NSString* theRest = [components objectAtIndex:1];
    STAssertEqualObjects(className, expectedClassName, @"");
    STAssertEqualObjects(theRest, expectedTheRest, @"");
}

- (void) testArrayIsValid
{
    NSArray* array = [NSArray array];
    void* arrayPtr = (as_bridge void*)array;
    bool valid = ksobjc_isValidObject(arrayPtr);
    STAssertTrue(valid, @"");
}

- (void) testMutableArrayIsValid
{
    NSMutableArray* array = [NSMutableArray array];
    void* arrayPtr = (as_bridge void*)array;
    bool valid = ksobjc_isValidObject(arrayPtr);
    STAssertTrue(valid, @"");
}

- (void) testCFArrayIsValid
{
    const void* values[4] =
    {
        @"1",
        @"2",
        @"3",
        @"4",
    };
    CFArrayRef arrayPtr = CFArrayCreate(NULL, values, 4, NULL);
    bool valid = ksobjc_isValidObject(arrayPtr);
    STAssertTrue(valid, @"");
    CFRelease(arrayPtr);
}

- (void) testEmptyCFMutableArrayIsValid
{
    CFMutableArrayRef arrayPtr = CFArrayCreateMutable(NULL, 4, NULL);
    bool valid = ksobjc_isValidObject(arrayPtr);
    STAssertTrue(valid, @"");
    CFRelease(arrayPtr);
}

- (void) testCFMutableArrayIsValid
{
    CFMutableArrayRef arrayPtr = CFArrayCreateMutable(NULL, 4, NULL);
    id value = @"blah";
    CFArrayAppendValue(arrayPtr, (as_bridge void*)value);
    bool valid = ksobjc_isValidObject(arrayPtr);
    STAssertTrue(valid, @"");
    CFRelease(arrayPtr);
}

- (void) testCopyArrayContentsEmpty
{
    NSArray* array = [NSArray array];
    void* arrayPtr = (as_bridge void*)array;
    size_t expectedCount = [array count];
    size_t count = ksobjc_arrayCount(arrayPtr);
    STAssertEquals(count, expectedCount, @"");
}

- (void) testArrayCountEmpty
{
    NSArray* array = [NSArray array];
    void* arrayPtr = (as_bridge void*)array;
    size_t count = ksobjc_arrayCount(arrayPtr);
    STAssertEquals(count, 0ul, @"");
}

- (void) testArrayDescriptionEmpty
{
    NSArray* array = [NSArray array];
    void* arrayPtr = (as_bridge void*)array;
    NSString* expectedClassName = [NSString stringWithCString:class_getName([array class]) encoding:NSUTF8StringEncoding];
    NSString* expectedTheRest = @"[]";
    char buffer[100];
    size_t copied = ksobjc_getDescription(arrayPtr, buffer, sizeof(buffer));
    STAssertTrue(copied > 0, @"");
    NSString* description = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
    NSArray* components = [self componentsOfComplexDescription:description];
    NSString* className = [components objectAtIndex:0];
    NSString* theRest = [components objectAtIndex:1];
    STAssertEqualObjects(className, expectedClassName, @"");
    STAssertEqualObjects(theRest, expectedTheRest, @"");
}

- (void) testArrayDescription
{
    NSArray* array = [NSArray arrayWithObjects:@"test", nil];
    void* arrayPtr = (as_bridge void*)array;
    NSString* expectedClassName = [NSString stringWithCString:class_getName([array class]) encoding:NSUTF8StringEncoding];
    NSString* expectedTheRest = @"\"test\"";
    char buffer[100];
    size_t copied = ksobjc_getDescription(arrayPtr, buffer, sizeof(buffer));
    STAssertTrue(copied > 0, @"");
    NSString* description = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
    NSArray* components = [self componentsOfComplexDescription:description];
    NSString* className = [components objectAtIndex:0];
    NSString* theRest = [components objectAtIndex:1];
    STAssertEqualObjects(className, expectedClassName, @"");
    
    // Remove bounding [ and ]
    theRest = [theRest substringWithRange:NSMakeRange(1, [theRest length]-2)];

    components = [self componentsOfComplexDescription:theRest];
    className = [components objectAtIndex:0];
    theRest = [components objectAtIndex:1];
    expectedClassName = [NSString stringWithCString:class_getName([expectedTheRest class]) encoding:NSUTF8StringEncoding];
    STAssertEqualObjects(className, expectedClassName, @"");
    STAssertEqualObjects(theRest, expectedTheRest, @"");
}

- (void) testCopyArrayContentsImmutable
{
    NSArray* array = [NSArray arrayWithObjects:@"1", @"2", @"3", @"4", nil];
    void* arrayPtr = (as_bridge void*)array;
    size_t expectedCount = [array count];
    size_t count = ksobjc_arrayCount(arrayPtr);
    STAssertEquals(count, expectedCount, @"");
    uintptr_t contents[10];
    size_t copied = ksobjc_arrayContents(arrayPtr, contents, sizeof(contents));
    STAssertEquals(copied, count, @"");
    for(size_t i = 0; i < count; i++)
    {
        bool isValid = ksobjc_objectType((void*)contents[i]) == KSObjCTypeObject;
        STAssertTrue(isValid, @"Object %d is not an object", i);
        isValid = ksobjc_isValidObject((void*)contents[i]);
        STAssertTrue(isValid, @"Object %d is invalid", i);
    }
}

- (void) testCopyArrayContentsImmutableEmpty
{
    NSArray* array = [NSArray array];
    void* arrayPtr = (as_bridge void*)array;
    size_t expectedCount = [array count];
    size_t count = ksobjc_arrayCount(arrayPtr);
    STAssertEquals(count, expectedCount, @"");
    uintptr_t contents[10];
    size_t copied = ksobjc_arrayContents(arrayPtr, contents, sizeof(contents));
    STAssertEquals(copied, expectedCount, @"");
}

- (void) testCopyArrayContentsMutable
{
    NSMutableArray* array = [NSMutableArray arrayWithObjects:@"1", @"2", @"3", @"4", nil];
    void* arrayPtr = (as_bridge void*)array;
    size_t expectedCount = [array count];
    size_t count = ksobjc_arrayCount(arrayPtr);
    STAssertEquals(count, expectedCount, @"");
    uintptr_t contents[10];
    size_t copied = ksobjc_arrayContents(arrayPtr, contents, sizeof(contents));
    STAssertEquals(copied, count, @"");
    for(size_t i = 0; i < count; i++)
    {
        bool isValid = ksobjc_objectType((void*)contents[i]) == KSObjCTypeObject;
        STAssertTrue(isValid, @"Object %d is not an object", i);
        isValid = ksobjc_isValidObject((void*)contents[i]);
        STAssertTrue(isValid, @"Object %d is invalid", i);
    }
}

- (void) testCopyArrayContentsMutableEmpty
{
    NSMutableArray* array = [NSMutableArray array];
    void* arrayPtr = (as_bridge void*)array;
    size_t expectedCount = [array count];
    size_t count = ksobjc_arrayCount(arrayPtr);
    STAssertEquals(count, expectedCount, @"");
    uintptr_t contents[10];
    size_t copied = ksobjc_arrayContents(arrayPtr, contents, sizeof(contents));
    STAssertEquals(copied, expectedCount, @"");
}

- (void) testCopyArrayContentsCFArray
{
    const void* values[4] =
    {
        @"1",
        @"2",
        @"3",
        @"4",
    };
    CFArrayRef arrayPtr = CFArrayCreate(NULL, values, 4, NULL);
    NSArray* array = (as_bridge NSArray*)arrayPtr;
    size_t expectedCount = [array count];
    size_t count = ksobjc_arrayCount(arrayPtr);
    STAssertEquals(count, expectedCount, @"");
    uintptr_t contents[10];
    size_t copied = ksobjc_arrayContents(arrayPtr, contents, sizeof(contents));
    STAssertEquals(copied, count, @"");
    for(size_t i = 0; i < count; i++)
    {
        bool isValid = ksobjc_objectType((void*)contents[i]) == KSObjCTypeObject;
        STAssertTrue(isValid, @"Object %d is not an object", i);
        isValid = ksobjc_isValidObject((void*)contents[i]);
        STAssertTrue(isValid, @"Object %d is invalid", i);
    }
    CFRelease(arrayPtr);
}

- (void) testCopyArrayContentsCFArrayEmpty
{
    CFArrayRef arrayPtr = CFArrayCreate(NULL, NULL, 0, NULL);
    NSArray* array = (as_bridge NSArray*)arrayPtr;
    size_t expectedCount = [array count];
    size_t count = ksobjc_arrayCount(arrayPtr);
    STAssertEquals(count, expectedCount, @"");
    uintptr_t contents[10];
    size_t copied = ksobjc_arrayContents(arrayPtr, contents, sizeof(contents));
    STAssertEquals(copied, expectedCount, @"");
    CFRelease(arrayPtr);
}

- (void) testUntrackedClassIsValid
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    bool isValid = ksobjc_objectType(classPtr) == KSObjCTypeClass;
    STAssertTrue(isValid, @"Not a class");
}

- (void) testUntrackedClassDescription
{
    SomeObjCClass* instance = as_autorelease([[SomeObjCClass alloc] init]);
    void* instancePtr = (as_bridge void*)instance;
    NSString* expectedClassName = [NSString stringWithCString:class_getName([instance class]) encoding:NSUTF8StringEncoding];
    char buffer[100];
    size_t copied = ksobjc_getDescription(instancePtr, buffer, sizeof(buffer));
    STAssertTrue(copied > 0, @"");
    NSString* description = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
    NSArray* components = [self componentsOfBasicDescription:description];
    NSString* className = [components objectAtIndex:0];
    STAssertEqualObjects(className, expectedClassName, @"");
}

- (void) testSuperclass
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    const void* expected = (as_bridge void*)[NSObject class];
    const void* superclass = ksobjc_superClass(classPtr);
    STAssertEquals(superclass, expected, @"");
}

- (void) testNSObjectIsRootClass
{
    void* classPtr = (as_bridge void*)[NSObject class];
    bool isRootClass = ksobjc_isRootClass(classPtr);
    STAssertTrue(isRootClass, @"");
}

- (void) testNotRootClass
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    bool isRootClass = ksobjc_isRootClass(classPtr);
    STAssertFalse(isRootClass, @"");
}

- (void) testIsClassNamed
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    bool isClassNamed = ksobjc_isClassNamed(classPtr, "SomeObjCClass");
    STAssertTrue(isClassNamed, @"");
    isClassNamed = ksobjc_isClassNamed(classPtr, "NSObject");
    STAssertFalse(isClassNamed, @"");
    isClassNamed = ksobjc_isClassNamed(classPtr, NULL);
    STAssertFalse(isClassNamed, @"");
}

- (void) testIsKindOfClass
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    bool isKindOfClass = ksobjc_isKindOfClass(classPtr, "NSObject");
    STAssertTrue(isKindOfClass, @"");
    isKindOfClass = ksobjc_isKindOfClass(classPtr, "NSDate");
    STAssertFalse(isKindOfClass, @"");
    isKindOfClass = ksobjc_isKindOfClass(classPtr, NULL);
    STAssertFalse(isKindOfClass, @"");
}

- (void) testBaseClass
{
    const void* classPtr = (as_bridge void*)[SomeSubclass class];
    const void* expected = (as_bridge void*)[SomeObjCClass class];
    const void* baseClass = ksobjc_baseClass(classPtr);
    STAssertEquals(baseClass, expected, @"");
}

- (void) testIvarCount
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    size_t ivarCount = ksobjc_ivarCount(classPtr);
    STAssertEquals(ivarCount, 2ul, @"");
}

- (void) testIvarList
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    KSObjCIvar ivars[10];
    size_t ivarCount = ksobjc_ivarList(classPtr, ivars, sizeof(ivars)/sizeof(*ivars));
    const char* expectedIvar1Name = "someIvar";
    const char* expectedIvar1Type = "i";
    const char* expectedIvar2Name = "anotherIvar";
    const char* expectedIvar2Type = "@";
    
    int compare;
    
    STAssertEquals(ivarCount, 2ul, @"");
    compare = strcmp(ivars[0].name, expectedIvar1Name);
    STAssertEquals(compare, 0, @"");
    compare = strcmp(ivars[0].type, expectedIvar1Type);
    STAssertEquals(compare, 0, @"");
    compare = strcmp(ivars[1].name, expectedIvar2Name);
    STAssertEquals(compare, 0, @"");
    compare = strcmp(ivars[1].type, expectedIvar2Type);
    STAssertEquals(compare, 0, @"");
}

- (void) testIvarListTruncated
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    KSObjCIvar ivars[1];
    size_t ivarCount = ksobjc_ivarList(classPtr, ivars, sizeof(ivars)/sizeof(*ivars));
    const char* expectedIvar1Name = "someIvar";
    const char* expectedIvar1Type = "i";
    
    int compare;
    
    STAssertEquals(ivarCount, 1ul, @"");
    compare = strcmp(ivars[0].name, expectedIvar1Name);
    STAssertEquals(compare, 0, @"");
    compare = strcmp(ivars[0].type, expectedIvar1Type);
    STAssertEquals(compare, 0, @"");
}

- (void) testIvarListNull
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    size_t ivarCount = ksobjc_ivarList(classPtr, NULL, 10);
    STAssertEquals(ivarCount, 0ul, @"");
}

- (void) testIvarNamed
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    KSObjCIvar ivar;
    bool found = ksobjc_ivarNamed(classPtr, "someIvar", &ivar);
    STAssertTrue(found, @"");
    const char* expectedIvarName = "someIvar";
    const char* expectedIvarType = "i";
    int compare = strcmp(ivar.name, expectedIvarName);
    STAssertEquals(compare, 0, @"");
    compare = strcmp(ivar.type, expectedIvarType);
    STAssertEquals(compare, 0, @"");
}

- (void) testIvarNamedNotFound
{
    void* classPtr = (as_bridge void*)[SomeObjCClass class];
    KSObjCIvar ivar;
    bool found = ksobjc_ivarNamed(classPtr, "blahblahh", &ivar);
    STAssertFalse(found, @"");

    found = ksobjc_ivarNamed(classPtr, NULL, &ivar);
    STAssertFalse(found, @"");
}

- (void) testIvarValue
{
    int expectedValue = 100;
    SomeObjCClass* object = as_autorelease([[SomeObjCClass alloc] init]);
    object.someIvar = expectedValue;
    void* objectPtr = (as_bridge void*)object;
    int value = 0;
    bool success = ksobjc_ivarValue(objectPtr, 0, &value);
    STAssertTrue(success, @"");
    STAssertEquals(value, expectedValue, @"");
}

- (void) testIvarValueOutOfRange
{
    SomeObjCClass* object = as_autorelease([[SomeObjCClass alloc] init]);
    void* objectPtr = (as_bridge void*)object;
    int value = 0;
    bool success = ksobjc_ivarValue(objectPtr, 100, &value);
    STAssertFalse(success, @"");
}

- (void) testUnknownObjectIsValid
{
    SomeObjCClass* object = as_autorelease([[SomeObjCClass alloc] init]);
    void* objectPtr = (as_bridge void*)object;
    bool success = ksobjc_isValidObject(objectPtr);
    STAssertTrue(success, @"");
}

//- (void) testCopyDictionaryContents
//{
//    NSDictionary* dict = [NSDictionary dictionaryWithObject:@"value" forKey:@"key"];
//    void* dictPtr = (as_bridge void*)dict;
//    size_t expectedCount = [dict count];
//    size_t count = ksobjc_dictionaryCount(dictPtr);
//    STAssertEquals(count, expectedCount, @"");
//    uintptr_t key;
//    uintptr_t value;
//    bool copied = ksobjc_dictionaryFirstEntry(dictPtr, &key, &value);
//    STAssertTrue(copied, @"");
//    bool isValid = ksobjc_objectType((void*)key) == KSObjCTypeObject;
//    STAssertTrue(isValid, @"");
//    isValid = ksobjc_isValidObject((void*)key);
//    STAssertTrue(isValid, @"");
//    isValid = ksobjc_objectType((void*)value) == KSObjCTypeObject;
//    STAssertTrue(isValid, @"");
//    isValid = ksobjc_isValidObject((void*)value);
//    STAssertTrue(isValid, @"");
//}

@end
