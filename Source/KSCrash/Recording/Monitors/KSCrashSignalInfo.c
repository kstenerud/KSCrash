//
//  KSCrashMonitorInfo.c
//  Embrace
//
//  Created by Jonathon Copeland on 8/4/22.
//  Copyright © 2022 embrace.io. All rights reserved.
//

#include "KSCrashSignalInfo.h"
#include <stdlib.h>

void KSCrash_initSignalInfo(struct KSCrash_SignalInfo* info)
{
    info->functionPointer = 0;
    info->moduleName = NULL;
    info->modulePath = NULL;
    info->isEmbraceHandler = 0;
    info->next = NULL;
}

void KSCrash_freeSignalInfoList(struct KSCrash_SignalInfo* list)
{
    if(list->moduleName)
    {
        free(list->moduleName);
    }
    
    if(list->modulePath)
    {
        free(list->modulePath);
    }
    
    if(list->next)
    {
        KSCrash_freeSignalInfoList(list->next);
    }
    
    free(list);
}
