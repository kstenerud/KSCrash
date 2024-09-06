//
//  KSCrashInstallationConsole.m
//  KSCrash-iOS
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

#import "KSCrashInstallationConsole.h"
#import "KSCrashInstallation+Private.h"
#import "KSCrashReportFilterAppleFmt.h"
#import "KSCrashReportFilterBasic.h"
#import "KSCrashReportFilterJSON.h"
#import "KSCrashReportFilterStringify.h"
#import "KSCrashReportSinkConsole.h"

@implementation KSCrashInstallationConsole

+ (instancetype)sharedInstance
{
    static KSCrashInstallationConsole *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[KSCrashInstallationConsole alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    if ((self = [super initWithRequiredProperties:nil])) {
        _printAppleFormat = NO;
    }
    return self;
}

- (id<KSCrashReportFilter>)sink
{
    id<KSCrashReportFilter> formatFilter;
    if (self.printAppleFormat) {
        formatFilter = [[KSCrashReportFilterAppleFmt alloc] initWithReportStyle:KSAppleReportStyleSymbolicated];
    } else {
        formatFilter = [[KSCrashReportFilterPipeline alloc] initWithFilters:@[
            [[KSCrashReportFilterJSONEncode alloc] initWithOptions:KSJSONEncodeOptionPretty | KSJSONEncodeOptionSorted],
            [KSCrashReportFilterStringify new],
        ]];
    }

    return [[KSCrashReportFilterPipeline alloc] initWithFilters:@[ formatFilter, [KSCrashReportSinkConsole new] ]];
}

@end
