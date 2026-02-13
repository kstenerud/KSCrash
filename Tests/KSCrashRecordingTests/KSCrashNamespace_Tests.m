//
//  KSCrashNamespace_Tests.m
//
//  Created by Alexander Cohen on 2026-02-13.
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

#import "KSCrash+Namespace.h"
#import "KSCrashC.h"

#pragma mark - C API Tests

@interface KSCrashNamespaceC_Tests : XCTestCase
@end

@implementation KSCrashNamespaceC_Tests

- (void)testNamespaceIdentifierNotNull
{
    const char *identifier = kscrash_namespaceIdentifier();
    XCTAssertTrue(identifier != NULL);
}

- (void)testNamespaceIdentifierStartsWithKSCrash
{
    const char *identifier = kscrash_namespaceIdentifier();
    XCTAssertTrue(strncmp(identifier, "KSCrash", 7) == 0, @"Expected identifier to start with 'KSCrash', got '%s'",
                  identifier);
}

- (void)testNamespaceIdentifierIsStable
{
    const char *first = kscrash_namespaceIdentifier();
    const char *second = kscrash_namespaceIdentifier();
    XCTAssertEqual(first, second, @"Expected same pointer on repeated calls");
}

- (void)testDocumentsPathNotNull
{
    const char *path = kscrash_documentsPath();
    XCTAssertTrue(path != NULL);
}

- (void)testDocumentsPathContainsNamespace
{
    const char *path = kscrash_documentsPath();
    const char *identifier = kscrash_namespaceIdentifier();
    XCTAssertTrue(strstr(path, identifier) != NULL, @"Expected documents path '%s' to contain namespace '%s'", path,
                  identifier);
}

- (void)testDocumentsPathIsStable
{
    const char *first = kscrash_documentsPath();
    const char *second = kscrash_documentsPath();
    XCTAssertEqual(first, second, @"Expected same pointer on repeated calls");
}

- (void)testApplicationSupportPathNotNull
{
    const char *path = kscrash_applicationSupportPath();
    XCTAssertTrue(path != NULL);
}

- (void)testApplicationSupportPathContainsNamespace
{
    const char *path = kscrash_applicationSupportPath();
    const char *identifier = kscrash_namespaceIdentifier();
    XCTAssertTrue(strstr(path, identifier) != NULL, @"Expected application support path '%s' to contain namespace '%s'",
                  path, identifier);
}

- (void)testApplicationSupportPathIsStable
{
    const char *first = kscrash_applicationSupportPath();
    const char *second = kscrash_applicationSupportPath();
    XCTAssertEqual(first, second, @"Expected same pointer on repeated calls");
}

- (void)testCachesPathNotNull
{
    const char *path = kscrash_cachesPath();
    XCTAssertTrue(path != NULL);
}

- (void)testCachesPathContainsNamespace
{
    const char *path = kscrash_cachesPath();
    const char *identifier = kscrash_namespaceIdentifier();
    XCTAssertTrue(strstr(path, identifier) != NULL, @"Expected caches path '%s' to contain namespace '%s'", path,
                  identifier);
}

- (void)testCachesPathIsStable
{
    const char *first = kscrash_cachesPath();
    const char *second = kscrash_cachesPath();
    XCTAssertEqual(first, second, @"Expected same pointer on repeated calls");
}

- (void)testPathsAreDistinct
{
    const char *documents = kscrash_documentsPath();
    const char *appSupport = kscrash_applicationSupportPath();
    const char *caches = kscrash_cachesPath();

    XCTAssertTrue(strcmp(documents, appSupport) != 0, @"Documents and Application Support paths should differ");
    XCTAssertTrue(strcmp(documents, caches) != 0, @"Documents and Caches paths should differ");
    XCTAssertTrue(strcmp(appSupport, caches) != 0, @"Application Support and Caches paths should differ");
}

@end

#pragma mark - ObjC Category Tests

@interface KSCrashNamespaceObjC_Tests : XCTestCase
@end

@implementation KSCrashNamespaceObjC_Tests

- (void)testNamespaceIdentifier
{
    NSString *identifier = KSCrash.namespaceIdentifier;
    XCTAssertNotNil(identifier);
    XCTAssertTrue([identifier hasPrefix:@"KSCrash"], @"Expected identifier to start with 'KSCrash', got '%@'",
                  identifier);
}

- (void)testNamespaceIdentifierMatchesCFunction
{
    NSString *objcIdentifier = KSCrash.namespaceIdentifier;
    NSString *cIdentifier = @(kscrash_namespaceIdentifier());
    XCTAssertEqualObjects(objcIdentifier, cIdentifier);
}

- (void)testDocumentsURL
{
    NSURL *url = KSCrash.documentsURL;
    XCTAssertNotNil(url);
    XCTAssertTrue(url.isFileURL);
    XCTAssertTrue([url.path containsString:KSCrash.namespaceIdentifier],
                  @"Expected documents URL '%@' to contain namespace '%@'", url.path, KSCrash.namespaceIdentifier);
}

- (void)testDocumentsURLMatchesCFunction
{
    NSURL *url = KSCrash.documentsURL;
    NSString *cPath = @(kscrash_documentsPath());
    XCTAssertEqualObjects(url.path, cPath);
}

- (void)testApplicationSupportURL
{
    NSURL *url = KSCrash.applicationSupportURL;
    XCTAssertNotNil(url);
    XCTAssertTrue(url.isFileURL);
    XCTAssertTrue([url.path containsString:KSCrash.namespaceIdentifier],
                  @"Expected application support URL '%@' to contain namespace '%@'", url.path,
                  KSCrash.namespaceIdentifier);
}

- (void)testApplicationSupportURLMatchesCFunction
{
    NSURL *url = KSCrash.applicationSupportURL;
    NSString *cPath = @(kscrash_applicationSupportPath());
    XCTAssertEqualObjects(url.path, cPath);
}

- (void)testCachesURL
{
    NSURL *url = KSCrash.cachesURL;
    XCTAssertNotNil(url);
    XCTAssertTrue(url.isFileURL);
    XCTAssertTrue([url.path containsString:KSCrash.namespaceIdentifier],
                  @"Expected caches URL '%@' to contain namespace '%@'", url.path, KSCrash.namespaceIdentifier);
}

- (void)testCachesURLMatchesCFunction
{
    NSURL *url = KSCrash.cachesURL;
    NSString *cPath = @(kscrash_cachesPath());
    XCTAssertEqualObjects(url.path, cPath);
}

- (void)testURLsAreDistinct
{
    NSURL *documents = KSCrash.documentsURL;
    NSURL *appSupport = KSCrash.applicationSupportURL;
    NSURL *caches = KSCrash.cachesURL;

    XCTAssertNotEqualObjects(documents, appSupport);
    XCTAssertNotEqualObjects(documents, caches);
    XCTAssertNotEqualObjects(appSupport, caches);
}

@end
