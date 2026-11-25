//
//  KSFileUtils_Tests.m
//
//  Created by Karl Stenerud on 2012-01-28.
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

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
#import "FileBasedTestCase.h"

#import "KSFileUtils.h"

@interface KSFileUtils_Tests : FileBasedTestCase
@end

@implementation KSFileUtils_Tests

- (void)testReadBuffered_EmptyFile
{
    int readBufferSize = 10;
    int dstBufferSize = 5;
    int readSize = 5;
    int expectedBytesRead = 0;
    NSString *fileContents = @"";
    NSString *expectedDataRead = @"";
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    int bytesRead = ksfu_readBufferedReader(&reader, dstBuffer, readSize);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBuffered_SameSize
{
    int readBufferSize = 10;
    int dstBufferSize = 5;
    int readSize = 5;
    int expectedBytesRead = 5;
    NSString *fileContents = @"12345";
    NSString *expectedDataRead = @"12345";
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    int bytesRead = ksfu_readBufferedReader(&reader, dstBuffer, readSize);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBuffered_FileIsBigger
{
    int readBufferSize = 10;
    int dstBufferSize = 5;
    int readSize = 5;
    int expectedBytesRead = 5;
    NSString *fileContents = @"123456789";
    NSString *expectedDataRead = @"12345";
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    int bytesRead = ksfu_readBufferedReader(&reader, dstBuffer, readSize);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBuffered_ReadBufferIsSmaller
{
    int readBufferSize = 3;
    int dstBufferSize = 5;
    int readSize = 5;
    int expectedBytesRead = 5;
    NSString *fileContents = @"12345";
    NSString *expectedDataRead = @"12345";
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    int bytesRead = ksfu_readBufferedReader(&reader, dstBuffer, readSize);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBuffered_ReadBufferIsMuchSmaller
{
    int readBufferSize = 3;
    int dstBufferSize = 16;
    int readSize = 16;
    int expectedBytesRead = 16;
    NSString *fileContents = @"1234567890abcdef";
    NSString *expectedDataRead = @"1234567890abcdef";
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    int bytesRead = ksfu_readBufferedReader(&reader, dstBuffer, readSize);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBufferedUntilChar_Halfway
{
    int readBufferSize = 10;
    int dstBufferSize = 5;
    NSString *fileContents = @"12345";
    int ch = '3';
    NSString *expectedDataRead = @"123";
    int expectedBytesRead = (int)expectedDataRead.length;
    int bytesRead = dstBufferSize;
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    bool result = ksfu_readBufferedReaderUntilChar(&reader, ch, dstBuffer, &bytesRead);
    XCTAssertTrue(result);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBufferedUntilChar_Beginning
{
    int readBufferSize = 10;
    int dstBufferSize = 5;
    NSString *fileContents = @"12345";
    int ch = '1';
    NSString *expectedDataRead = @"1";
    int expectedBytesRead = (int)expectedDataRead.length;
    int bytesRead = dstBufferSize;
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    bool result = ksfu_readBufferedReaderUntilChar(&reader, ch, dstBuffer, &bytesRead);
    XCTAssertTrue(result);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBufferedUntilChar_End
{
    int readBufferSize = 10;
    int dstBufferSize = 5;
    NSString *fileContents = @"12345";
    int ch = '5';
    NSString *expectedDataRead = @"12345";
    int expectedBytesRead = (int)expectedDataRead.length;
    int bytesRead = dstBufferSize;
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    bool result = ksfu_readBufferedReaderUntilChar(&reader, ch, dstBuffer, &bytesRead);
    XCTAssertTrue(result);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBufferedUntilChar_SmallDstBuffer
{
    int readBufferSize = 10;
    int dstBufferSize = 3;
    NSString *fileContents = @"12345";
    int ch = '5';
    NSString *expectedDataRead = @"123";
    int expectedBytesRead = (int)expectedDataRead.length;
    int bytesRead = dstBufferSize;
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    bool result = ksfu_readBufferedReaderUntilChar(&reader, ch, dstBuffer, &bytesRead);
    XCTAssertTrue(result);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBufferedUntilChar_SmallReadBuffer
{
    int readBufferSize = 4;
    int dstBufferSize = 10;
    NSString *fileContents = @"1234567890";
    int ch = '9';
    NSString *expectedDataRead = @"123456789";
    int expectedBytesRead = (int)expectedDataRead.length;
    int bytesRead = dstBufferSize;
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    bool result = ksfu_readBufferedReaderUntilChar(&reader, ch, dstBuffer, &bytesRead);
    XCTAssertTrue(result);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBufferedUntilChar_NotFound
{
    int readBufferSize = 3;
    int dstBufferSize = 8;
    NSString *fileContents = @"12345";
    int ch = '9';
    NSString *expectedDataRead = @"12345";
    int expectedBytesRead = (int)expectedDataRead.length;
    int bytesRead = dstBufferSize;
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    bool result = ksfu_readBufferedReaderUntilChar(&reader, ch, dstBuffer, &bytesRead);
    XCTAssertFalse(result);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testReadBufferedUntilChar_NotFound_LargeFile
{
    int readBufferSize = 4;
    int dstBufferSize = 8;
    NSString *fileContents = @"1234567890";
    int ch = 'a';
    NSString *expectedDataRead = @"12345678";
    int expectedBytesRead = (int)expectedDataRead.length;
    int bytesRead = dstBufferSize;
    char readBuffer[readBufferSize];
    KSBufferedReader reader;
    NSString *path = [self generateFileWithString:fileContents];
    XCTAssertTrue(ksfu_openBufferedReader(&reader, path.UTF8String, readBuffer, readBufferSize));
    char dstBuffer[dstBufferSize + 1];
    bool result = ksfu_readBufferedReaderUntilChar(&reader, ch, dstBuffer, &bytesRead);
    XCTAssertFalse(result);
    XCTAssertEqual(bytesRead, expectedBytesRead);
    dstBuffer[bytesRead] = '\0';
    XCTAssertEqualObjects([NSString stringWithUTF8String:dstBuffer], expectedDataRead);
    ksfu_closeBufferedReader(&reader);
}

- (void)testWriteBuffered
{
    int writeBufferSize = 5;
    int writeSize = 5;
    NSString *fileContents = @"12345";
    char writeBuffer[writeBufferSize];
    KSBufferedWriter writer;
    NSString *path = [self generateTempFilePath];
    XCTAssertTrue(ksfu_openBufferedWriter(&writer, path.UTF8String, writeBuffer, writeBufferSize));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, fileContents.UTF8String, writeSize));
    ksfu_closeBufferedWriter(&writer);
    NSError *error = nil;
    NSString *actualFileContents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(actualFileContents, fileContents);
}

- (void)testWriteBuffered_Flush
{
    int writeBufferSize = 5;
    int writeSize = 5;
    NSString *fileContents = @"12345";
    char writeBuffer[writeBufferSize];
    KSBufferedWriter writer;
    NSString *path = [self generateTempFilePath];
    XCTAssertTrue(ksfu_openBufferedWriter(&writer, path.UTF8String, writeBuffer, writeBufferSize));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, fileContents.UTF8String, writeSize));
    ksfu_flushBufferedWriter(&writer);
    NSError *error = nil;
    NSString *actualFileContents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(actualFileContents, fileContents);
    ksfu_closeBufferedWriter(&writer);
}

- (void)testWriteBuffered_BufferIsSmaller
{
    int writeBufferSize = 4;
    int writeSize = 10;
    NSString *fileContents = @"1234567890";
    char writeBuffer[writeBufferSize];
    KSBufferedWriter writer;
    NSString *path = [self generateTempFilePath];
    XCTAssertTrue(ksfu_openBufferedWriter(&writer, path.UTF8String, writeBuffer, writeBufferSize));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, fileContents.UTF8String, writeSize));
    ksfu_closeBufferedWriter(&writer);
    NSError *error = nil;
    NSString *actualFileContents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(actualFileContents, fileContents);
}

- (void)testWriteBuffered_DataIsSmaller
{
    int writeBufferSize = 10;
    int writeSize = 3;
    NSString *fileContents = @"123";
    char writeBuffer[writeBufferSize];
    KSBufferedWriter writer;
    NSString *path = [self generateTempFilePath];
    XCTAssertTrue(ksfu_openBufferedWriter(&writer, path.UTF8String, writeBuffer, writeBufferSize));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, fileContents.UTF8String, writeSize));
    ksfu_closeBufferedWriter(&writer);
    NSError *error = nil;
    NSString *actualFileContents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(actualFileContents, fileContents);
}

// open() hands out descriptor 0 when stdin is closed. Stdin is swapped for the file with dup2 rather than closed,
// so 0 is unassigned only between the writer's close and the restore; while it is, another thread's open() could
// take it.
- (void)testWriteBuffered_DescriptorZero
{
    NSString *path = [self generateTempFilePath];
    int fileFD = open(path.UTF8String, O_RDWR | O_CREAT | O_EXCL, 0644);
    XCTAssertGreaterThan(fileFD, 0);
    int savedStdin = dup(STDIN_FILENO);
    XCTAssertGreaterThanOrEqual(savedStdin, 0);
    XCTAssertEqual(dup2(fileFD, STDIN_FILENO), STDIN_FILENO);
    close(fileFD);

    // Guard bytes past the buffer catch an append that copies beyond it.
    char storage[16];
    memset(storage, 'G', sizeof(storage));
    KSBufferedWriter writer = { .buffer = storage, .bufferLength = 4, .position = 0, .fd = STDIN_FILENO };
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, "1234", 4));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, "5678", 4));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, "90", 2));
    XCTAssertEqual(memcmp(storage + 4, "GGGGGGGGGGGG", 12), 0);
    ksfu_closeBufferedWriter(&writer);
    XCTAssertEqual(writer.fd, -1);
    XCTAssertEqual(fcntl(STDIN_FILENO, F_GETFD), -1, @"close should have closed descriptor 0");

    XCTAssertEqual(dup2(savedStdin, STDIN_FILENO), STDIN_FILENO);
    close(savedStdin);

    NSError *error = nil;
    NSString *actualFileContents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(actualFileContents, @"1234567890");
}

