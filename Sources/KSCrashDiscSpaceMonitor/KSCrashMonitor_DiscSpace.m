//
//  KSCrashMonitor_DiscSpace.c
//  
//
//  Created by Gleb Linnik on 04.06.2024.
//

#import "KSCrashMonitor_DiscSpace.h"

#import <Foundation/Foundation.h>

static volatile bool g_isEnabled = false;

static uint64_t getStorageSize(void)
{
    NSNumber *storageSize = [[[NSFileManager defaultManager]
                              attributesOfFileSystemForPath:NSHomeDirectory()
                              error:nil]
                             objectForKey:NSFileSystemSize];
    return storageSize.unsignedLongLongValue;
}

#pragma mark - API -

static const char* const name()
{
    return "KSCrashMonitorTypeDiscSpace";
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
        eventContext->System.storageSize = getStorageSize();
    }
}

KSCrashMonitorAPI* kscm_discspace_getAPI(void)
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
static void kscm_discspace_register(void)
{
    kscm_addMonitor(kscm_discspace_getAPI());
}
