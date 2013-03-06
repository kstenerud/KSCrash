//
//  KSLogger_Tests.m
//  KSCrash
//
//  Created by Karl Stenerud on 1/26/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "SenTestCase+KSCrash.h"
#import "ARCSafe_MemMgmt.h"
#import "KSLogger.h"

@interface KSLogger_Tests : SenTestCase

@property(nonatomic, readwrite, retain) NSString* tempDir;

@end

@implementation KSLogger_Tests

@synthesize tempDir = _tempDir;

- (void) dealloc
{
    as_release(_tempDir);
    as_superdealloc();
}

- (void) setUp
{
    [super setUp];
    self.tempDir = [self createTempPath];
}

- (void) tearDown
{
    [self removePath:self.tempDir];
}

- (void) testLogError
{
    KSLOG_ERROR(@"TEST");
}

- (void) testLogErrorNull
{
    KSLOG_ERROR(nil);
}

- (void) testLogAlways
{
    KSLOG_ALWAYS(@"TEST");
}

- (void) testLogAlwaysNull
{
    KSLOG_ALWAYS(nil);
}

- (void) testLogBasicError
{
    KSLOGBASIC_ERROR(@"TEST");
}

- (void) testLogBasicErrorNull
{
    KSLOGBASIC_ERROR(nil);
}

- (void) testLogBasicAlways
{
    KSLOGBASIC_ALWAYS(@"TEST");
}

- (void) testLogBasicAlwaysNull
{
    KSLOGBASIC_ALWAYS(nil);
}

- (void) testSetLogFilename
{
    NSString* expected = @"TEST";
    NSString* logFileName = [self.tempDir stringByAppendingPathComponent:@"log.txt"];
    kslog_setLogFilename([logFileName UTF8String], true);
    KSLOGBASIC_ALWAYS(expected);
    kslog_setLogFilename(nil, true);

    NSError* error = nil;
    NSString* result = [NSString stringWithContentsOfFile:logFileName encoding:NSUTF8StringEncoding error:&error];
    STAssertNil(error, @"");
    result = [[result componentsSeparatedByString:@"\x0a"] objectAtIndex:0];
    STAssertEqualObjects(result, expected, @"");

    KSLOGBASIC_ALWAYS(@"blah blah");
    result = [NSString stringWithContentsOfFile:logFileName encoding:NSUTF8StringEncoding error:&error];
    result = [[result componentsSeparatedByString:@"\x0a"] objectAtIndex:0];
    STAssertNil(error, @"");
    STAssertEqualObjects(result, expected, @"");
}

@end