- (void)testWriteBuffered_FlushWithoutFileFails
{
    char storage[16];
    memset(storage, 'G', sizeof(storage));
    KSBufferedWriter writer = { .buffer = storage, .bufferLength = 4, .position = 0, .fd = -1 };
    XCTAssertTrue(ksfu_flushBufferedWriter(&writer));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, "12", 2));
    XCTAssertFalse(ksfu_flushBufferedWriter(&writer));
    XCTAssertFalse(ksfu_writeBufferedWriter(&writer, "345", 3));
    XCTAssertEqual(writer.position, 2);
    XCTAssertEqual(memcmp(storage + 4, "GGGGGGGGGGGG", 12), 0);
}

- (void)testReadBuffered_CloseDescriptorZero
{
    NSString *path = [self generateTempFilePath];
    int fileFD = open(path.UTF8String, O_RDWR | O_CREAT | O_EXCL, 0644);
    XCTAssertGreaterThan(fileFD, 0);
    int savedStdin = dup(STDIN_FILENO);
    XCTAssertGreaterThanOrEqual(savedStdin, 0);
    XCTAssertEqual(dup2(fileFD, STDIN_FILENO), STDIN_FILENO);
    close(fileFD);

    char readBuffer[4];
    KSBufferedReader reader = {
        .buffer = readBuffer, .bufferLength = 3, .dataStartPos = 0, .dataEndPos = 0, .fd = STDIN_FILENO
    };
    ksfu_closeBufferedReader(&reader);
    XCTAssertEqual(reader.fd, -1);
    XCTAssertEqual(fcntl(STDIN_FILENO, F_GETFD), -1, @"close should have closed descriptor 0");

    XCTAssertEqual(dup2(savedStdin, STDIN_FILENO), STDIN_FILENO);
    close(savedStdin);
}

