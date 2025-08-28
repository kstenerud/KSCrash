//
//  CrashCallback.m
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#import "CrashCallback.h"
#import <stdio.h>
#import "KSCrashC.h"

static void (^g_integrationTestWillWriteReportCallback)(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context) =
^void (KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context) {
    // Do nothing by default
};

void integrationTestWillWriteReportCallback(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context) {
    g_integrationTestWillWriteReportCallback(plan, context);
}

void setIntegrationTestWillWriteReportCallback(void (^ _Nonnull implementation)(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context)) {
    g_integrationTestWillWriteReportCallback = implementation;
}

static void (^g_integrationTestIsWritingReportCallback)(const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer) =
^void (const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer) {
    // Do nothing by default
};

void integrationTestIsWritingReportCallback(const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer) {
    g_integrationTestIsWritingReportCallback(plan, writer);
}

void setIntegrationTestIsWritingReportCallback(void (^implementation)(const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer)) {
    g_integrationTestIsWritingReportCallback = implementation;
}

static void (^g_integrationTestDidWriteReportCallback)(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, int64_t reportID) =
^void (const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, int64_t reportID) {
    // Do nothing by default
};

void integrationTestDidWriteReportCallback(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, int64_t reportID) {
    g_integrationTestDidWriteReportCallback(plan, reportID);
}

void setIntegrationTestDidWriteReportCallback(void (^ _Nonnull implementation)(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, int64_t reportID)) {
    g_integrationTestDidWriteReportCallback = implementation;
}
