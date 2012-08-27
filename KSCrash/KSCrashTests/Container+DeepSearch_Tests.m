//
//  Container+DeepSearch_Tests.m
//  KSCrash
//
//  Created by Karl Stenerud on 8/26/12.
//
//

#import <SenTestingKit/SenTestingKit.h>
#import "Container+DeepSearch.h"

@interface Container_DeepSearch_Tests : SenTestCase @end

@implementation Container_DeepSearch_Tests

- (void) testDeepSearchDictionary
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"key3",
                      nil], @"key2",
                     nil], @"key1",
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:@"key1", @"key2", @"key3", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchDictionaryPath
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"key3",
                      nil], @"key2",
                     nil], @"key1",
                    nil];

    id actual = [container objectForKeyPath:@"key1/key2/key3"];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchDictionary2
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"3",
                      nil], @"2",
                     nil], @"1",
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:@"1", @"2", @"3", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchDictionary2Path
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"3",
                      nil], @"2",
                     nil], @"1",
                    nil];

    id actual = [container objectForKeyPath:@"1/2/3"];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchArray
{
    id expected = @"Object";
    id container = [NSArray arrayWithObjects:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSArray arrayWithObjects:
                      @"blah2",
                      expected,
                      nil],
                     nil],
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:
                        [NSNumber numberWithInt:0],
                        [NSNumber numberWithInt:1],
                        [NSNumber numberWithInt:1],
                        nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchArrayString
{
    id expected = @"Object";
    id container = [NSArray arrayWithObjects:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSArray arrayWithObjects:
                      @"blah2",
                      expected,
                      nil],
                     nil],
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:@"0", @"1", @"1", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchArrayString2
{
    id expected = @"Object";
    id container = [NSArray arrayWithObjects:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSArray arrayWithObjects:
                      @"blah2",
                      expected,
                      nil],
                     nil],
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:@"0", @"1", @"key", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertNil(actual, @"");
}

- (void) testDeepSearchArrayPath
{
    id expected = @"Object";
    id container = [NSArray arrayWithObjects:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSArray arrayWithObjects:
                      @"blah2",
                      expected,
                      nil],
                     nil],
                    nil];

    id actual = [container objectForKeyPath:@"0/1/1"];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchMixed
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"key3",
                      nil],
                     nil], @"key1",
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:
                        @"key1",
                        [NSNumber numberWithInt:1],
                        @"key3", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchMixedPath
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"key3",
                      nil],
                     nil], @"key1",
                    nil];

    id actual = [container objectForKeyPath:@"key1/1/key3"];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchNotFound
{
    id container = [NSDictionary dictionary];
    NSArray* deepKey = [NSArray arrayWithObjects:@"key1", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertNil(actual, @"");
}

- (void) testDeepSearchNotFoundArray
{
    id container = [NSArray array];
    NSArray* deepKey = [NSArray arrayWithObjects:@"key1", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertNil(actual, @"");
}

- (void) testDeepSearchNonContainerObject
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"key3",
                      nil],
                     nil], @"key1",
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:
                        @"key1",
                        [NSNumber numberWithInt:1],
                        @"key3",
                        @"key4", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertNil(actual, @"");
}


@end