- (void)testLastPathEntry
{
    NSString *path = @"some/kind/of/path";
    NSString *expected = @"path";
    NSString *actual = [NSString stringWithCString:ksfu_lastPathEntry([path cStringUsingEncoding:NSUTF8StringEncoding])
                                          encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void)testWriteBytesToFD
{
    NSError *error = nil;
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"test.txt"];
    NSString *expected = @"testing a bunch of stuff.\nOh look, a newline!";
    int stringLength = (int)[expected length];

    int fd = open([path UTF8String], O_RDWR | O_CREAT | O_EXCL, 0644);
    XCTAssertTrue(fd >= 0, @"");
    bool result = ksfu_writeBytesToFD(fd, [expected cStringUsingEncoding:NSUTF8StringEncoding], stringLength);
    XCTAssertTrue(result, @"");
    NSString *actual = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void)testWriteBytesToFDBig
{
    NSError *error = nil;
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"test.txt"];
    int length = 1000000;
    NSMutableData *expected = [NSMutableData dataWithCapacity:(NSUInteger)length];
    for (int i = 0; i < length; i++) {
        unsigned char byte = (unsigned char)i;
        [expected appendBytes:&byte length:1];
    }

    int fd = open([path UTF8String], O_RDWR | O_CREAT | O_EXCL, 0644);
    XCTAssertTrue(fd >= 0, @"");
    bool result = ksfu_writeBytesToFD(fd, [expected bytes], length);
    XCTAssertTrue(result, @"");
    NSMutableData *actual = [NSMutableData dataWithContentsOfFile:path options:0 error:&error];
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void)testReadBytesFromFD
{
    NSError *error = nil;
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"test.txt"];
    NSString *expected = @"testing a bunch of stuff.\nOh look, a newline!";
    int stringLength = (int)[expected length];
    [expected writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error, @"");

    int fd = open([path UTF8String], O_RDONLY);
    XCTAssertTrue(fd >= 0, @"");
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)stringLength];
    bool result = ksfu_readBytesFromFD(fd, [data mutableBytes], stringLength);
    XCTAssertTrue(result, @"");
    NSString *actual = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void)testReadBytesFromFDBig
{
    NSError *error = nil;
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"test.txt"];
    int length = 1000000;
    NSMutableData *expected = [NSMutableData dataWithCapacity:(NSUInteger)length];
    for (int i = 0; i < length; i++) {
        unsigned char byte = (unsigned char)i;
        [expected appendBytes:&byte length:1];
    }
    [expected writeToFile:path options:0 error:&error];
    XCTAssertNil(error, @"");

    int fd = open([path UTF8String], O_RDONLY);
    XCTAssertTrue(fd >= 0, @"");
    NSMutableData *actual = [NSMutableData dataWithLength:(NSUInteger)length];
    bool result = ksfu_readBytesFromFD(fd, [actual mutableBytes], length);
    XCTAssertTrue(result, @"");
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void)testReadEntireFile
{
    NSError *error = nil;
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"test.txt"];
    NSString *expected = @"testing a bunch of stuff.\nOh look, a newline!";
    [expected writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error, @"");

    int fd = open([path UTF8String], O_RDONLY);
    XCTAssertTrue(fd >= 0, @"");
    char *bytes;
    int readLength;
    bool result = ksfu_readEntireFile([path UTF8String], &bytes, &readLength, 0);
    XCTAssertTrue(result, @"");
    NSMutableData *data = [NSMutableData dataWithBytesNoCopy:bytes length:(unsigned)readLength freeWhenDone:YES];
    NSString *actual = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void)testReadEntireFileBig
{
    NSError *error = nil;
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"test.txt"];
    int length = 1000000;
    NSMutableData *expected = [NSMutableData dataWithCapacity:(NSUInteger)length];
    for (int i = 0; i < length; i++) {
        unsigned char byte = (unsigned char)i;
        [expected appendBytes:&byte length:1];
    }
    [expected writeToFile:path options:0 error:&error];
    XCTAssertNil(error, @"");

    int fd = open([path UTF8String], O_RDONLY);
    XCTAssertTrue(fd >= 0, @"");
    char *bytes;
    int readLength;
    bool result = ksfu_readEntireFile([path UTF8String], &bytes, &readLength, 0);
    XCTAssertTrue(result, @"");
    NSMutableData *actual = [NSMutableData dataWithBytesNoCopy:bytes length:(unsigned)readLength freeWhenDone:YES];
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void)testWriteStringToFD
{
    NSError *error = nil;
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"test.txt"];
    NSString *expected = @"testing a bunch of stuff.\nOh look, a newline!";

    int fd = open([path UTF8String], O_RDWR | O_CREAT | O_EXCL, 0644);
    XCTAssertTrue(fd >= 0, @"");
    bool result = ksfu_writeStringToFD(fd, [expected cStringUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertTrue(result, @"");
    NSString *actual = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void)testWriteFmtToFD
{
    NSError *error = nil;
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"test.txt"];
    NSString *expected = @"test test testing 1 2.0 3";

    int fd = open([path UTF8String], O_RDWR | O_CREAT | O_EXCL, 0644);
    XCTAssertTrue(fd >= 0, @"");
    bool result = ksfu_writeFmtToFD(fd, "test test testing %d %.1f %s", 1, 2.0f, "3");
    XCTAssertTrue(result, @"");
    NSString *actual = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(actual, expected, @"");
}

