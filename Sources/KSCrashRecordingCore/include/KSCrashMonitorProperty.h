//
//  KSCrashMonitorProperty.h
//
//
//  Created by Gleb Linnik on 29.05.2024.
//

#ifndef KSCrashMonitorProperty_h
#define KSCrashMonitorProperty_h

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    /** Indicates that no properties are set. */
    KSCrashMonitorPropertyNone = 0,

    /** Indicates that the program cannot continue execution if a monitor with this property is triggered. */
    KSCrashMonitorPropertyFatal = 1 << 0,

    /** Indicates that the monitor with this property will not be enabled if a debugger is attached. */
    KSCrashMonitorPropertyDebuggerUnsafe = 1 << 1,

    /** Indicates that the monitor is safe to be used in an asynchronous environment.
     * Monitors without this property are considered unsafe for asynchronous operations by default. */
    KSCrashMonitorPropertyAsyncSafe = 1 << 2,

} KSCrashMonitorProperty;

#ifdef __cplusplus
}
#endif

#endif /* KSCrashMonitorProperty_h */
