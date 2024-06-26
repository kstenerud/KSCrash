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
#include "KSCrashReportStore.h"
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
        int64_t reportID = kscrs_getNextCrashReport(crashReportFilePath);
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

    if (g_installed) {
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
}

void handleConfiguration(KSCrashCConfiguration *configuration)
{
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
    kscrs_setMaxReportCount(configuration->maxReportCount);

    if (configuration->enableSwapCxaThrow) {
        kscm_enableSwapCxaThrow();
    }
}
// ============================================================================
#pragma mark - API -
// ============================================================================

void kscrash_install(const char *appName, const char *const installPath, KSCrashCConfiguration configuration)
{
    KSLOG_DEBUG("Installing crash reporter.");

    if (g_installed) {
        KSLOG_DEBUG("Crash reporter already installed.");
        return;
    }
    g_installed = 1;

    handleConfiguration(&configuration);

    char path[KSFU_MAX_PATH_LENGTH];
    snprintf(path, sizeof(path), "%s/Reports", installPath);
    ksfu_makePath(path);
    kscrs_initialize(appName, installPath, path);

    snprintf(path, sizeof(path), "%s/Data", installPath);
    ksfu_makePath(path);
    ksmemory_initialize(path);

    snprintf(path, sizeof(path), "%s/Data/CrashState.json", installPath);
    kscrashstate_initialize(path);

    snprintf(g_consoleLogPath, sizeof(g_consoleLogPath), "%s/Data/ConsoleLog.txt", installPath);
    if (g_shouldPrintPreviousLog) {
        printPreviousLog(g_consoleLogPath);
    }
    kslog_setLogFilename(g_consoleLogPath, true);

    ksccd_init(60);

    kscm_setEventCallback(onCrash);
    setMonitors(configuration.monitors);
    kscm_activateMonitors();

    KSLOG_DEBUG("Installation complete.");

    notifyOfBeforeInstallationState();
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

int kscrash_getReportCount(void) { return kscrs_getReportCount(); }

int kscrash_getReportIDs(int64_t *reportIDs, int count) { return kscrs_getReportIDs(reportIDs, count); }

char *kscrash_readReportAtPath(const char *path)
{
    if (!path) {
        return NULL;
    }

    char *rawReport = kscrs_readReportAtPath(path);
    if (rawReport == NULL) {
        return NULL;
    }

    char *fixedReport = kscrf_fixupCrashReport(rawReport);

    free(rawReport);
    return fixedReport;
}

char *kscrash_readReport(int64_t reportID)
{
    if (reportID <= 0) {
        KSLOG_ERROR("Report ID was %" PRIx64, reportID);
        return NULL;
    }

    char *rawReport = kscrs_readReport(reportID);
    if (rawReport == NULL) {
        KSLOG_ERROR("Failed to load report ID %" PRIx64, reportID);
        return NULL;
    }

    char *fixedReport = kscrf_fixupCrashReport(rawReport);
    if (fixedReport == NULL) {
        KSLOG_ERROR("Failed to fixup report ID %" PRIx64, reportID);
    }

    free(rawReport);
    return fixedReport;
}

int64_t kscrash_addUserReport(const char *report, int reportLength)
{
    return kscrs_addUserReport(report, reportLength);
}

void kscrash_deleteAllReports(void) { kscrs_deleteAllReports(); }

void kscrash_deleteReportWithID(int64_t reportID) { kscrs_deleteReportWithID(reportID); }