- (bool)writeToFD:(int)fd fmt:(char *)fmt, ...
{
    va_list args;
    va_start(args, fmt);
    bool result = ksfu_writeFmtArgsToFD(fd, fmt, args);
    va_end(args);
    return result;
}

- (void)testWriteFmtArgsToFD
{
    NSError *error = nil;
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"test.txt"];
    NSString *expected = @"test test testing 1 2.0 3";

    int fd = open([path UTF8String], O_RDWR | O_CREAT | O_EXCL, 0644);
    XCTAssertTrue(fd >= 0, @"");
    bool result = [self writeToFD:fd fmt:"test test testing %d %.1f %s", 1, 2.0f, "3"];
    XCTAssertTrue(result, @"");
    NSString *actual = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error, @"");
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void)testReadLineFromFD
{
    NSError *error = nil;
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"test.txt"];
    NSString *source = @"line 1\nline 2\nline 3";
    NSString *expected1 = @"line 1";
    NSString *expected2 = @"line 2";
    NSString *expected3 = @"line 3";
    [source writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error, @"");

    int fd = open([path UTF8String], O_RDONLY);
    XCTAssertTrue(fd >= 0, @"");
    NSMutableData *data = [NSMutableData dataWithLength:100];
    int bytesRead;
    NSString *actual;

    bytesRead = ksfu_readLineFromFD(fd, [data mutableBytes], 100);
    XCTAssertTrue(bytesRead > 0, @"");
    actual = [[NSString alloc] initWithBytes:[data bytes] length:(NSUInteger)bytesRead encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(actual, expected1, @"");

    bytesRead = ksfu_readLineFromFD(fd, [data mutableBytes], 100);
    XCTAssertTrue(bytesRead > 0, @"");
    actual = [[NSString alloc] initWithBytes:[data bytes] length:(NSUInteger)bytesRead encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(actual, expected2, @"");

    bytesRead = ksfu_readLineFromFD(fd, [data mutableBytes], 100);
    XCTAssertTrue(bytesRead > 0, @"");
    actual = [[NSString alloc] initWithBytes:[data bytes] length:(NSUInteger)bytesRead encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(actual, expected3, @"");

    bytesRead = ksfu_readLineFromFD(fd, [data mutableBytes], 100);
    XCTAssertTrue(bytesRead == 0, @"");
}

- (void)testWriteBuffered_OrderOfEntries
{
    int writeBufferSize = 10;
    NSString *logEntry1 = @"Log1";
    NSString *logEntry2 = @"Log2";
    NSString *logEntry3 = @"Log3";
    char writeBuffer[writeBufferSize];
    KSBufferedWriter writer;
    NSString *path = [self generateTempFilePath];
    XCTAssertTrue(ksfu_openBufferedWriter(&writer, path.UTF8String, writeBuffer, writeBufferSize));

    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, logEntry1.UTF8String, (int)logEntry1.length));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, logEntry2.UTF8String, (int)logEntry2.length));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, logEntry3.UTF8String, (int)logEntry3.length));

    ksfu_closeBufferedWriter(&writer);
    NSError *error = nil;
    NSString *actualFileContents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    NSString *expectedContents = @"Log1Log2Log3";
    XCTAssertEqualObjects(actualFileContents, expectedContents);
}

