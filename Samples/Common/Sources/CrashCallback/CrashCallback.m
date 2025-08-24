//
//  CrashCallback.m
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#import "CrashCallback.h"
#import <stdio.h>
#import "KSCrashC.h"

static void (^g_integrationTestReportWritingCallback)(const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer) =
^void (const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer) {
    // Do nothing by default
};

void integrationTestReportWritingCallback(const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer) {
    g_integrationTestReportWritingCallback(plan, writer);
}

void setIntegrationTestReportWritingImplementation(void (^implementation)(const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer)) {
    g_integrationTestReportWritingCallback = implementation;
}
