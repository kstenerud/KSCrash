//
//  KSThread_Main.h
//  KSCrash-iOS
//
//  Created by Golder on 2019/4/16.
//  Copyright © 2019 Karl Stenerud. All rights reserved.
//

#ifndef KSThread_Main_h
#define KSThread_Main_h


#ifdef __cplusplus
extern "C" {
#endif


#include "KSThread.h"

/*  Get main thread ID.
 *  Sometimes you need know which mach ID is main thread. Example: You maybe only care about
 *  callstack of main thread and callstack of crashed thread when report a crash.
 *
 *  @return main thread mach ID
 */
KSThread ksthread_main(void);
    
    
#ifdef __cplusplus
}
#endif

#endif /* KSThread_Main_h */
