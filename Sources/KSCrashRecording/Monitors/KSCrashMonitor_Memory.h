//
//  KSCrashMonitor_Memory.h
//
//  Created by Alexander Cohen on 2024-05-20.
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

/* Monitor memory and records data for OOMs.
 */

#ifndef KSCrashMonitor_Memory_h
#define KSCrashMonitor_Memory_h

#include "KSCrashAppTransitionState.h"
#include "KSCrashMonitor.h"

#ifdef __cplusplus
extern "C" {
#endif

extern const uint8_t KSCrash_Memory_Version_1_0;
extern const uint8_t KSCrash_Memory_CurrentVersion;

/** Non-Fatal report level where we don't report at all */
extern const uint8_t KSCrash_Memory_NonFatalReportLevelNone;

/**
 App Memory
 */
typedef struct KSCrash_Memory {
    /** magic header */
    int32_t magic;

    /** current version of the struct */
    int8_t version;

    /** timestamp in microseconds */
    int64_t timestamp;

    /** amount of app memory used */
    uint64_t footprint;

    /** amount of app memory remaining */
    uint64_t remaining;

    /** high water mark for footprint (footprint +  remaining)*/
    uint64_t limit;

    /** memory pressure  `KSCrashAppMemoryPressure` */
    uint8_t pressure;

    /** memory level  `KSCrashAppMemoryLevel` (KSCrashAppMemory.level) */
    uint8_t level;

    /** transition state of the app */
    KSCrashAppTransitionState state;

    /** The process for this data had a fatal exception/event of some type */
    bool fatal;

} KSCrash_Memory;

/** Access the Monitor API.
 */
KSCrashMonitorAPI *kscm_memory_getAPI(void);

/** Initialize the memory monitor.
 *
 * @param dataPath The data path of the KSCrash system.
 */
void ksmemory_initialize(const char *dataPath);

/** Returns true if the previous session was terminated due to memory.
 *
 * @param userPerceptible Set to true if the termination was visible
 * to the user or if they might have perceived it in any way (ie: app was active, or
 * during some sort of transition from background to active). Can be NULL.
 */
bool ksmemory_previous_session_was_terminated_due_to_memory(bool *userPerceptible);

/** Sets the minimum level at which to report non-fatals.
 *
 * @param level Minimum level at which we report non-fatals.
 *
 * @notes Default to no reporting. Use _KSCrash_Memory_NonFatalReportLevelNone_
 * to turn this feature off. Use any value in `KSCrashAppMemoryState` as a level.
 */
void ksmemory_set_nonfatal_report_level(uint8_t level);

/** Returns the minimum level at which memory non-fatals are reported.
 */
uint8_t ksmemory_get_nonfatal_report_level(void);

/** Enables or disables sending reports for memory terminations.
 *  Default to true.
 *
 * @param enabled if true, reports will be sent.
 */
void ksmemory_set_fatal_reports_enabled(bool enabled);

/** Returns true if fatal reports are enabled.
 */
bool ksmemory_get_fatal_reports_enabled(void);

#ifdef __cplusplus
}
#endif

#endif  // KSCrashMonitor_Memory_h
