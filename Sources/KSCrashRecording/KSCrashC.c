//
//  KSCrashC.c
//
//  Created by Karl Stenerud on 2012-01-28.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#include "KSCrashC.h"

#include "KSCrashCachedData.h"
#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorType.h"
#include "KSCrashMonitor_AppState.h"
#include "KSCrashMonitor_CPPException.h"
#include "KSCrashMonitor_Deadlock.h"
#include "KSCrashMonitor_MachException.h"
#include "KSCrashMonitor_Memory.h"
#include "KSCrashMonitor_NSException.h"
#include "KSCrashMonitor_Signal.h"
#include "KSCrashMonitor_System.h"
#include "KSCrashMonitor_User.h"
#include "KSCrashMonitor_Zombie.h"
#include "KSCrashReportC.h"
#include "KSCrashReportFixer.h"
#include "KSCrashReportStoreC+Private.h"
#include "KSFileUtils.h"
#include "KSObjC.h"
#include "KSString.h"
#include "KSSystemCapabilities.h"

// #define KSLogger_LocalLevel TRACE
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "KSLogger.h"

#define KSC_MAX_APP_NAME_LENGTH 100

typedef enum {
    KSApplicationStateNone,
    KSApplicationStateDidBecomeActive,
    KSApplicationStateWillResignActiveActive,
    KSApplicationStateDidEnterBackground,
    KSApplicationStateWillEnterForeground,
    KSApplicationStateWillTerminate
} KSApplicationState;

static const struct KSCrashMonitorMapping {
    KSCrashMonitorType type;
    KSCrashMonitorAPI *(*getAPI)(void);
} g_monitorMappings[] = { { KSCrashMonitorTypeMachException, kscm_machexception_getAPI },
                          { KSCrashMonitorTypeSignal, kscm_signal_getAPI },
                          { KSCrashMonitorTypeCPPException, kscm_cppexception_getAPI },
                          { KSCrashMonitorTypeNSException, kscm_nsexception_getAPI },
                          { KSCrashMonitorTypeMainThreadDeadlock, kscm_deadlock_getAPI },
                          { KSCrashMonitorTypeUserReported, kscm_user_getAPI },
                          { KSCrashMonitorTypeSystem, kscm_system_getAPI },
                          { KSCrashMonitorTypeApplicationState, kscm_appstate_getAPI },
                          { KSCrashMonitorTypeZombie, kscm_zombie_getAPI },
                          { KSCrashMonitorTypeMemoryTermination, kscm_memory_getAPI } };

static const size_t g_monitorMappingCount = sizeof(g_monitorMappings) / sizeof(g_monitorMappings[0]);

// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** True if KSCrash has been installed. */
static volatile bool g_installed = 0;

static bool g_shouldAddConsoleLogToReport = false;
static bool g_shouldPrintPreviousLog = false;
static char g_consoleLogPath[KSFU_MAX_PATH_LENGTH];
static KSCrashMonitorType g_monitoring = KSCrashMonitorTypeProductionSafeMinimal;
static char g_lastCrashReportFilePath[KSFU_MAX_PATH_LENGTH];
static KSCrashReportStoreCConfiguration g_reportStoreConfig;
static KSReportWrittenCallback g_reportWrittenCallback;
static KSApplicationState g_lastApplicationState = KSApplicationStateNone;

// ============================================================================
#pragma mark - Utility -
// ============================================================================

static void printPreviousLog(const char *filePath)
{
    char *data;
    int length;
    if (ksfu_readEntireFile(filePath, &data, &length, 0)) {
        printf("\nvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv Previous Log vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv\n\n");
        printf("%s\n", data);
        free(data);
        printf("^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n\n");
        fflush(stdout);
    }
}

