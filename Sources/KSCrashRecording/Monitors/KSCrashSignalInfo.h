//
//  KSCrashMonitorInfo.h
//  Embrace
//
//  Created by Jonathon Copeland on 8/4/22.
//  Copyright © 2022 embrace.io. All rights reserved.
//

#ifndef KSCrashMonitorInfo_h
#define KSCrashMonitorInfo_h

#include <stdio.h>

struct KSCrash_SignalInfo
{
    uintptr_t functionPointer;
    char* moduleName;
    char* modulePath;
    short isEmbraceHandler;
    
    struct KSCrash_SignalInfo* next;
};

void KSCrash_initSignalInfo(struct KSCrash_SignalInfo* info);
void KSCrash_freeSignalInfoList(struct KSCrash_SignalInfo* list);

#endif /* KSCrashMonitorInfo_h */