- (void)testWriteBuffered_OrderWithLargeData
{
    int writeBufferSize = 10;
    NSString *logEntry1 = @"Small1";
    NSString *logEntry2 = @"ThisIsLargeData";
    NSString *logEntry3 = @"Small3";
    char writeBuffer[writeBufferSize];
    KSBufferedWriter writer;
    NSString *path = [self generateTempFilePath];
    XCTAssertTrue(ksfu_openBufferedWriter(&writer, path.UTF8String, writeBuffer, writeBufferSize));

    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, logEntry1.UTF8String, (int)logEntry1.length));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, logEntry2.UTF8String, (int)logEntry2.length));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, logEntry3.UTF8String, (int)logEntry3.length));

    ksfu_closeBufferedWriter(&writer);
    NSError *error = nil;
    NSString *actualFileContents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    NSString *expectedContents = @"Small1ThisIsLargeDataSmall3";
    XCTAssertEqualObjects(actualFileContents, expectedContents);
}

- (void)testWriteBuffered_FlushAndLargeWriteOrder
{
    int writeBufferSize = 10;
    NSString *logEntry1 = @"Buffer1";
    NSString *logEntry2 = @"Buffer2";
    NSString *largeEntry = @"ThisIsLargeDataThatExceedsBufferSize";
    NSString *logEntry3 = @"EndData";
    char writeBuffer[writeBufferSize];
    KSBufferedWriter writer;
    NSString *path = [self generateTempFilePath];
    XCTAssertTrue(ksfu_openBufferedWriter(&writer, path.UTF8String, writeBuffer, writeBufferSize));

    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, logEntry1.UTF8String, (int)logEntry1.length));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, logEntry2.UTF8String, (int)logEntry2.length));
    // This should trigger a flush and write directly
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, largeEntry.UTF8String, (int)largeEntry.length));
    XCTAssertTrue(ksfu_writeBufferedWriter(&writer, logEntry3.UTF8String, (int)logEntry3.length));

    ksfu_closeBufferedWriter(&writer);
    NSError *error = nil;
    NSString *actualFileContents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    NSString *expectedContents = @"Buffer1Buffer2ThisIsLargeDataThatExceedsBufferSizeEndData";
    XCTAssertEqualObjects(actualFileContents, expectedContents);
}

