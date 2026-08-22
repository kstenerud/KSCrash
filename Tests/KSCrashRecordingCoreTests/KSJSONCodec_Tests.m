//
//  KSJSONCodec_Tests.m
//
//  Created by Karl Stenerud on 2012-01-08.
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

#import <XCTest/XCTest.h>

#import "FileBasedTestCase.h"
#import "KSJSONCodec.h"
#import "KSJSONCodecObjC.h"

#define AssertAround(FLOAT_VALUE, COMPARED_TO)                          \
    XCTAssertGreaterThanOrEqual(FLOAT_VALUE, (COMPARED_TO) - 0.000001); \
    XCTAssertLessThanOrEqual(FLOAT_VALUE, (COMPARED_TO) + 0.000001)

@interface KSJSONCodec_Tests : FileBasedTestCase
@end

@implementation KSJSONCodec_Tests

static NSData *toData(NSString *string)
{
    if (string == nil) {
        return nil;
    }
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

static NSString *toString(NSData *data)
{
    if (data == nil) {
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)testSerializeDeserializeArrayEmpty
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[]";
    id original = [NSArray array];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayNull
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[null]";
    id original = [NSArray arrayWithObjects:[NSNull null], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayBoolTrue
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[true]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithBool:YES], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayBoolFalse
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[false]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithBool:NO], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayInteger
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[1]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithInt:1], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayFloat
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[-0.2]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithFloat:-0.2f], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    AssertAround([[result objectAtIndex:0] floatValue], -0.2f);
    // This always fails on NSNumber filled with float.
    // XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayFloat2
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[-2e-15]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithFloat:-2e-15f], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    AssertAround([[result objectAtIndex:0] floatValue], -2e-15f);
    // This always fails on NSNumber filled with float.
    // XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayString
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[\"One\"]";
    id original = [NSArray arrayWithObjects:@"One", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayStringIntl
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[\"テスト\"]";
    id original = [NSArray arrayWithObjects:@"テスト", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayMultipleEntries
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[\"One\",1000,true]";
    id original = [NSArray arrayWithObjects:@"One", [NSNumber numberWithInt:1000], [NSNumber numberWithBool:YES], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayWithArray
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[[]]";
    id original = [NSArray arrayWithObjects:[NSArray array], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayWithArray2
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[[\"Blah\"]]";
    id original = [NSArray arrayWithObjects:[NSArray arrayWithObjects:@"Blah", nil], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayWithDictionary
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[{}]";
    id original = [NSArray arrayWithObjects:[NSDictionary dictionary], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayWithDictionary2
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[{\"Blah\":true}]";
    id original = [NSArray
        arrayWithObjects:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"Blah", nil], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryEmpty
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{}";
    id original = [NSDictionary dictionary];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryNull
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"One\":null}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:[NSNull null], @"One", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryBoolTrue
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"One\":true}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"One", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryBoolFalse
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"One\":false}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], @"One", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryInteger
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"One\":1}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1], @"One", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryFloat
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"One\":54.918}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:54.918f], @"One", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    AssertAround([[(NSDictionary *)result objectForKey:@"One"] floatValue], 54.918f);
    // This always fails on NSNumber filled with float.
    // XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryFloat2
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"One\":5e+20}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:5e20f], @"One", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    AssertAround([[(NSDictionary *)result objectForKey:@"One"] floatValue], 5e20f);
    // This always fails on NSNumber filled with float.
    // XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryString
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"One\":\"Value\"}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:@"Value", @"One", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryMultipleEntries
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"One\":\"Value\",\"Three\":true,\"Two\":1000}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:@"Value", @"One", [NSNumber numberWithInt:1000], @"Two",
                                                             [NSNumber numberWithBool:YES], @"Three", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryWithDictionary
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"One\":{}}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:[NSDictionary dictionary], @"One", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryWithDictionary2
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"One\":{\"Blah\":1}}";
    id original = [NSDictionary
        dictionaryWithObjectsAndKeys:[NSDictionary
                                         dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1], @"Blah", nil],
                                     @"One", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryWithArray
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"Key\":[]}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray array], @"Key", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryWithArray2
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"Blah\":[true]}";
    id original = [NSDictionary
        dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:[NSNumber numberWithBool:YES]], @"Blah", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeBigDictionary
{
    NSError *error = (NSError *)self;
    id original = [NSDictionary
        dictionaryWithObjectsAndKeys:@"0", @"0", @"1", @"1", @"2", @"2", @"3", @"3", @"4", @"4", @"5", @"5", @"6", @"6",
                                     @"7", @"7", @"8", @"8", @"9", @"9", @"10", @"10", @"11", @"11", @"12", @"12",
                                     @"13", @"13", @"14", @"14", @"15", @"15", @"16", @"16", @"17", @"17", @"18", @"18",
                                     @"19", @"19", @"20", @"20", @"21", @"21", @"22", @"22", @"23", @"23", @"24", @"24",
                                     @"25", @"25", @"26", @"26", @"27", @"27", @"28", @"28", @"29", @"29", @"30", @"30",
                                     @"31", @"31", @"32", @"32", @"33", @"33", @"34", @"34", @"35", @"35", @"36", @"36",
                                     @"37", @"37", @"38", @"38", @"39", @"39", @"40", @"40", @"41", @"41", @"42", @"42",
                                     @"43", @"43", @"44", @"44", @"45", @"45", @"46", @"46", @"47", @"47", @"48", @"48",
                                     @"49", @"49", @"50", @"50", @"51", @"51", @"52", @"52", @"53", @"53", @"54", @"54",
                                     @"55", @"55", @"56", @"56", @"57", @"57", @"58", @"58", @"59", @"59", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDeep
{
    NSError *error = (NSError *)self;
    NSString *expected = @"{\"a0\":\"A0\",\"a1\":{\"b0\":{\"c0\":\"C0\",\"c1\":{\"d0\":[[],[],[]],\"d1\":\"D1\"}},"
                         @"\"b1\":\"B1\"},\"a2\":\"A2\"}";
    id original = [NSDictionary
        dictionaryWithObjectsAndKeys:
            @"A0", @"a0",
            [NSDictionary
                dictionaryWithObjectsAndKeys:
                    [NSDictionary
                        dictionaryWithObjectsAndKeys:
                            @"C0", @"c0",
                            [NSDictionary
                                dictionaryWithObjectsAndKeys:[NSArray arrayWithObjects:[NSArray array], [NSArray array],
                                                                                       [NSArray array], nil],
                                                             @"d0", @"D1", @"d1", nil],
                            @"c1", nil],
                    @"b0", @"B1", @"b1", nil],
            @"a1", @"A2", @"a2", nil];

    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testDeserializeUnicode
{
    NSError *error = (NSError *)self;
    NSString *json = @"[\"\\u00dcOne\"]";
    NSString *expected = @"\u00dcOne";
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    NSString *value = [result objectAtIndex:0];
    XCTAssertEqualObjects(value, expected, @"");
}

- (void)testDeserializeUnicode2
{
    NSError *error = (NSError *)self;
    NSString *json = @"[\"\\u827e\\u5c0f\\u8587\"]";
    NSString *expected = @"\u827e\u5c0f\u8587";
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    NSString *value = [result objectAtIndex:0];
    XCTAssertEqualObjects(value, expected, @"");
}

- (void)testDeserializeUnicodeExtended
{
    // A surrogate pair encodes the code point less 0x10000, so 𐌣 = U+10323 is
    // 0x10323 - 0x10000 = 0x323, split as 0xd800,0xdf23. Dropping that bias on either side
    // is what made this test and the decoder agree on the wrong character for years.
    NSError *error = (NSError *)self;
    NSString *json = @"[\"ABC\\ud800\\udf23DEFGHIJ\"]";
    NSString *expected = @"ABC𐌣DEFGHIJ";
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    NSString *value = [result objectAtIndex:0];
    XCTAssertEqualObjects(value, expected, @"");

    // And the pair this used to carry really is a different character.
    error = nil;
    result = [KSJSONCodec decode:toData(@"[\"ABC\\ud840\\udf23DEFGHIJ\"]") options:0 error:&error];
    XCTAssertEqualObjects([result objectAtIndex:0], @"ABC𠌣DEFGHIJ");
}

- (void)testDeserializeUnicodeExtendedLoneTrailSurrogate
{
    NSError *error = (NSError *)self;
    NSString *json = @"[\"ABC\\ud840DEFGHIJ\"]";
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeUnicodeExtendedMissingTrailSurrogate
{
    NSError *error = (NSError *)self;
    NSString *json = @"[\"ABC\\udf23DEFGHIJ\"]";
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeUnicodeExtendedMissingTrailSurrogate2
{
    NSError *error = (NSError *)self;
    NSString *json = @"[\"ABC\\udf23\\u1234DEFGHIJ\"]";
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeUnicodeExtendedCutOff
{
    NSError *error = (NSError *)self;
    NSString *json = @"[\"ABC\\udf23\"]";
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeControlChars
{
    NSError *error = (NSError *)self;
    NSString *json = @"[\"\\b\\f\\n\\r\\t\"]";
    NSString *expected = @"\b\f\n\r\t";
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    NSString *value = [result objectAtIndex:0];
    XCTAssertEqualObjects(value, expected, @"");
}

- (void)testSerializeDeserializeControlChars2
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[\"\\b\\f\\n\\r\\t\"]";
    id original = [NSArray arrayWithObjects:@"\b\f\n\r\t", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeControlChars3
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[\"Testing\\b escape \\f chars\\n\"]";
    id original = [NSArray arrayWithObjects:@"Testing\b escape \f chars\n", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeEscapedChars
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[\"\\\"\\\\\"]";
    id original = [NSArray arrayWithObjects:@"\"\\", nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeFloat
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[1.2]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithFloat:1.2f], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    AssertAround([[result objectAtIndex:0] floatValue], [[original objectAtIndex:0] floatValue]);
}

- (void)testSerializeDeserializeDouble
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[0.1]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0.1], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    AssertAround([[result objectAtIndex:0] floatValue], [[original objectAtIndex:0] floatValue]);
}

- (void)testSerializeDeserializeChar
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[20]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithChar:20], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeShort
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[2000]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithShort:2000], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeLong
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[2000000000]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithLong:2000000000], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeLongLong
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[200000000000]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithLongLong:200000000000], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeNegative
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[-2000]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithInt:-2000], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserialize0
{
    NSError *error = (NSError *)self;
    NSString *expected = @"[0]";
    id original = [NSArray arrayWithObjects:[NSNumber numberWithInt:0], nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeEmptyString
{
    NSError *error = (NSError *)self;
    NSString *string = @"";
    NSString *expected = @"[\"\"]";
    id original = [NSArray arrayWithObjects:string, nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeBigString
{
    NSError *error = (NSError *)self;

    int length = 500;
    NSMutableString *string = [NSMutableString stringWithCapacity:(NSUInteger)length];
    for (int i = 0; i < length; i++) {
        [string appendFormat:@"%d", i % 10];
    }

    NSString *expected = [NSString stringWithFormat:@"[\"%@\"]", string];
    id original = [NSArray arrayWithObjects:string, nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeHugeString
{
    NSError *error = (NSError *)self;
    char buff[5000];
    memset(buff, '2', sizeof(buff));
    buff[sizeof(buff) - 1] = 0;
    NSString *string = [NSString stringWithCString:buff encoding:NSUTF8StringEncoding];

    id original = [NSArray arrayWithObjects:string, nil];
    NSString *jsonString = toString([KSJSONCodec encode:original options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString, @"");
    XCTAssertNil(error, @"");
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeLargeArray
{
    NSError *error = (NSError *)self;
    unsigned int numEntries = 2000;

    NSMutableString *jsonString = [NSMutableString string];
    [jsonString appendString:@"["];
    for (unsigned int i = 0; i < numEntries; i++) {
        [jsonString appendFormat:@"%u,", i % 10];
    }
    [jsonString deleteCharactersInRange:NSMakeRange([jsonString length] - 1, 1)];
    [jsonString appendString:@"]"];

    NSArray *deserialized = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    unsigned int deserializedCount = (unsigned int)[deserialized count];
    XCTAssertNotNil(deserialized, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqual(deserializedCount, numEntries, @"");
    NSString *serialized = toString([KSJSONCodec encode:deserialized options:0 error:&error]);
    XCTAssertNotNil(serialized, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(serialized, jsonString, @"");
    int value = [[deserialized objectAtIndex:1] intValue];
    XCTAssertEqual(value, 1, @"");
    value = [[deserialized objectAtIndex:9] intValue];
    XCTAssertEqual(value, 9, @"");
}

- (void)testSerializeDeserializeLargeDictionary
{
    NSError *error = (NSError *)self;
    unsigned int numEntries = 2000;

    NSMutableString *jsonString = [NSMutableString string];
    [jsonString appendString:@"{"];
    for (unsigned int i = 0; i < numEntries; i++) {
        [jsonString appendFormat:@"\"%u\":%u,", i, i];
    }
    [jsonString deleteCharactersInRange:NSMakeRange([jsonString length] - 1, 1)];
    [jsonString appendString:@"}"];

    NSDictionary *deserialized = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    unsigned int deserializedCount = (unsigned int)[deserialized count];
    XCTAssertNotNil(deserialized, @"");
    XCTAssertNil(error, @"");
    XCTAssertEqual(deserializedCount, numEntries, @"");
    int value = [[(NSDictionary *)deserialized objectForKey:@"1"] intValue];
    XCTAssertEqual(value, 1, @"");
    NSString *serialized = toString([KSJSONCodec encode:deserialized options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(serialized, @"");
    XCTAssertNil(error, @"");
    XCTAssertTrue([serialized length] == [jsonString length], @"");
}

- (void)testDeserializeArrayMissingTerminator
{
    NSError *error = (NSError *)self;
    NSString *json = @"[\"blah\"";
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

//- (void) testSerializeBadTopLevelType
//{
//    NSError* error = (NSError*)self;
//    id source = @"Blah";
//    NSString* result = toString([KSJSONCodec encode:source error:&error]);
//    XCTAssertNil(result, @"");
//    XCTAssertNotNil(error, @"");
//}

- (void)testSerializeArrayBadType
{
    NSError *error = (NSError *)self;
    id source = [NSArray arrayWithObject:[NSValue valueWithPointer:NULL]];
    NSString *result = toString([KSJSONCodec encode:source options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testSerializeDictionaryBadType
{
    NSError *error = (NSError *)self;
    id source = [NSDictionary dictionaryWithObject:[NSValue valueWithPointer:NULL] forKey:@"blah"];
    NSString *result = toString([KSJSONCodec encode:source options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testSerializeDictionaryBadCharacter
{
    NSError *error = (NSError *)self;
    id source = [NSDictionary dictionaryWithObject:@"blah" forKey:@"blah\x01blah"];
    NSString *result = toString([KSJSONCodec encode:source options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testSerializeArrayBadCharacter
{
    NSError *error = (NSError *)self;
    id source = [NSArray arrayWithObject:@"test\x01ing"];
    NSString *result = toString([KSJSONCodec encode:source options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidUnicodeSequence
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[\"One\\ubarfTwo\"]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidUnicodeSequence2
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[\"One\\u123gTwo\"]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayUnterminatedEscape
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[\"One\\u123\"]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayUnterminatedEscape2
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[\"One\\\"]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayUnterminatedEscape3
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[\"One\\u\"]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidEscape
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[\"One\\qTwo\"]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayUnterminatedString
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[\"One]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayTruncatedFalse
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[f]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidFalse
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[falst]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayTruncatedTrue
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[t]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidTrue
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[ture]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayTruncatedNull
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[n]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidNull
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[nlll]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidElement
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[-blah]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayUnterminated
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[\"blah\"";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayNumberOverflow
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"[123456789012345678901234567890]";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
}

- (void)testDeserializeDictionaryInvalidKey
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"{blah:\"blah\"}";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeDictionaryInvalidUTF8Key
{
    const unsigned char json[] = { '{', '"', 0xff, '"', ':', '1', '}' };
    NSData *jsonData = [NSData dataWithBytes:json length:sizeof(json)];
    NSError *error = nil;
    id result = nil;

    XCTAssertNoThrow(result = [KSJSONCodec decode:jsonData options:KSJSONDecodeOptionKeepPartialObject error:&error]);
    XCTAssertEqualObjects(result, @{});
    XCTAssertNotNil(error);
}

- (void)testDeserializeDictionaryInvalidUTF8KeyWithIgnoredNull
{
    const unsigned char json[] = { '{', '"', 0xff, '"', ':', 'n', 'u', 'l', 'l', '}' };
    NSData *jsonData = [NSData dataWithBytes:json length:sizeof(json)];
    NSError *error = nil;
    id result = nil;

    KSJSONDecodeOption options = KSJSONDecodeOptionKeepPartialObject | KSJSONDecodeOptionIgnoreNullInObject;
    XCTAssertNoThrow(result = [KSJSONCodec decode:jsonData options:options error:&error]);
    XCTAssertEqualObjects(result, @{});
    XCTAssertNotNil(error);
}

- (void)testDeserializeDictionaryInvalidUTF8Value
{
    const unsigned char json[] = { '{', '"', 'k', '"', ':', '"', 0xff, '"', '}' };
    NSData *jsonData = [NSData dataWithBytes:json length:sizeof(json)];
    NSError *error = nil;
    id result = nil;

    XCTAssertNoThrow(result = [KSJSONCodec decode:jsonData options:KSJSONDecodeOptionKeepPartialObject error:&error]);
    XCTAssertEqualObjects(result, @{});
    XCTAssertNotNil(error);
}

- (void)testDeserializeArrayInvalidUTF8Value
{
    const unsigned char json[] = { '[', '"', 0xff, '"', ']' };
    NSData *jsonData = [NSData dataWithBytes:json length:sizeof(json)];
    NSError *error = nil;
    id result = nil;

    XCTAssertNoThrow(result = [KSJSONCodec decode:jsonData options:KSJSONDecodeOptionKeepPartialObject error:&error]);
    XCTAssertEqualObjects(result, @[]);
    XCTAssertNotNil(error);
}

- (void)testDeserializeDictionaryMissingSeparator
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"{\"blah\"\"blah\"}";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeDictionaryBadElement
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"{\"blah\":blah\"}";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeDictionaryUnterminated
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"{\"blah\":\"blah\"";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeInvalidData
{
    NSError *error = (NSError *)self;
    NSString *jsonString = @"X{\"blah\":\"blah\"}";
    id result = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
}

- (void)testDeserializeArrayWithNull
{
    NSError *error = (NSError *)self;
    NSString *json = @"[null]";
    id expected = [NSNull null];
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    NSString *value = [result objectAtIndex:0];
    XCTAssertEqualObjects(value, expected, @"");
}

- (void)testDeserializeArrayWithNullIgnoreNullInArray
{
    NSError *error = (NSError *)self;
    NSString *json = @"[null]";
    NSArray *result = [KSJSONCodec decode:toData(json) options:KSJSONDecodeOptionIgnoreNullInArray error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertTrue([result count] == 0, @"");
}

- (void)testDeserializeArrayWithNullIgnoreNullInObject
{
    NSError *error = (NSError *)self;
    NSString *json = @"[null]";
    id expected = [NSNull null];
    NSArray *result = [KSJSONCodec decode:toData(json) options:KSJSONDecodeOptionIgnoreNullInObject error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    NSString *value = [result objectAtIndex:0];
    XCTAssertEqualObjects(value, expected, @"");
}

- (void)testDeserializeArrayWithNullIgnoreAllNulls
{
    NSError *error = (NSError *)self;
    NSString *json = @"[null]";
    NSArray *result = [KSJSONCodec decode:toData(json) options:KSJSONDecodeOptionIgnoreAllNulls error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertTrue([result count] == 0, @"");
}

- (void)testDeserializeObjectWithNull
{
    NSError *error = (NSError *)self;
    NSString *json = @"{\"blah\":null}";
    id expected = [NSNull null];
    NSArray *result = [KSJSONCodec decode:toData(json) options:0 error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    NSString *value = [result valueForKey:@"blah"];
    XCTAssertEqualObjects(value, expected, @"");
}

- (void)testDeserializeObjectWithNullIgnoreNullInArray
{
    NSError *error = (NSError *)self;
    NSString *json = @"{\"blah\":null}";
    id expected = [NSNull null];
    NSArray *result = [KSJSONCodec decode:toData(json) options:KSJSONDecodeOptionIgnoreNullInArray error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    NSString *value = [result valueForKey:@"blah"];
    XCTAssertEqualObjects(value, expected, @"");
}

- (void)testDeserializeObjectWithNullIgnoreNullInObject
{
    NSError *error = (NSError *)self;
    NSString *json = @"{\"blah\":null}";
    NSArray *result = [KSJSONCodec decode:toData(json) options:KSJSONDecodeOptionIgnoreNullInObject error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertTrue([result count] == 0, @"");
}

- (void)testDeserializeObjectWithNullIgnoreAllNulls
{
    NSError *error = (NSError *)self;
    NSString *json = @"{\"blah\":null}";
    NSArray *result = [KSJSONCodec decode:toData(json) options:KSJSONDecodeOptionIgnoreAllNulls error:&error];
    XCTAssertNotNil(result, @"");
    XCTAssertNil(error, @"");
    XCTAssertTrue([result count] == 0, @"");
}

- (void)testFloatParsingDoesntOverflow
{
    NSError *error = (NSError *)self;

    char *buffer = malloc(0x1000000);
    for (int i = 0; i < 0x1000000; i++) {
        buffer[i] = ';';
    }

    memcpy(buffer, "{\"test\":1.1}", 12);

    NSData *data = [NSData dataWithBytesNoCopy:buffer length:0x1000000 freeWhenDone:YES];

    // The object is followed by 16MB of filler, so this is not a valid document. What is
    // being guarded is that parsing the float stops at the '}' instead of running away into
    // the filler, which the reported offset is what proves.
    NSDictionary *result = [KSJSONCodec decode:data options:0 error:&error];
    XCTAssertNil(result, @"");
    XCTAssertNotNil(error, @"");
    XCTAssertTrue([error.localizedDescription containsString:@"offset 12"], @"got: %@", error.localizedDescription);
}

static int addJSONData(const char *data, int length, void *userData)
{
    NSMutableData *nsdata = (__bridge NSMutableData *)userData;
    [nsdata appendBytes:data length:(unsigned)length];
    return KSJSON_OK;
}

- (void)serializeObject:(id)object toFile:(NSString *)filename
{
    NSError *error = nil;
    NSData *savedData = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    XCTAssertNotNil(savedData);
    XCTAssertNil(error);
    XCTAssertTrue([savedData writeToFile:filename atomically:YES]);
}

- (void)expectData:(NSData *)data encodesObject:(id)expectedObject
{
    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNotNil(object);
    XCTAssertNil(error);
    XCTAssertEqualObjects(object, expectedObject);
}

- (id)decodeJSON:(const char *)jsonBytes
{
    NSError *error = nil;
    NSData *jsonData = [NSData dataWithBytes:jsonBytes length:strlen(jsonBytes)];
    id object = [KSJSONCodec decode:jsonData options:KSJSONDecodeOptionKeepPartialObject error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(object);
    return object;
}

- (void)expectEquivalentJSON:(const char *)jsonCompareBytes toJSON:(const char *)jsonExpectedBytes
{
    id objectCompare = [self decodeJSON:jsonCompareBytes];
    id objectExpect = [self decodeJSON:jsonExpectedBytes];
    XCTAssertEqualObjects(objectCompare, objectExpect);
}

- (void)testAddJSONFromFile
{
    NSString *savedFilename = [self.tempPath stringByAppendingPathComponent:@"saved.json"];
    id savedObject = @{ @"loaded" : @"yes" };
    [self serializeObject:savedObject toFile:savedFilename];
    id expectedObject = @{ @"1" : @"one", @"from_file" : savedObject };

    NSMutableData *encodedData = [NSMutableData data];
    KSJSONEncodeContext context = { 0 };
    ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
    ksjson_beginObject(&context, NULL);
    ksjson_addStringElement(&context, "1", "one", KSJSON_SIZE_AUTOMATIC);
    ksjson_addJSONFromFile(&context, "from_file", savedFilename.UTF8String, true);
    ksjson_endContainer(&context);
    ksjson_endEncode(&context);

    [self expectData:encodedData encodesObject:expectedObject];
}

- (void)testAddJSONFromBigFile
{
    NSString *savedFilename = [self.tempPath stringByAppendingPathComponent:@"big.json"];
    id savedObject = @{
        @"an_array" : @[ @1, @2, @3, @4 ],
        @"lines" : @[
            @"I cannot describe to you my sensations on the near prospect of my undertaking.",
            @"It is impossible to communicate to you a conception of the trembling sensation, half pleasurable and half fearful, with which I am preparing to depart.",
            @"I am going to unexplored regions, to \"the land of mist and snow,\" but I shall kill no albatross; therefore do not be alarmed for my safety or if I should come back to you as worn and woeful as the \"Ancient Mariner.\"",
            @"You will smile at my allusion, but I will disclose a secret.",
            @"I have often attributed my attachment to, my passionate enthusiasm for, the dangerous mysteries of ocean to that production of the most imaginative of modern poets.",
            @"There is something at work in my soul which I do not understand.",
            @"I am practically industrious—painstaking, a workman to execute with perseverance and labour—but besides this there is a love for the marvellous, a belief in the marvellous, intertwined in all my projects, which hurries me out of the common pathways of men, even to the wild sea and unvisited regions I am about to explore.",
            @"But to return to dearer considerations.",
            @"Shall I meet you again, after having traversed immense seas, and returned by the most southern cape of Africa or America? I dare not expect such success, yet I cannot bear to look on the reverse of the picture.",
            @"Continue for the present to write to me by every opportunity: I may receive your letters on some occasions when I need them most to support my spirits.",
            @"I love you very tenderly.",
            @"Remember me with affection, should you never hear from me again.",
        ],
    };
    [self serializeObject:savedObject toFile:savedFilename];
    id expectedObject = @{ @"testing" : @"this", @"from_file" : savedObject };

    NSMutableData *encodedData = [NSMutableData data];
    KSJSONEncodeContext context = { 0 };
    ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
    ksjson_beginObject(&context, NULL);
    ksjson_addStringElement(&context, "testing", "this", KSJSON_SIZE_AUTOMATIC);
    ksjson_addJSONFromFile(&context, "from_file", savedFilename.UTF8String, true);
    ksjson_endContainer(&context);
    ksjson_endEncode(&context);

    [self expectData:encodedData encodesObject:expectedObject];
}

// A truncated file is rejected whole rather than embedded as far as it parsed, so the
// element it would have written is simply absent and the caller's name is still free.
- (void)testAddJSONFromBrokenFile
{
    NSString *savedFilename = [self.tempPath stringByAppendingPathComponent:@"broken.json"];
    char *savedJSON = "{"
                      "\"an_object\": {";
    char *expectedJSON = "{"
                         "\"1\": \"one\""
                         "}";

    NSData *data = [NSData dataWithBytes:savedJSON length:strlen(savedJSON)];
    XCTAssertTrue([data writeToFile:savedFilename atomically:YES]);

    NSError *error = nil;
    NSData *expectedObject = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:expectedJSON
                                                                                    length:strlen(expectedJSON)]
                                                             options:0
                                                               error:&error];
    XCTAssertNotNil(expectedObject);
    XCTAssertNil(error);

    NSMutableData *encodedData = [NSMutableData data];
    KSJSONEncodeContext context = { 0 };
    ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
    ksjson_beginObject(&context, NULL);
    ksjson_addStringElement(&context, "1", "one", KSJSON_SIZE_AUTOMATIC);
    XCTAssertNotEqual(ksjson_addJSONFromFile(&context, "from_file", savedFilename.UTF8String, true), KSJSON_OK);
    ksjson_endContainer(&context);
    ksjson_endEncode(&context);

    [self expectData:encodedData encodesObject:expectedObject];
}

- (void)testDontCloseLastContainer
{
    char *jsonData = "{\"a\":\"1\"}";
    char *expectedJson = "{\"a_container\": {\"a\":\"1\", \"testing\":\"this\"}}";

    NSMutableData *encodedData = [NSMutableData data];
    KSJSONEncodeContext context = { 0 };
    ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
    ksjson_beginObject(&context, NULL);
    ksjson_addJSONElement(&context, "a_container", jsonData, (int)strlen(jsonData), false);
    ksjson_addStringElement(&context, "testing", "this", KSJSON_SIZE_AUTOMATIC);
    ksjson_endContainer(&context);
    ksjson_endEncode(&context);
    [encodedData appendBytes:"\0" length:1];

    [self expectEquivalentJSON:encodedData.bytes toJSON:expectedJson];
}

/** Valid JSON whose string value is past KSJSON_MAX_EMBEDDED_STRING_LENGTH, so the decoder
 * refuses it even though the payload itself is well-formed.
 */
- (NSString *)jsonWithOversizedString
{
    NSMutableString *json = [NSMutableString stringWithString:@"{\"blob\":\""];
    for (int i = 0; i < KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1000; i++) {
        [json appendString:@"A"];
    }
    [json appendString:@"\"}"];
    return json;
}

/** Valid JSON nested past KSJSON_MAX_CONTAINER_DEPTH. */
- (NSString *)jsonNestedTooDeep
{
    NSMutableString *json = [NSMutableString string];
    int depth = KSJSON_MAX_CONTAINER_DEPTH + 50;
    for (int i = 0; i < depth; i++) {
        [json appendString:@"["];
    }
    [json appendString:@"1"];
    for (int i = 0; i < depth; i++) {
        [json appendString:@"]"];
    }
    return json;
}

- (void)testRejectedAddJSONElementWritesNothing
{
    // The encoder emits as it decodes, so a payload that only fails partway would leave a
    // truncated element the caller can neither see nor take back. Rejection has to happen
    // before the first byte, which is what lets the caller put its own element here instead.
    const char *json = [self jsonWithOversizedString].UTF8String;

    NSMutableData *encodedData = [NSMutableData data];
    KSJSONEncodeContext context = { 0 };
    ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
    ksjson_beginObject(&context, NULL);
    int result = ksjson_addJSONElement(&context, "bad", json, (int)strlen(json), false);
    XCTAssertEqual(result, KSJSON_ERROR_DATA_TOO_LONG);
    XCTAssertEqual(encodedData.length, 1u, @"a rejected payload must not write anything past the '{'");

    ksjson_addStringElement(&context, "after", "value", KSJSON_SIZE_AUTOMATIC);
    ksjson_endContainer(&context);
    ksjson_endEncode(&context);

    NSError *error = nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:encodedData options:0 error:&error];
    XCTAssertNotNil(decoded, @"output must stay well-formed after a rejected element: %@", error);
    XCTAssertNil(decoded[@"bad"], @"the rejected element must be absent, not partially present");
    XCTAssertEqualObjects(decoded[@"after"], @"value", @"the next element must land at the original level");
}

- (void)testRejectedAddJSONFromFileWritesNothing
{
    NSString *savedFilename = [self.tempPath stringByAppendingPathComponent:@"oversized.json"];
    NSData *savedData = [[self jsonWithOversizedString] dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([savedData writeToFile:savedFilename atomically:YES]);

    NSMutableData *encodedData = [NSMutableData data];
    KSJSONEncodeContext context = { 0 };
    ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
    ksjson_beginObject(&context, NULL);
    int result = ksjson_addJSONFromFile(&context, "bad", savedFilename.UTF8String, false);
    XCTAssertEqual(result, KSJSON_ERROR_DATA_TOO_LONG);
    XCTAssertEqual(encodedData.length, 1u, @"a rejected file must not write anything past the '{'");

    ksjson_addStringElement(&context, "after", "value", KSJSON_SIZE_AUTOMATIC);
    ksjson_endContainer(&context);
    ksjson_endEncode(&context);

    NSError *error = nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:encodedData options:0 error:&error];
    XCTAssertNotNil(decoded, @"output must stay well-formed after a rejected element: %@", error);
    XCTAssertNil(decoded[@"bad"]);
    XCTAssertEqualObjects(decoded[@"after"], @"value", @"the next element must land at the original level");
}

- (void)testRejectedAddJSONElementLeavesContainerLevelUntouched
{
    // closeLastContainer=false hands the caller an open container on success. On rejection
    // there is nothing to hand back, and the level must not drift either way or the caller's
    // matching endContainer would close something else.
    const char *json = [self jsonWithOversizedString].UTF8String;

    NSMutableData *encodedData = [NSMutableData data];
    KSJSONEncodeContext context = { 0 };
    ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
    ksjson_beginObject(&context, NULL);
    int levelBefore = context.containerLevel;

    XCTAssertNotEqual(ksjson_addJSONElement(&context, "bad", json, (int)strlen(json), false), KSJSON_OK);
    XCTAssertEqual(context.containerLevel, levelBefore);

    XCTAssertNotEqual(ksjson_addJSONElement(&context, "bad", json, (int)strlen(json), true), KSJSON_OK);
    XCTAssertEqual(context.containerLevel, levelBefore);
}

- (void)testCheckJSONElementAgreesWithAdd
{
    NSDictionary<NSString *, NSString *> *cases = @{
        @"valid object" : @"{\"a\":1}",
        @"valid array" : @"[1,2,3]",
        @"valid string" : @"\"hello\"",
        @"malformed" : @"{\"a\":",
        @"oversized string" : [self jsonWithOversizedString],
        @"too deep" : [self jsonNestedTooDeep],
    };

    for (NSString *label in cases) {
        const char *json = cases[label].UTF8String;
        int checkResult = [self checkElement:json atDepth:0];

        NSMutableData *encodedData = [NSMutableData data];
        KSJSONEncodeContext context = { 0 };
        ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
        ksjson_beginObject(&context, NULL);
        int addResult = ksjson_addJSONElement(&context, "x", json, (int)strlen(json), true);

        XCTAssertEqual(checkResult, addResult, @"check and add must agree for %@", label);
    }
}

- (void)testCheckJSONElementRejectsOversizedKey
{
    NSMutableString *json = [NSMutableString stringWithString:@"{\""];
    for (int i = 0; i < KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1000; i++) {
        [json appendString:@"k"];
    }
    [json appendString:@"\":1}"];

    const char *bytes = json.UTF8String;
    XCTAssertEqual([self checkElement:bytes atDepth:0], KSJSON_ERROR_DATA_TOO_LONG);
}

- (void)testCheckJSONElementAcceptsPayloadLargerThanTheStringLimit
{
    // The limit is on each key and value, not on the payload, so a long run of short
    // strings has to pass however big it gets.
    NSMutableString *json = [NSMutableString stringWithString:@"{"];
    for (int i = 0; i < 5000; i++) {
        [json appendFormat:@"%@\"k%d\":\"v\"", i == 0 ? @"" : @",", i];
    }
    [json appendString:@"}"];

    const char *bytes = json.UTF8String;
    XCTAssertGreaterThan(strlen(bytes), (size_t)KSJSON_MAX_EMBEDDED_STRING_LENGTH);
    XCTAssertEqual([self checkElement:bytes atDepth:0], KSJSON_OK);
}

/** Open `depth` nested containers. Arrays, because a nameless object cannot be nested
 * inside another object.
 */
- (void)nestEncoder:(KSJSONEncodeContext *)context toDepth:(int)depth
{
    for (int i = 0; i < depth; i++) {
        XCTAssertEqual(ksjson_beginArray(context, NULL), KSJSON_OK);
    }
    XCTAssertEqual(context->containerLevel, depth);
}

/** Check a payload against a destination already nested `depth` containers deep. */
- (int)checkElement:(const char *)json atDepth:(int)depth
{
    NSMutableData *scratch = [NSMutableData data];
    KSJSONEncodeContext destination = { 0 };
    ksjson_beginEncode(&destination, false, addJSONData, (__bridge void *)(scratch));
    [self nestEncoder:&destination toDepth:depth];
    return ksjson_checkJSONElement(&destination, json, (int)strlen(json));
}

- (int)checkFile:(NSString *)path atDepth:(int)depth
{
    NSMutableData *scratch = [NSMutableData data];
    KSJSONEncodeContext destination = { 0 };
    ksjson_beginEncode(&destination, false, addJSONData, (__bridge void *)(scratch));
    [self nestEncoder:&destination toDepth:depth];
    return ksjson_checkJSONFile(&destination, path.UTF8String);
}

/** A payload nested `depth` containers deep. */
- (NSString *)nestedPayloadOfDepth:(int)depth
{
    NSMutableString *json = [NSMutableString string];
    for (int i = 0; i < depth; i++) {
        [json appendString:@"["];
    }
    [json appendString:@"1"];
    for (int i = 0; i < depth; i++) {
        [json appendString:@"]"];
    }
    return json;
}

#pragma mark - Numbers

// A number is the only element with no closing delimiter, so the end of the data is where
// it ends. That is only true of the real end, though.
- (void)testNumberAtRealEndOfDataIsAccepted
{
    for (NSString *content in @[ @"1", @"0", @"42", @"-1.5", @"1e3", @"1E+3", @"-0.5e-3", @"9223372036854775807" ]) {
        XCTAssertEqual([self checkElement:content.UTF8String atDepth:0], KSJSON_OK, @"in memory: %@", content);

        NSString *path = [self.tempPath stringByAppendingPathComponent:@"number.json"];
        XCTAssertTrue([[content dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
        XCTAssertEqual([self checkFile:path atDepth:0], KSJSON_OK, @"from file: %@", content);
    }
}

/** Write `content` to a file and embed it, returning the decoded element. */
- (id)embedFileWithContent:(NSString *)content result:(int *)outResult
{
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"window.json"];
    XCTAssertTrue([[content dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);

    NSMutableData *encodedData = [NSMutableData data];
    KSJSONEncodeContext context = { 0 };
    ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
    ksjson_beginObject(&context, NULL);
    int addResult = ksjson_addJSONFromFile(&context, "n", path.UTF8String, true);
    ksjson_endContainer(&context);
    ksjson_endEncode(&context);

    if (outResult != NULL) {
        *outResult = addResult;
    }
    XCTAssertEqual([self checkFile:path atDepth:0], addResult, @"check and add must agree");
    if (addResult != KSJSON_OK) {
        return nil;
    }
    return [NSJSONSerialization JSONObjectWithData:encodedData options:0 error:nil][@"n"];
}

- (NSString *)spacesOfLength:(NSUInteger)length
{
    return [@"" stringByPaddingToLength:length withString:@" " startingAtIndex:0];
}

// Whether a number is whole cannot depend on where the read window happens to land, so the
// decoder pulls in more of the file rather than deciding at the boundary.
- (void)testNumberSplitAcrossTheFileWindow
{
    int result = KSJSON_OK;

    // The window ends in the middle of the digits.
    id value = [self
        embedFileWithContent:[[self spacesOfLength:KSJSON_EMBEDDED_FILE_WINDOW - 2] stringByAppendingString:@"1234"]
                      result:&result];
    XCTAssertEqual(result, KSJSON_OK);
    XCTAssertEqualObjects(value, @1234, @"digits past the window boundary must not be dropped");

    // The window ends right after a lone zero, with the fraction still to come.
    value = [self
        embedFileWithContent:[[self spacesOfLength:KSJSON_EMBEDDED_FILE_WINDOW - 1] stringByAppendingString:@"0.5"]
                      result:&result];
    XCTAssertEqual(result, KSJSON_OK);
    XCTAssertEqualObjects(value, @0.5, @"a zero at the boundary must not swallow its own fraction");

    // The file ends exactly on the window, so the read is full and proves nothing.
    value =
        [self embedFileWithContent:[[self spacesOfLength:KSJSON_EMBEDDED_FILE_WINDOW - 1] stringByAppendingString:@"1"]
                            result:&result];
    XCTAssertEqual(result, KSJSON_OK, @"a file ending exactly on the window is still a whole file");
    XCTAssertEqualObjects(value, @1);
}

// The end of the data completes a whole number. It does not complete a half-written one.
- (void)testIncompleteAndMalformedNumbersAreRejected
{
    for (NSString *content in @[ @"1e", @"1e+", @"1e-", @"1.", @"-", @"-e1", @"01" ]) {
        XCTAssertNotEqual([self checkElement:content.UTF8String atDepth:0], KSJSON_OK, @"%@", content);
    }
}

- (void)testNumbersInsideContainersAreUnaffected
{
    for (NSString *content in @[ @"{\"a\":1}", @"[1]", @"[1,2]", @"[1.5,-2e3]", @"{\"a\":0}" ]) {
        XCTAssertEqual([self checkElement:content.UTF8String atDepth:0], KSJSON_OK, @"%@", content);
    }
    for (NSString *content in @[ @"{\"a\":", @"[1,", @"{\"a\":1", @"[1e" ]) {
        XCTAssertNotEqual([self checkElement:content.UTF8String atDepth:0], KSJSON_OK, @"%@", content);
    }
}

// A number ends where the grammar says it ends, and what follows has to be something a
// value may be followed by. Otherwise only the prefix that happens to parse is taken.
- (void)testNumberFollowedByJunkIsRejected
{
    for (NSString *content in @[ @"1.2.3", @"1e2e3", @"1x", @"1.2x", @"12abc", @"[1x]", @"{\"a\":1x}" ]) {
        XCTAssertNotEqual([self checkElement:content.UTF8String atDepth:0], KSJSON_OK, @"%@", content);
    }
}

// A payload is one element, not "whatever parses first". Anything after it is an error, or
// a payload is only ever as valid as its opening.
- (void)testTrailingContentAfterTheTopLevelElementIsRejected
{
    for (NSString *content in @[ @"1 2", @"truejunk", @"{}[]", @"[1] [2]", @"\"a\" \"b\"", @"null null" ]) {
        XCTAssertNotEqual([self checkElement:content.UTF8String atDepth:0], KSJSON_OK, @"%@", content);
    }
}

// Whitespace around a payload is not trailing content.
- (void)testSurroundingWhitespaceIsAccepted
{
    for (NSString *content in @[ @"  {\"a\":1}  ", @"[1]\n", @"1\n", @"\t\"x\" " ]) {
        XCTAssertEqual([self checkElement:content.UTF8String atDepth:0], KSJSON_OK, @"%@", content);
    }
}

// The public decoder is subject to the same rules. Nothing here goes through the embedding
// path, so these pin the grammar and the end-of-data requirement on their own.
- (void)testPublicDecoderRejectsJunkAfterAValue
{
    for (NSString *content in @[ @"[1x]", @"[1.2.3]", @"[1e2e3]", @"{\"a\":1x}" ]) {
        NSError *error = nil;
        XCTAssertNil([KSJSONCodec decode:toData(content) options:0 error:&error], @"%@", content);
    }
}

- (void)testPublicDecoderRejectsTrailingContent
{
    for (NSString *content in @[ @"[1] [2]", @"{} junk", @"[1]x" ]) {
        NSError *error = nil;
        XCTAssertNil([KSJSONCodec decode:toData(content) options:0 error:&error], @"%@", content);
    }
    NSError *error = nil;
    XCTAssertNotNil([KSJSONCodec decode:toData(@"  [1]  \n") options:0 error:&error],
                    @"surrounding whitespace is not trailing content");
}

// Whitespace is the only thing that can fill a window without producing an element, so a
// file can look truncated before the decoder has asked for any of the rest of it.
- (void)testElementBeginningPastTheFirstWindow
{
    int result = KSJSON_OK;

    // Exactly a window of whitespace, then the element.
    id value =
        [self embedFileWithContent:[[self spacesOfLength:KSJSON_EMBEDDED_FILE_WINDOW] stringByAppendingString:@"1"]
                            result:&result];
    XCTAssertEqual(result, KSJSON_OK, @"leading whitespace filling the window must not look like truncation");
    XCTAssertEqualObjects(value, @1);

    // Elements whose length is known up front, straddling the boundary.
    for (NSUInteger pad = KSJSON_EMBEDDED_FILE_WINDOW - 3; pad <= KSJSON_EMBEDDED_FILE_WINDOW; pad++) {
        value = [self embedFileWithContent:[[self spacesOfLength:pad] stringByAppendingString:@"true"] result:&result];
        XCTAssertEqual(result, KSJSON_OK, @"true starting %lu bytes in", (unsigned long)pad);
        XCTAssertEqualObjects(value, @YES);

        value = [self embedFileWithContent:[[self spacesOfLength:pad] stringByAppendingString:@"null"] result:&result];
        XCTAssertEqual(result, KSJSON_OK, @"null starting %lu bytes in", (unsigned long)pad);
        XCTAssertEqualObjects(value, [NSNull null]);
    }
}

// A string is scanned to its closing quote, which may be past the end of the window.
- (void)testStringStraddlingTheFileWindow
{
    for (NSUInteger pad = KSJSON_EMBEDDED_FILE_WINDOW - 6; pad <= KSJSON_EMBEDDED_FILE_WINDOW; pad++) {
        int result = KSJSON_OK;
        id value = [self embedFileWithContent:[[self spacesOfLength:pad] stringByAppendingString:@"\"hello\""]
                                       result:&result];
        XCTAssertEqual(result, KSJSON_OK, @"string starting %lu bytes in", (unsigned long)pad);
        XCTAssertEqualObjects(value, @"hello");
    }
}

#pragma mark - Nesting

// How much nesting is left depends on how deep the destination already is, so the check
// has to be asked about a destination. One that just fits, and one that does not.
- (void)testCheckAgreesWithAddAtTheDepthBoundary
{
    for (int destinationDepth = 0; destinationDepth <= 20; destinationDepth += 10) {
        // ksjson_beginObject for the element itself takes one of the remaining levels.
        const int justFits = KSJSON_MAX_CONTAINER_DEPTH - destinationDepth - 2;

        for (int payloadDepth = justFits - 1; payloadDepth <= justFits + 2; payloadDepth++) {
            const char *bytes = [self nestedPayloadOfDepth:payloadDepth].UTF8String;

            NSMutableData *encodedData = [NSMutableData data];
            KSJSONEncodeContext context = { 0 };
            ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
            [self nestEncoder:&context toDepth:destinationDepth];

            int checkResult = ksjson_checkJSONElement(&context, bytes, (int)strlen(bytes));
            int addResult = ksjson_addJSONElement(&context, NULL, bytes, (int)strlen(bytes), true);
            XCTAssertEqual(checkResult, addResult, @"payload %d deep into a destination %d deep", payloadDepth,
                           destinationDepth);
        }

        XCTAssertEqual([self checkElement:[self nestedPayloadOfDepth:justFits].UTF8String atDepth:destinationDepth],
                       KSJSON_OK, @"a payload that fits must be accepted at depth %d", destinationDepth);
        XCTAssertEqual([self checkElement:[self nestedPayloadOfDepth:justFits + 2].UTF8String atDepth:destinationDepth],
                       KSJSON_ERROR_DATA_TOO_LONG, @"a payload that does not fit must be refused at depth %d",
                       destinationDepth);
    }
}

#pragma mark - String limits

/** A JSON payload whose single key or value decodes to `decodedLength` bytes, written
 * using `escape` repeated as needed.
 */
- (NSString *)payloadWithEscape:(NSString *)escape count:(int)count inKey:(BOOL)inKey
{
    NSMutableString *repeated = [NSMutableString string];
    for (int i = 0; i < count; i++) {
        [repeated appendString:escape];
    }
    return inKey ? [NSString stringWithFormat:@"{\"%@\":1}", repeated]
                 : [NSString stringWithFormat:@"{\"a\":\"%@\"}", repeated];
}

// The limit is on decoded bytes. Escapes only ever shrink, so what matters is what the
// value becomes, not how wide it was written.
- (void)testStringLimitCountsDecodedBytes
{
    // \n is two source bytes for one decoded byte.
    XCTAssertEqual(
        [self checkElement:[self payloadWithEscape:@"\\n" count:KSJSON_MAX_EMBEDDED_STRING_LENGTH inKey:NO].UTF8String
                   atDepth:0],
        KSJSON_OK, @"a value of exactly the limit must fit");
    XCTAssertEqual(
        [self
            checkElement:[self payloadWithEscape:@"\\n" count:KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1 inKey:NO].UTF8String
                 atDepth:0],
        KSJSON_ERROR_DATA_TOO_LONG, @"one decoded byte over the limit must be refused");

    // a is six source bytes for one decoded byte.
    XCTAssertEqual(
        [self
            checkElement:[self payloadWithEscape:@"\\u0061" count:KSJSON_MAX_EMBEDDED_STRING_LENGTH inKey:NO].UTF8String
                 atDepth:0],
        KSJSON_OK, @"one-byte escapes must be charged one byte each");
    XCTAssertEqual([self checkElement:[self payloadWithEscape:@"\\u0061"
                                                        count:KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1
                                                        inKey:NO]
                                          .UTF8String
                              atDepth:0],
                   KSJSON_ERROR_DATA_TOO_LONG);
}

// Three-byte code points and surrogate pairs are charged what they encode to.
- (void)testStringLimitChargesWideCodePointsTheirRealWidth
{
    const int threeByteCount = KSJSON_MAX_EMBEDDED_STRING_LENGTH / 3;
    XCTAssertEqual([self checkElement:[self payloadWithEscape:@"\\u4e2d" count:threeByteCount inKey:NO].UTF8String
                              atDepth:0],
                   KSJSON_OK, @"three-byte code points must fit up to the limit");
    XCTAssertEqual([self checkElement:[self payloadWithEscape:@"\\u4e2d" count:threeByteCount + 1 inKey:NO].UTF8String
                              atDepth:0],
                   KSJSON_ERROR_DATA_TOO_LONG, @"and must be refused past it");

    // A surrogate pair is twelve source bytes for four decoded ones.
    const int pairCount = KSJSON_MAX_EMBEDDED_STRING_LENGTH / 4;
    XCTAssertEqual([self checkElement:[self payloadWithEscape:@"\\ud83d\\ude00" count:pairCount inKey:NO].UTF8String
                              atDepth:0],
                   KSJSON_OK, @"surrogate pairs must fit up to the limit");
    XCTAssertEqual([self checkElement:[self payloadWithEscape:@"\\ud83d\\ude00" count:pairCount + 1 inKey:NO].UTF8String
                              atDepth:0],
                   KSJSON_ERROR_DATA_TOO_LONG, @"and must be refused past it");
}

// Keys go through the same decoder as values and are bounded the same way.
- (void)testStringLimitAppliesToKeysAsWell
{
    XCTAssertEqual([self checkElement:[self payloadWithEscape:@"\\u0061"
                                                        count:KSJSON_MAX_EMBEDDED_STRING_LENGTH
                                                        inKey:YES]
                                          .UTF8String
                              atDepth:0],
                   KSJSON_OK, @"a key of exactly the limit must fit");
    XCTAssertEqual([self checkElement:[self payloadWithEscape:@"\\u0061"
                                                        count:KSJSON_MAX_EMBEDDED_STRING_LENGTH + 1
                                                        inKey:YES]
                                          .UTF8String
                              atDepth:0],
                   KSJSON_ERROR_DATA_TOO_LONG, @"one decoded byte over the limit must be refused in a key too");
}

// Values embed unchanged, escapes and all.
- (void)testEscapedValuesRoundTripThroughEmbedding
{
    const char *json = "{\"a\":\"x\\u0061\\u4e2d\\ud83d\\ude00\\n\"}";

    NSMutableData *encodedData = [NSMutableData data];
    KSJSONEncodeContext context = { 0 };
    ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));
    XCTAssertEqual(ksjson_addJSONElement(&context, NULL, json, (int)strlen(json), true), KSJSON_OK);
    ksjson_endEncode(&context);

    NSDictionary *decoded = [NSJSONSerialization JSONObjectWithData:encodedData options:0 error:nil];
    XCTAssertEqualObjects(decoded[@"a"], @"xa中\U0001F600\n");
}

- (void)testCheckJSONFile
{
    NSString *goodPath = [self.tempPath stringByAppendingPathComponent:@"good.json"];
    XCTAssertTrue([[@"{\"a\":1}" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:goodPath atomically:YES]);
    XCTAssertEqual([self checkFile:goodPath atDepth:0], KSJSON_OK);

    NSString *badPath = [self.tempPath stringByAppendingPathComponent:@"bad.json"];
    NSData *badData = [[self jsonWithOversizedString] dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([badData writeToFile:badPath atomically:YES]);
    XCTAssertEqual([self checkFile:badPath atDepth:0], KSJSON_ERROR_DATA_TOO_LONG);

    NSString *missingPath = [self.tempPath stringByAppendingPathComponent:@"nope.json"];
    XCTAssertNotEqual([self checkFile:missingPath atDepth:0], KSJSON_OK);
}

- (void)testEncoderRefusesToNestPastItsLimit
{
    // isObject[] is indexed by containerLevel, so this is a bounds check, not a policy.
    NSMutableData *encodedData = [NSMutableData data];
    KSJSONEncodeContext context = { 0 };
    ksjson_beginEncode(&context, false, addJSONData, (__bridge void *)(encodedData));

    int depth = 0;
    while (ksjson_beginArray(&context, NULL) == KSJSON_OK) {
        depth++;
        XCTAssertLessThan(depth, KSJSON_MAX_CONTAINER_DEPTH + 1, @"beginArray must stop before overrunning isObject");
    }
    XCTAssertLessThan(context.containerLevel, KSJSON_MAX_CONTAINER_DEPTH);
}

- (void)testSerializeDeserializeIntegerEdgeCases
{
    [self testIntegerSerialization:INT_MAX];
    [self testIntegerSerialization:INT_MIN];
    [self testIntegerSerialization:LONG_MAX];
    [self testIntegerSerialization:LONG_MIN];
    [self testIntegerSerialization:LLONG_MAX];
    [self testIntegerSerialization:LLONG_MIN];
    [self testIntegerSerialization:(1LL << 31) - 1];
    [self testIntegerSerialization:1LL << 31];
    [self testIntegerSerialization:(1LL << 31) + 1];
}

- (void)testSerializeDeserializeUnsignedIntegerEdgeCases
{
    [self testUnsignedIntegerSerialization:UINT_MAX];
    [self testUnsignedIntegerSerialization:ULONG_MAX];
    [self testUnsignedIntegerSerialization:ULLONG_MAX];
    [self testUnsignedIntegerSerialization:(1ULL << 32) - 1];
    [self testUnsignedIntegerSerialization:1ULL << 32];
    [self testUnsignedIntegerSerialization:(1ULL << 32) + 1];
}

- (void)testSerializeDeserializeFloatEdgeCases
{
    [self testFloatSerialization:FLT_MIN];
    [self testFloatSerialization:FLT_MAX];
    [self testFloatSerialization:-0.0f];
    [self testFloatSerialization:0.0f];
    [self testFloatSerialization:INFINITY];
    [self testFloatSerialization:-INFINITY];
    [self testFloatSerialization:NAN];
    [self testFloatSerialization:0.123456789f];  // More digits than float precision
    [self testFloatSerialization:1.000001f];
    [self testFloatSerialization:0.999999f];
}

- (void)testSerializeDeserializeDoubleEdgeCases
{
    [self testDoubleSerialization:DBL_MIN];
    //    [self testDoubleSerialization:DBL_MAX]; // Attributed as +inf
    [self testDoubleSerialization:-0.0];
    [self testDoubleSerialization:0.0];
    [self testDoubleSerialization:INFINITY];
    [self testDoubleSerialization:-INFINITY];
    [self testDoubleSerialization:NAN];
    //    [self testDoubleSerialization:0.123456789012345]; // Attributed as float
    [self testDoubleSerialization:1.000000000000001];
    [self testDoubleSerialization:0.999999999999999];
    //    [self testDoubleSerialization:1234567.8]; // Attributed as float and deoceded as 12345670
    //    [self testDoubleSerialization:1.000000001]; // Counted as 1
}

- (void)testIntegerSerialization:(long long)value
{
    NSError *error = nil;
    NSNumber *number = @(value);
    NSArray *array = @[ number ];
    NSString *jsonString = toString([KSJSONCodec encode:array options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString);
    XCTAssertNil(error);

    NSArray *decodedArray = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(decodedArray);
    XCTAssertNil(error);

    // For very large numbers, JSON might lose precision, so we compare string representations
    NSString *originalString = [number stringValue];
    NSString *decodedString = [decodedArray[0] stringValue];
    XCTAssertEqualObjects(originalString, decodedString);
}

- (void)testUnsignedIntegerSerialization:(unsigned long long)value
{
    NSError *error = nil;
    NSNumber *number = @(value);
    NSArray *array = @[ number ];
    NSString *jsonString = toString([KSJSONCodec encode:array options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString);
    XCTAssertNil(error);

    NSArray *decodedArray = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(decodedArray);
    XCTAssertNil(error);

    // For very large numbers, JSON might lose precision, so we compare string representations
    NSString *originalString = [number stringValue];
    NSString *decodedString = [decodedArray[0] stringValue];
    XCTAssertEqualObjects(originalString, decodedString);
}

- (void)testFloatSerialization:(float)value
{
    NSError *error = nil;
    NSNumber *number = @(value);
    NSArray *array = @[ number ];
    NSString *jsonString = toString([KSJSONCodec encode:array options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString);
    XCTAssertNil(error);

    NSArray *decodedArray = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(decodedArray);
    XCTAssertNil(error);

    if (isnan(value)) {
        XCTAssertTrue([decodedArray[0] isKindOfClass:[NSNull class]], @"NaN should be decoded as NSNull");
    } else if (isinf(value)) {
        if (value > 0) {
            XCTAssertEqualObjects(jsonString, @"[1e999]",
                                  @"Positive infinity should be encoded as a very large number");
        } else {
            XCTAssertEqualObjects(jsonString, @"[-1e999]",
                                  @"Negative infinity should be encoded as a very large negative number");
        }
        AssertAround([decodedArray[0] floatValue], value);
    } else {
        XCTAssertEqualWithAccuracy([decodedArray[0] floatValue], value, FLT_EPSILON * fabsf(value) * 100);
    }
}

- (void)testDoubleSerialization:(double)value
{
    NSError *error = nil;
    NSNumber *number = @(value);
    NSArray *array = @[ number ];
    NSString *jsonString = toString([KSJSONCodec encode:array options:KSJSONEncodeOptionSorted error:&error]);
    XCTAssertNotNil(jsonString);
    XCTAssertNil(error);

    NSArray *decodedArray = [KSJSONCodec decode:toData(jsonString) options:0 error:&error];
    XCTAssertNotNil(decodedArray);
    XCTAssertNil(error);

    if (isnan(value)) {
        XCTAssertTrue([decodedArray[0] isKindOfClass:[NSNull class]], @"NaN should be decoded as NSNull");
    } else if (isinf(value)) {
        if (value > 0) {
            XCTAssertEqualObjects(jsonString, @"[1e999]",
                                  @"Positive infinity should be encoded as a very large number");
        } else {
            XCTAssertEqualObjects(jsonString, @"[-1e999]",
                                  @"Negative infinity should be encoded as a very large negative number");
        }
        AssertAround([decodedArray[0] doubleValue], value);
    } else {
        XCTAssertEqualWithAccuracy([decodedArray[0] doubleValue], value, DBL_EPSILON * fabs(value) * 100);
    }
}

#pragma mark - C-level encoder tests (signal-safe formatters)

// Accumulator callback: appends JSON data to a char buffer.
typedef struct {
    char buf[1024];
    int pos;
} JSONBuf;

static int appendJSONData(const char *data, int length, void *userData)
{
    JSONBuf *jb = (JSONBuf *)userData;
    if (jb->pos + length < (int)sizeof(jb->buf)) {
        memcpy(jb->buf + jb->pos, data, (size_t)length);
        jb->pos += length;
        jb->buf[jb->pos] = '\0';
    }
    return KSJSON_OK;
}

- (NSString *)encodeValue:(void (^)(KSJSONEncodeContext *ctx))block
{
    JSONBuf jb = { .pos = 0 };
    jb.buf[0] = '\0';
    KSJSONEncodeContext ctx;
    ksjson_beginEncode(&ctx, false, appendJSONData, &jb);
    ksjson_beginArray(&ctx, NULL);
    block(&ctx);
    ksjson_endContainer(&ctx);
    ksjson_endEncode(&ctx);
    return [NSString stringWithUTF8String:jb.buf];
}

- (void)testCEncoderInteger
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addIntegerElement(ctx, NULL, 42);
    }];
    XCTAssertEqualObjects(json, @"[42]");
}

- (void)testCEncoderNegativeInteger
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addIntegerElement(ctx, NULL, -1);
    }];
    XCTAssertEqualObjects(json, @"[-1]");
}

- (void)testCEncoderIntegerMax
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addIntegerElement(ctx, NULL, INT64_MAX);
    }];
    XCTAssertEqualObjects(json, @"[9223372036854775807]");
}

- (void)testCEncoderIntegerMin
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addIntegerElement(ctx, NULL, INT64_MIN);
    }];
    XCTAssertEqualObjects(json, @"[-9223372036854775808]");
}

- (void)testCEncoderUnsignedMax
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addUIntegerElement(ctx, NULL, UINT64_MAX);
    }];
    XCTAssertEqualObjects(json, @"[18446744073709551615]");
}

- (void)testCEncoderUnsignedZero
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addUIntegerElement(ctx, NULL, 0);
    }];
    XCTAssertEqualObjects(json, @"[0]");
}

- (void)testCEncoderFloatZero
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addFloatingPointElement(ctx, NULL, 0.0);
    }];
    XCTAssertEqualObjects(json, @"[0.0]");
}

- (void)testCEncoderFloatNaN
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addFloatingPointElement(ctx, NULL, NAN);
    }];
    XCTAssertEqualObjects(json, @"[null]");
}

- (void)testCEncoderFloatInf
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addFloatingPointElement(ctx, NULL, INFINITY);
    }];
    XCTAssertEqualObjects(json, @"[1e999]");
}

- (void)testCEncoderFloatNegInf
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addFloatingPointElement(ctx, NULL, -INFINITY);
    }];
    XCTAssertEqualObjects(json, @"[-1e999]");
}

- (void)testCEncoderFloatPi
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addFloatingPointElement(ctx, NULL, 3.14159);
    }];
    // 3.14159 fits in float precision, so FLT_DIG (6) significant digits
    double parsed = strtod([json substringWithRange:NSMakeRange(1, json.length - 2)].UTF8String, NULL);
    XCTAssertEqualWithAccuracy(parsed, 3.14159, 0.0001);
}

- (void)testCEncoderFloatSmallNegative
{
    NSString *json = [self encodeValue:^(KSJSONEncodeContext *ctx) {
        ksjson_addFloatingPointElement(ctx, NULL, -0.2);
    }];
    XCTAssertTrue([json hasPrefix:@"[-0."], @"Expected [-0., got %@", json);
}

- (void)testCEncoderObjectWithNumbers
{
    JSONBuf jb = { .pos = 0 };
    jb.buf[0] = '\0';
    KSJSONEncodeContext ctx;
    ksjson_beginEncode(&ctx, false, appendJSONData, &jb);
    ksjson_beginObject(&ctx, NULL);
    ksjson_addIntegerElement(&ctx, "count", 100);
    ksjson_addFloatingPointElement(&ctx, "ratio", 0.5);
    ksjson_addUIntegerElement(&ctx, "addr", 0xDEADBEEF);
    ksjson_endContainer(&ctx);
    ksjson_endEncode(&ctx);
    NSString *json = [NSString stringWithUTF8String:jb.buf];
    XCTAssertEqualObjects(json, @"{\"count\":100,\"ratio\":0.5,\"addr\":3735928559}");
}

@end
