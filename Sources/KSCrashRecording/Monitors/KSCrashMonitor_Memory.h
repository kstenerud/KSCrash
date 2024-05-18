//
//  KSCrashMonitor_Memory.h
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

#include "KSCrashMonitor.h"

#ifdef __cplusplus
extern "C" {
#endif

/** States of transition for the application */
enum {
    KSCrash_ApplicationTransitionStateStartup = 0,
    KSCrash_ApplicationTransitionStateStartupPrewarm,
    KSCrash_ApplicationTransitionStateLaunching,
    KSCrash_ApplicationTransitionStateForegrounding,
    KSCrash_ApplicationTransitionStateActive,
    KSCrash_ApplicationTransitionStateDeactivating,
    KSCrash_ApplicationTransitionStateBackground,
    KSCrash_ApplicationTransitionStateTerminating,
    KSCrash_ApplicationTransitionStateExiting,
};
typedef uint8_t KSCrash_ApplicationTransitionState;

/** Returns true if the transition state is user perceptible.
 */
bool ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionState state);

/**
 App Memory
 */
typedef struct KSCrash_Memory {
    
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
    KSCrash_ApplicationTransitionState state;
    
    /** padding for a nice 40 byte structure which is where most compilers will end up. */
    uint8_t pad[5];
} KSCrash_Memory;

/** Access the Monitor API.
 */
KSCrashMonitorAPI* kscm_memory_getAPI(void);

/** Initialize the memory monitor.
 *
 * @param installPath The install path of the KSCrash system.
 */
void ksmemory_initialize(const char* installPath);

/** Returns true if the previous session was terminated due to memory.
 */
bool ksmemory_previous_session_was_terminated_due_to_memory(bool *userPerceptible);

#ifdef __cplusplus
}
#endif

#endif // KSCrashMonitor_Memory_h
