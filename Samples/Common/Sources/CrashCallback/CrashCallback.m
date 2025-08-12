//
//  CrashCallback.m
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#import "CrashCallback.h"
#import <stdio.h>
#import "KSCrashC.h"

static void (^g_integrationTestCrashCallback)(KSCrash_ExceptionHandlingPolicy policy, const struct KSCrashReportWriter * _Nonnull writer) =
^void (KSCrash_ExceptionHandlingPolicy policy, const struct KSCrashReportWriter * _Nonnull writer) {
    // Do nothing by default
};

void integrationTestCrashNotifyCallback(KSCrash_ExceptionHandlingPolicy policy, const struct KSCrashReportWriter * _Nonnull writer) {
    g_integrationTestCrashCallback(policy, writer);
}

void setIntegrationTestCrashNotifyImplementation(void (^implementation)(KSCrash_ExceptionHandlingPolicy policy, const struct KSCrashReportWriter * _Nonnull writer)) {
    g_integrationTestCrashCallback = implementation;
}
