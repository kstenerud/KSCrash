//
//  CrashCallback.m
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#import "CrashCallback.h"
#import <stdio.h>
#import "KSCrashC.h"

static void (^g_integrationTestEventNotifyCallback)(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context) =
^void (KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context) {
    // Do nothing by default
};

void integrationTestEventNotifyCallback(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context) {
    g_integrationTestEventNotifyCallback(plan, context);
}

void setIntegrationTestEventNotifyImplementation(void (^ _Nonnull implementation)(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context)) {
    g_integrationTestEventNotifyCallback = implementation;
}

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
