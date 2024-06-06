//
//  KSCrashMonitor_BootTime.c
//
//
//  Created by Gleb Linnik on 04.06.2024.
//

#import "KSCrashMonitor_BootTime.h"

#import "KSCrashMonitorContext.h"
#import "KSSysCtl.h"
#import "KSDate.h"

#import <sys/types.h>
#import <Foundation/Foundation.h>

static volatile bool g_isEnabled = false;

/** Get a sysctl value as an NSDate.
 *
 * @param name The sysctl name.
 *
 * @return The result of the sysctl call.
 */
static const char* dateSysctl(const char* name)
{
    struct timeval value = kssysctl_timevalForName(name);
    char* buffer = malloc(21);
    ksdate_utcStringFromTimestamp(value.tv_sec, buffer);
    return buffer;
}

#pragma mark - API -

static const char* const name(void)
{
    return "KSCrashMonitorTypeBootTime";
}

static void setEnabled(bool isEnabled)
{
    if(isEnabled != g_isEnabled)
    {
        g_isEnabled = isEnabled;
    }
}

static bool isEnabled(void)
{
    return g_isEnabled;
}

static void addContextualInfoToEvent(KSCrash_MonitorContext* eventContext)
{
    if(g_isEnabled)
    {
        eventContext->System.bootTime = dateSysctl("kern.boottime");
    }
}

KSCrashMonitorAPI* kscm_boottime_getAPI(void)
{
    static KSCrashMonitorAPI api =
    {
        .name = name,
        .setEnabled = setEnabled,
        .isEnabled = isEnabled,
        .addContextualInfoToEvent = addContextualInfoToEvent
    };
    return &api;
}

#pragma mark - Injection -

__attribute__((constructor))
static void kscm_boottime_register(void)
{
    kscm_addMonitor(kscm_boottime_getAPI());
}
