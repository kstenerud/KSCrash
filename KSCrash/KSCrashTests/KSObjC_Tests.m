//
//  KSObjC_Tests.m
//  KSCrash
//
//  Created by Karl Stenerud on 8/30/12.
//
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