#pragma mark - Memory Mapping Tests

- (void)testMunmap_NullPointer
{
    // munmap with NULL should return true (no-op)
    XCTAssertTrue(ksfu_munmap(NULL, 100));
}

- (void)testMmap_InvalidPath
{
    // mmap with non-existent path should return NULL
    NSString *invalidPath = @"/nonexistent/path/to/file.bin";
    void *ptr = ksfu_mmap(invalidPath.UTF8String, 100);
    XCTAssertTrue(ptr == NULL);
}

- (void)testMmap_Munmap_RoundTrip
{
    // Test mapping a file, writing to it, and unmapping
    NSString *path = [self generateTempFilePath];
    size_t size = 1024;

    void *ptr = ksfu_mmap(path.UTF8String, size);
    XCTAssertTrue(ptr != NULL);

    // Write some data to the mapped memory
    memset(ptr, 0xAB, size);

    // Verify the data was written
    uint8_t *bytes = (uint8_t *)ptr;
    XCTAssertEqual(bytes[0], 0xAB);
    XCTAssertEqual(bytes[size - 1], 0xAB);

    // Unmap should succeed
    XCTAssertTrue(ksfu_munmap(ptr, size));
}

- (void)testMmap_Munmap_MultipleRoundTrips
{
    // Test multiple map/unmap cycles to ensure no leaks or issues
    NSString *path = [self generateTempFilePath];
    size_t size = 256;

    for (int i = 0; i < 5; i++) {
        void *ptr = ksfu_mmap(path.UTF8String, size);
        XCTAssertTrue(ptr != NULL);

        // Write iteration number
        memset(ptr, (uint8_t)i, size);

        XCTAssertTrue(ksfu_munmap(ptr, size));
    }
}

- (void)testRemoveFileReportsErrno
{
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"removeme"];
    XCTAssertTrue([@"x" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);

    int err = -1;
    XCTAssertTrue(ksfu_removeFile(path.UTF8String, true, &err));
    XCTAssertEqual(err, 0);

    XCTAssertFalse(ksfu_removeFile(path.UTF8String, false, &err));
    XCTAssertEqual(err, ENOENT);

    // errnoOut is optional.
    XCTAssertFalse(ksfu_removeFile(path.UTF8String, false, NULL));
}

