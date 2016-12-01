//
//  KSCrashInstallation+Alert.m
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

#import "KSCrashInstallation+Alert.h"
#import "KSCrash.h"
#import "KSCrashReportFilterAlert.h"

@implementation KSCrashInstallation (Alert)

- (void) addConditionalAlertWithTitle:(NSString*) title
                              message:(NSString*) message
                            yesAnswer:(NSString*) yesAnswer
                             noAnswer:(NSString*) noAnswer
{
    [self addPreFilter:[KSCrashReportFilterAlert filterWithTitle:title
                                                         message:message
                                                       yesAnswer:yesAnswer
                                                        noAnswer:noAnswer]];
    KSCrash* handler = [KSCrash sharedInstance];
    if(handler.deleteBehaviorAfterSendAll == KSCDeleteOnSucess)
    {
        // Better to delete always, or else the user will keep getting nagged
        // until he presses "yes"!
        handler.deleteBehaviorAfterSendAll = KSCDeleteAlways;
    }
}

- (void) addUnconditionalAlertWithTitle:(NSString*) title
                                message:(NSString*) message
                      dismissButtonText:(NSString*) dismissButtonText
{
    [self addPreFilter:[KSCrashReportFilterAlert filterWithTitle:title
                                                         message:message
                                                       yesAnswer:dismissButtonText
                                                        noAnswer:nil]];
}

@end
