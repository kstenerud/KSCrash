//
//  CrashCallback.m
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#import "CrashCallback.h"
#import <stdio.h>
#import "KSCrashC.h"

static void (^g_crashCallback)(const struct KSCrashReportWriter *writer) = ^void (const struct KSCrashReportWriter *writer) {
    // Do nothing by default
};

void crashNotifyCallback(const struct KSCrashReportWriter *writer) {
    g_crashCallback(writer);
}

void setCrashNotifyImplementation(void (^implementation)(const struct KSCrashReportWriter *writer)) {
    g_crashCallback = implementation;
}
