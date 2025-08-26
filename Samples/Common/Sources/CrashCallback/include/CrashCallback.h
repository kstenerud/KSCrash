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

void integrationTestEventNotifyCallback(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context);

void setIntegrationTestEventNotifyImplementation(void (^ _Nonnull implementation)(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context));


void integrationTestReportWritingCallback(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, const struct KSCrashReportWriter * _Nonnull writer);

void setIntegrationTestReportWritingImplementation(void (^ _Nonnull implementation)(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, const struct KSCrashReportWriter * _Nonnull writer));

#ifdef __cplusplus
}
#endif
