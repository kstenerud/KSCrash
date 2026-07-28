//
//  CrashCallback.m
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#import "CrashCallback.h"
#import <errno.h>
#import <signal.h>
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

static void (^g_integrationTestSwiftAsyncTrigger)(void) = ^void(void) {
    printf("No Swift async crash trigger registered\n");
};

void integrationTestSwiftAsyncTrigger(void) { g_integrationTestSwiftAsyncTrigger(); }

void setIntegrationTestSwiftAsyncTrigger(void (^implementation)(void))
{
    g_integrationTestSwiftAsyncTrigger = implementation;
}

int integrationTestIgnoreSIGPIPE(void)
{
    struct sigaction action = { { 0 } };
    action.sa_handler = SIG_IGN;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGPIPE, &action, NULL) != 0) {
        return errno;
    }
    return 0;
}