static void notifyOfBeforeInstallationState(void)
{
    KSLOG_DEBUG("Notifying of pre-installation state");
    switch (g_lastApplicationState) {
        case KSApplicationStateDidBecomeActive:
            return kscrash_notifyAppActive(true);
        case KSApplicationStateWillResignActiveActive:
            return kscrash_notifyAppActive(false);
        case KSApplicationStateDidEnterBackground:
            return kscrash_notifyAppInForeground(false);
        case KSApplicationStateWillEnterForeground:
            return kscrash_notifyAppInForeground(true);
        case KSApplicationStateWillTerminate:
            return kscrash_notifyAppTerminate();
        default:
            return;
    }
}

// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

/** Called when a crash occurs.
 *
 * This function gets passed as a callback to a crash handler.
 */
static void onCrash(struct KSCrash_MonitorContext *monitorContext)
{
    if (monitorContext->currentSnapshotUserReported == false) {
        KSLOG_DEBUG("Updating application state to note crash.");
        kscrashstate_notifyAppCrash();
    }
    monitorContext->consoleLogPath = g_shouldAddConsoleLogToReport ? g_consoleLogPath : NULL;

    if (monitorContext->crashedDuringCrashHandling) {
        kscrashreport_writeRecrashReport(monitorContext, g_lastCrashReportFilePath);
    } else if (monitorContext->reportPath) {
        kscrashreport_writeStandardReport(monitorContext, monitorContext->reportPath);
    } else {
        char crashReportFilePath[KSFU_MAX_PATH_LENGTH];
        int64_t reportID = kscrs_getNextCrashReport(crashReportFilePath, &g_reportStoreConfig);
        strncpy(g_lastCrashReportFilePath, crashReportFilePath, sizeof(g_lastCrashReportFilePath));
        kscrashreport_writeStandardReport(monitorContext, crashReportFilePath);

        if (g_reportWrittenCallback) {
            g_reportWrittenCallback(reportID);
        }
    }
}

static void setMonitors(KSCrashMonitorType monitorTypes)
{
    g_monitoring = monitorTypes;

    for (size_t i = 0; i < g_monitorMappingCount; i++) {
        KSCrashMonitorAPI *api = g_monitorMappings[i].getAPI();
        if (api != NULL) {
            if (monitorTypes & g_monitorMappings[i].type) {
                kscm_addMonitor(api);
            } else {
                kscm_removeMonitor(api);
            }
        }
    }
}

void handleConfiguration(KSCrashCConfiguration *configuration)
{
    g_reportStoreConfig = KSCrashReportStoreCConfiguration_Copy(&configuration->reportStoreConfiguration);

    if (configuration->userInfoJSON != NULL) {
        kscrashreport_setUserInfoJSON(configuration->userInfoJSON);
    }
#if KSCRASH_HAS_OBJC
    kscm_setDeadlockHandlerWatchdogInterval(configuration->deadlockWatchdogInterval);
#endif
    ksccd_setSearchQueueNames(configuration->enableQueueNameSearch);
    kscrashreport_setIntrospectMemory(configuration->enableMemoryIntrospection);

    if (configuration->doNotIntrospectClasses.strings != NULL) {
        kscrashreport_setDoNotIntrospectClasses(configuration->doNotIntrospectClasses.strings,
                                                configuration->doNotIntrospectClasses.length);
    }

    kscrashreport_setUserSectionWriteCallback(configuration->crashNotifyCallback);
    g_reportWrittenCallback = configuration->reportWrittenCallback;
    g_shouldAddConsoleLogToReport = configuration->addConsoleLogToReport;
    g_shouldPrintPreviousLog = configuration->printPreviousLogOnStartup;

    if (configuration->enableSwapCxaThrow) {
        kscm_enableSwapCxaThrow();
    }
}
// ============================================================================
#pragma mark - API -
// ============================================================================

