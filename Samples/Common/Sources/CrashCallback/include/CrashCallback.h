//
//  CrashCallback.h
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#pragma once

#include "KSCrashExceptionHandlingPolicy.h"

#ifdef __cplusplus
extern "C" {
#endif

struct KSCrashReportWriter;
void integrationTestCrashNotifyCallback(KSCrash_ExceptionHandlingPolicy policy, const struct KSCrashReportWriter * _Nonnull writer);

void setIntegrationTestCrashNotifyImplementation(void (^ _Nonnull implementation)(KSCrash_ExceptionHandlingPolicy policy, const struct KSCrashReportWriter * _Nonnull writer));

#ifdef __cplusplus
}
#endif
