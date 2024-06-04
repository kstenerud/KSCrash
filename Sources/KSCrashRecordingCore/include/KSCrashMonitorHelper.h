//
//  KSCrashMonitorHelper.h
//
//
//  Created by Gleb Linnik on 03.06.2024.
//

#ifndef KSCrashMonitorHelper_h
#define KSCrashMonitorHelper_h

#include "KSCrashMonitor.h"

#ifdef __cplusplus
extern "C" {
#endif

static inline void kscm_setMonitorEnabled(KSCrashMonitorAPI* api, bool isEnabled)
{
    if (api != NULL && api->setEnabled != NULL)
    {
        api->setEnabled(isEnabled);
    }
}

static inline bool kscm_isMonitorEnabled(KSCrashMonitorAPI* api)
{
    if (api != NULL && api->isEnabled != NULL)
    {
        return api->isEnabled();
    }
    return false;
}

static inline const char* kscm_getMonitorName(KSCrashMonitorAPI* api)
{
    if (api != NULL && api->name != NULL)
    {
        return api->name();
    }
    return NULL;
}

static inline KSCrashMonitorProperty kscm_getMonitorProperties(KSCrashMonitorAPI* api)
{
    if (api != NULL && api->properties != NULL)
    {
        return api->properties();
    }
    return KSCrashMonitorPropertyNone;
}

static inline void kscm_addContextualInfoToEvent(KSCrashMonitorAPI* api, struct KSCrash_MonitorContext* eventContext)
{
    if (api != NULL && api->addContextualInfoToEvent != NULL)
    {
        api->addContextualInfoToEvent(eventContext);
    }
}

static inline void kscm_notifyPostSystemEnable(KSCrashMonitorAPI* api)
{
    if (api != NULL && api->notifyPostSystemEnable != NULL)
    {
        api->notifyPostSystemEnable();
    }
}

#ifdef __cplusplus
}
#endif

#endif /* KSCrashMonitorHelper_h */
