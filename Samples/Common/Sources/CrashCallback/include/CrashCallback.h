//
//  CrashCallback.h
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

struct KSCrashReportWriter;
void crashNotifyCallback(const struct KSCrashReportWriter *writer);

void setCrashNotifyImplementation(void (^implementation)(const struct KSCrashReportWriter *writer));

#ifdef __cplusplus
}
#endif