KSCrashInstallErrorCode kscrash_install(const char *appName, const char *const installPath,
                                        KSCrashCConfiguration *configuration)
{
    KSLOG_DEBUG("Installing crash reporter.");

    if (g_installed) {
        KSLOG_DEBUG("Crash reporter already installed.");
        return KSCrashInstallErrorAlreadyInstalled;
    }

    if (appName == NULL || installPath == NULL) {
        KSLOG_ERROR("Invalid parameters: appName or installPath is NULL.");
        return KSCrashInstallErrorInvalidParameter;
    }

    handleConfiguration(configuration);

    if (g_reportStoreConfig.appName == NULL) {
        g_reportStoreConfig.appName = strdup(appName);
    }

    char path[KSFU_MAX_PATH_LENGTH];
    if (g_reportStoreConfig.reportsPath == NULL) {
        if (snprintf(path, sizeof(path), "%s/" KSCRS_DEFAULT_REPORTS_FOLDER, installPath) >= (int)sizeof(path)) {
            KSLOG_ERROR("Reports path is too long.");
            return KSCrashInstallErrorPathTooLong;
        }
        g_reportStoreConfig.reportsPath = strdup(path);
    }

    kscrs_initialize(&g_reportStoreConfig);

    if (snprintf(path, sizeof(path), "%s/Data", installPath) >= (int)sizeof(path)) {
        KSLOG_ERROR("Data path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    if (ksfu_makePath(path) == false) {
        KSLOG_ERROR("Could not create path: %s", path);
        return KSCrashInstallErrorCouldNotCreatePath;
    }
    ksmemory_initialize(path);

    if (snprintf(path, sizeof(path), "%s/Data/CrashState.json", installPath) >= (int)sizeof(path)) {
        KSLOG_ERROR("Crash state path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    kscrashstate_initialize(path);

    if (snprintf(g_consoleLogPath, sizeof(g_consoleLogPath), "%s/Data/ConsoleLog.txt", installPath) >=
        (int)sizeof(g_consoleLogPath)) {
        KSLOG_ERROR("Console log path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    if (g_shouldPrintPreviousLog) {
        printPreviousLog(g_consoleLogPath);
    }
    kslog_setLogFilename(g_consoleLogPath, true);

    ksccd_init(60);

    kscm_setEventCallback(onCrash);
    setMonitors(configuration->monitors);
    if (kscm_activateMonitors() == false) {
        KSLOG_ERROR("No crash monitors are active");
        return KSCrashInstallErrorNoActiveMonitors;
    }

    g_installed = true;
    KSLOG_DEBUG("Installation complete.");

    notifyOfBeforeInstallationState();
    return KSCrashInstallErrorNone;
}

void kscrash_setUserInfoJSON(const char *const userInfoJSON) { kscrashreport_setUserInfoJSON(userInfoJSON); }

const char *kscrash_getUserInfoJSON(void) { return kscrashreport_getUserInfoJSON(); }

void kscrash_reportUserException(const char *name, const char *reason, const char *language, const char *lineOfCode,
                                 const char *stackTrace, bool logAllThreads, bool terminateProgram)
{
    kscm_reportUserException(name, reason, language, lineOfCode, stackTrace, logAllThreads, terminateProgram);
    if (g_shouldAddConsoleLogToReport) {
        kslog_clearLogFile();
    }
}

void kscrash_notifyObjCLoad(void) { kscrashstate_notifyObjCLoad(); }

void kscrash_notifyAppActive(bool isActive)
{
    if (g_installed) {
        kscrashstate_notifyAppActive(isActive);
    }
    g_lastApplicationState = isActive ? KSApplicationStateDidBecomeActive : KSApplicationStateWillResignActiveActive;
}

void kscrash_notifyAppInForeground(bool isInForeground)
{
    if (g_installed) {
        kscrashstate_notifyAppInForeground(isInForeground);
    }
    g_lastApplicationState =
        isInForeground ? KSApplicationStateWillEnterForeground : KSApplicationStateDidEnterBackground;
}

void kscrash_notifyAppTerminate(void)
{
    if (g_installed) {
        kscrashstate_notifyAppTerminate();
    }
    g_lastApplicationState = KSApplicationStateWillTerminate;
}

void kscrash_notifyAppCrash(void) { kscrashstate_notifyAppCrash(); }

int64_t kscrash_addUserReport(const char *report, int reportLength)
{
    return kscrs_addUserReport(report, reportLength, &g_reportStoreConfig);
}
