//
//  KSCrashMonitorAPI.c
//  KSCrash
//
//  Created by Karl Stenerud on 19.07.25.
//

#include "KSCrashMonitorAPI.h"

static void default_init(__unused KSCrash_ExceptionHandlerCallbacks *callbacks) {}
static KSCrashMonitorFlag default_monitorFlags(void) { return 0; }
static const char *default_monitorId(void) { return "unset"; }
static void default_setEnabled(__unused bool isEnabled) {}
static bool default_isEnabled(void) { return false; }
static void default_addContextualInfoToEvent(__unused struct KSCrash_MonitorContext *eventContext) {}
static void default_notifyPostSystemEnable(void) {}
static KSCrashMonitorAPI g_defaultAPI = {
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
