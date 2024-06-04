//
//  KSCrashMonitor_BootTime.h
//  
//
//  Created by Gleb Linnik on 04.06.2024.
//

#ifndef KSCrashMonitor_BootTime_h
#define KSCrashMonitor_BootTime_h

#include "KSCrashMonitor.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Access the Monitor API.
 */
KSCrashMonitorAPI* kscm_boottime_getAPI(void);

#ifdef __cplusplus
}
#endif

#endif /* KSCrashMonitor_BootTime_h */
