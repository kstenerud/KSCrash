//
//  KSCrashHostKind_Tests.m
//
//  Created by Alexander Cohen on 2026-11-21.
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

#import "KSCrashHostKind.h"

@interface KSCrashHostKind_Tests : XCTestCase
@end

@implementation KSCrashHostKind_Tests

- (void)testAppExecutable
{
    XCTAssertEqual(kshostkind_forExecutablePath("/private/var/containers/Bundle/Application/X/MyApp.app/MyApp"),
                   KSCrashHostKindApp);
    XCTAssertEqual(kshostkind_forExecutablePath("/Applications/MyApp.app/Contents/MacOS/MyApp"), KSCrashHostKindApp);
}

- (void)testExtensionExecutable
{
    XCTAssertEqual(kshostkind_forExecutablePath("/private/var/containers/Bundle/Application/X/MyApp.app/PlugIns/"
                                                "MyExt.appex/MyExt"),
                   KSCrashHostKindExtension);
    XCTAssertEqual(
        kshostkind_forExecutablePath("/Applications/MyApp.app/Contents/PlugIns/MyExt.appex/Contents/MacOS/MyExt"),
        KSCrashHostKindExtension);
}

- (void)testBundleExtensionIgnoresCase
{
    XCTAssertEqual(kshostkind_forExecutablePath("/tmp/MyApp.APP/MyApp"), KSCrashHostKindApp);
    XCTAssertEqual(kshostkind_forExecutablePath("/tmp/MyExt.AppEx/MyExt"), KSCrashHostKindExtension);
}

- (void)testTestBundleExecutable
{
    XCTAssertEqual(kshostkind_forExecutablePath("/tmp/MyTests.xctest/MyTests"), KSCrashHostKindXCTest);
}

- (void)testExecutablesThatAreNoBundlesMainExecutable
{
    // A helper tool inside an app is not the app's main executable.
    XCTAssertEqual(kshostkind_forExecutablePath("/Applications/MyApp.app/Contents/Helpers/tool"), KSCrashHostKindOther);
    XCTAssertEqual(kshostkind_forExecutablePath("/Applications/Xcode.app/Contents/Developer/usr/bin/xctest"),
                   KSCrashHostKindOther);
    XCTAssertEqual(kshostkind_forExecutablePath("/usr/local/bin/tool"), KSCrashHostKindOther);
    XCTAssertEqual(kshostkind_forExecutablePath("tool"), KSCrashHostKindOther);
    XCTAssertEqual(kshostkind_forExecutablePath(""), KSCrashHostKindOther);
}

// NSBundle's main bundle is the reference the path rule has to agree with.
- (void)testCurrentMatchesTheMainBundle
{
    NSString *extension = NSBundle.mainBundle.bundlePath.pathExtension.lowercaseString;
    KSCrashHostKind expected = KSCrashHostKindOther;
    if ([extension isEqualToString:@"app"]) {
        expected = KSCrashHostKindApp;
    } else if ([extension isEqualToString:@"appex"]) {
        expected = KSCrashHostKindExtension;
    } else if ([extension isEqualToString:@"xctest"]) {
        expected = KSCrashHostKindXCTest;
    }
    XCTAssertEqual(kshostkind_current(), expected);
}

@end
