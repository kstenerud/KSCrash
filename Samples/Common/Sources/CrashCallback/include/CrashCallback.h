//
//  CrashCallback.h
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#pragma once

#include "KSCrashExceptionHandlingPlan.h"

#ifdef __cplusplus
extern "C" {
#endif

struct KSCrashReportWriter;

void integrationTestWillWriteReportCallback(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context);

void setIntegrationTestWillWriteReportCallback(void (^ _Nonnull implementation)(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context));


void integrationTestIsWritingReportCallback(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, const struct KSCrashReportWriter * _Nonnull writer);

void setIntegrationTestIsWritingReportCallback(void (^ _Nonnull implementation)(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, const struct KSCrashReportWriter * _Nonnull writer));


void integrationTestDidWriteReportCallback(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, int64_t reportID);

void setIntegrationTestDidWriteReportCallback(void (^ _Nonnull implementation)(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, int64_t reportID));

#ifdef __cplusplus
}
#endif
