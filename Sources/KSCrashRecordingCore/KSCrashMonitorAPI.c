//
//  KSCrashMonitorAPI.c
//  KSCrash
//
//  Created by Karl Stenerud on 19.07.25.
//

#include "KSCrashMonitorAPI.h"

static void default_init(__unused KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context) {}
static KSCrashMonitorFlag default_monitorFlags(__unused void *context) { return 0; }
static const char *default_monitorId(__unused void *context) { return "unset"; }
static void default_setEnabled(__unused bool isEnabled, __unused void *context) {}
static bool default_isEnabled(__unused void *context) { return false; }
static void default_addContextualInfoToEvent(__unused struct KSCrash_MonitorContext *eventContext,
                                             __unused void *context)
{
}
static void default_notifyPostSystemEnable(__unused void *context) {}
static KSCrashMonitorAPI g_defaultAPI = {
    .context = NULL,
    .init = default_init,
    .monitorId = default_monitorId,
    .monitorFlags = default_monitorFlags,
    .setEnabled = default_setEnabled,
    .isEnabled = default_isEnabled,
    .addContextualInfoToEvent = default_addContextualInfoToEvent,
    .notifyPostSystemEnable = default_notifyPostSystemEnable,
};

bool kscma_initAPI(KSCrashMonitorAPI *api)
{
    if (api != NULL && api->init == NULL) {
        *api = g_defaultAPI;
        return true;
    }
    return false;
}