- (void)testSetDataProtectionOfAMissingPath
{
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"missing"];
#if TARGET_OS_IPHONE
    XCTAssertFalse(ksfu_setDataProtectionAtPath(path.UTF8String, KSFUDataProtectionNone));
#else
    // No data protection to set.
    XCTAssertTrue(ksfu_setDataProtectionAtPath(path.UTF8String, KSFUDataProtectionNone));
#endif
}

- (void)testGetDataProtectionOfABadDescriptor
{
#if TARGET_OS_IPHONE
    XCTAssertEqual(ksfu_getDataProtection(-1), KSFUDataProtectionUnknown);
#else
    // Always readable where there is no data protection.
    XCTAssertEqual(ksfu_getDataProtection(-1), KSFUDataProtectionNone);
#endif
}

- (void)testSetDataProtectionDoesNotFollowALink
{
    NSString *target = [self.tempPath stringByAppendingPathComponent:@"target"];
    XCTAssertTrue([@"x" writeToFile:target atomically:NO encoding:NSUTF8StringEncoding error:nil]);
    NSString *link = [self.tempPath stringByAppendingPathComponent:@"link"];
    XCTAssertEqual(symlink(target.UTF8String, link.UTF8String), 0);
#if TARGET_OS_IPHONE
    XCTAssertFalse(ksfu_setDataProtectionAtPath(link.UTF8String, KSFUDataProtectionNone),
                   @"the link's target is not this call's to change");
#else
    XCTAssertTrue(ksfu_setDataProtectionAtPath(link.UTF8String, KSFUDataProtectionNone));
#endif
}

- (void)testSetDataProtectionOfAFIFOReturns
{
    NSString *fifo = [self.tempPath stringByAppendingPathComponent:@"fifo"];
    XCTAssertEqual(mkfifo(fifo.UTF8String, 0600), 0);
    // Opening a FIFO for reading blocks until a writer opens it, unless the open does not block.
    // Reaching the next line is the test.
    ksfu_setDataProtectionAtPath(fifo.UTF8String, KSFUDataProtectionNone);
}

// Only a device keeps protection classes: the simulator and macOS accept the call and report the
// default class afterwards.
- (void)testSetDataProtectionReachesWhatIsCreatedInTheFolder
{
#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR && !TARGET_OS_MACCATALYST
    NSString *folder = [self.tempPath stringByAppendingPathComponent:@"unprotected"];
    XCTAssertTrue(ksfu_makePath(folder.UTF8String));
    XCTAssertTrue(ksfu_setDataProtectionAtPath(folder.UTF8String, KSFUDataProtectionNone));

    int folderFD = open(folder.UTF8String, O_RDONLY);
    XCTAssertEqual(ksfu_getDataProtection(folderFD), KSFUDataProtectionNone);
    close(folderFD);

    NSString *file = [folder stringByAppendingPathComponent:@"report.json"];
    int fileFD = open(file.UTF8String, O_RDWR | O_CREAT | O_EXCL, 0644);
    XCTAssertGreaterThanOrEqual(fileFD, 0);
    XCTAssertEqual(ksfu_getDataProtection(fileFD), KSFUDataProtectionNone, @"a new file takes its folder's class");
    XCTAssertTrue(ksfu_setDataProtection(fileFD, KSFUDataProtectionCompleteUntilFirstUserAuthentication));
    XCTAssertEqual(ksfu_getDataProtection(fileFD), KSFUDataProtectionCompleteUntilFirstUserAuthentication);
    close(fileFD);

    NSString *subfolder = [folder stringByAppendingPathComponent:@"Sidecars"];
    XCTAssertTrue(ksfu_makePath(subfolder.UTF8String));
    int subfolderFD = open(subfolder.UTF8String, O_RDONLY);
    XCTAssertEqual(ksfu_getDataProtection(subfolderFD), KSFUDataProtectionNone,
                   @"a new folder takes its folder's class");
    close(subfolderFD);
#else
    XCTSkip(@"Only a device keeps data protection classes");
#endif
}

@end
