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
#import "KSCrashReportSinkConsole.h"
#import "KSCrashReportFilterAppleFmt.h"
#import "KSCrashReportFilterJSON.h"
#import "KSCrashReportFilterStringify.h"
#import "KSSingleton.h"

@implementation KSCrashInstallationConsole

IMPLEMENT_EXCLUSIVE_SHARED_INSTANCE(KSCrashInstallationConsole)

@synthesize printAppleFormat = _printAppleFormat;

- (id) init
{
    if((self = [super initWithRequiredProperties:nil]))
    {
        self.printAppleFormat = NO;
    }
    return self;
}

- (id<KSCrashReportFilter>) sink
{
    id<KSCrashReportFilter> formatFilter;
    if(self.printAppleFormat)
    {
        formatFilter = [KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicated];
    }
    else
    {
        formatFilter = [KSCrashReportFilterPipeline filterWithFilters:
                        [KSCrashReportFilterJSONEncode filterWithOptions:KSJSONEncodeOptionPretty | KSJSONEncodeOptionSorted],
                        [KSCrashReportFilterStringify new],
                        nil];
    }

    return [KSCrashReportFilterPipeline filterWithFilters:
            formatFilter,
            [KSCrashReportSinkConsole new],
            nil];
}

@end
