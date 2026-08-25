//
//  CrashCallback.h
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#pragma once

#include <stdint.h>

#include "KSCrashExceptionHandlingPlan.h"

#ifdef __cplusplus
extern "C" {
#endif

struct KSCrashReportWriter;

void integrationTestWillWriteReportCallback(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context);

void setIntegrationTestWillWriteReportCallback(void (^ _Nonnull implementation)(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context));


void integrationTestIsWritingReportCallback(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, const struct KSCrashReportWriter * _Nonnull writer);

void setIntegrationTestIsWritingReportCallback(void (^ _Nonnull implementation)(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, const struct KSCrashReportWriter * _Nonnull writer));


void integrationTestDidWriteReportCallback(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, const char *_Nonnull reportID);

void setIntegrationTestDidWriteReportCallback(void (^ _Nonnull implementation)(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, const char *_Nonnull reportID));

int integrationTestIgnoreSIGPIPE(void);

typedef struct {
    int32_t signalNumber;
    int32_t signalCode;
    uint64_t instructionAddress;
    uint64_t faultAddress;
} IntegrationTestSignalMarker;

/**
 * Installs a SIGSEGV handler after KSCrash that writes the received signal context
 * to markerPath and then forwards the signal to the handler it replaced.
 */
int integrationTestInstallPostKSCrashSIGSEGVHandler(const char *_Nonnull markerPath);

/** Runs the Swift async crash trigger. Swift async code cannot live in the Objective-C
 * CrashTriggers target, so Swift registers the implementation here at startup.
 */
void integrationTestSwiftAsyncTrigger(void);

void setIntegrationTestSwiftAsyncTrigger(void (^_Nonnull implementation)(void));

#ifdef __cplusplus
}
#endif
