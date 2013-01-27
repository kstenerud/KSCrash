//
//  KSSafeCollections_Tests.m
//  KSCrash
//
//  Created by Karl Stenerud on 1/26/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "KSSafeCollections.h"

@interface KSSafeCollections_Tests : SenTestCase @end

@implementation KSSafeCollections_Tests

- (void) testAddObjectIfNotNil
{
    NSMutableArray* array = [NSMutableArray array];
    id object = @"blah";
    [array addObjectIfNotNil:object];
    STAssertTrue([array count] == 1, @"");
}

- (void) testAddObjectIfNotNil2
{
    NSMutableArray* array = [NSMutableArray array];
    id object = nil;
    [array addObjectIfNotNil:object];
    STAssertTrue([array count] == 0, @"");
}

- (void) testSafeAddObject
{
    NSMutableArray* array = [NSMutableArray array];
    id object = @"blah";
    [array safeAddObject:object];
    STAssertTrue([array count] == 1, @"");
}

- (void) testSafeAddObject2
{
    NSMutableArray* array = [NSMutableArray array];
    id object = nil;
    [array safeAddObject:object];
    STAssertTrue([array count] == 1, @"");
}

- (void) testInsertObjectIfNotNil
{
    NSMutableArray* array = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
    id object = @"blah";
    [array insertObjectIfNotNil:object atIndex:1];
    STAssertTrue([array count] == 3, @"");
}

- (void) testInsertObjectIfNotNil2
{
    NSMutableArray* array = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
    id object = nil;
    [array insertObjectIfNotNil:object atIndex:1];
    STAssertTrue([array count] == 2, @"");
}

- (void) testSafeInsertObject
{
    NSMutableArray* array = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
    id object = @"blah";
    [array safeInsertObject:object atIndex:1];
    STAssertTrue([array count] == 3, @"");
}

- (void) testSafeInsertObject2
{
    NSMutableArray* array = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
    id object = nil;
    [array safeInsertObject:object atIndex:1];
    STAssertTrue([array count] == 3, @"");
}

- (void) testSetObjectIfNotNil
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = @"blah";
    [dict setObjectIfNotNil:object forKey:key];
    id result = [dict objectForKey:key];
    STAssertEquals(result, object, @"");
}

- (void) testSetObjectIfNotNil2
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = nil;
    [dict setObjectIfNotNil:object forKey:key];
    id result = [dict objectForKey:key];
    STAssertNil(result, @"");
}

- (void) testSafeSetObject
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = @"blah";
    [dict safeSetObject:object forKey:key];
    id result = [dict objectForKey:key];
    STAssertEquals(result, object, @"");
}

- (void) testSafeSetObject2
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = nil;
    [dict safeSetObject:object forKey:key];
    id result = [dict objectForKey:key];
    STAssertNotNil(result, @"");
}

- (void) testSetValueIfNotNil
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = @"blah";
    [dict setValueIfNotNil:object forKey:key];
    id result = [dict valueForKey:key];
    STAssertEquals(result, object, @"");
}

- (void) testSetValueIfNotNil2
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = nil;
    [dict setValueIfNotNil:object forKey:key];
    id result = [dict valueForKey:key];
    STAssertNil(result, @"");
}

- (void) testSafeSetValue
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = @"blah";
    [dict safeSetValue:object forKey:key];
    id result = [dict valueForKey:key];
    STAssertEquals(result, object, @"");
}

- (void) testSafeSetValue2
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = nil;
    [dict safeSetValue:object forKey:key];
    id result = [dict valueForKey:key];
    STAssertNotNil(result, @"");
}

@end
