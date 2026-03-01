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

#include "KSBinaryImageCache.h"
#include "KSCompilerDefines.h"
#include "KSCrashExceptionHandlingPlan+Private.h"
#include "KSCrashMonitor.h"
#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorType.h"
#include "KSCrashMonitor_CPPException.h"
#include "KSCrashMonitor_Deadlock.h"
#include "KSCrashMonitor_Lifecycle.h"
#include "KSCrashMonitor_MachException.h"
#include "KSCrashMonitor_Memory.h"
#include "KSCrashMonitor_NSException.h"
#include "KSCrashMonitor_Signal.h"
#include "KSCrashMonitor_System.h"
#include "KSCrashMonitor_User.h"
#include "KSCrashMonitor_UserInfo.h"
#include "KSCrashMonitor_Watchdog.h"
#include "KSCrashMonitor_Zombie.h"
#include "KSCrashReportC.h"
#include "KSCrashReportFixer.h"
#include "KSCrashReportStoreC+Private.h"
#include "KSDynamicLinker.h"
#include "KSFileUtils.h"
#include "KSObjC.h"
#include "KSString.h"
#include "KSSystemCapabilities.h"
#include "KSThreadCache.h"

// #define KSLogger_LocalLevel TRACE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <uuid/uuid.h>

#include "KSLogger.h"

#define KSC_MAX_APP_NAME_LENGTH 100
#define KSC_MAX_PLUGINS 64
#define KSC_UUID_STRING_LENGTH 36
#define KSC_RUN_ID_FILE_MODE 0644

static const struct KSCrashMonitorMapping {
    KSCrashMonitorType type;
    KSCrashMonitorAPI *(*getAPI)(void);
}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
g_monitorMappings[] = { { KSCrashMonitorTypeMachException, kscm_machexception_getAPI },
                        { KSCrashMonitorTypeSignal, kscm_signal_getAPI },
                        { KSCrashMonitorTypeCPPException, kscm_cppexception_getAPI },
                        { KSCrashMonitorTypeNSException, kscm_nsexception_getAPI },
                        { KSCrashMonitorTypeMainThreadDeadlock, kscm_deadlock_getAPI },
                        { KSCrashMonitorTypeUserReported, kscm_user_getAPI },
                        { KSCrashMonitorTypeSystem, kscm_system_getAPI },
                        { KSCrashMonitorTypeApplicationState, kscm_lifecycle_getAPI },
                        { KSCrashMonitorTypeZombie, kscm_zombie_getAPI },
                        { KSCrashMonitorTypeMemoryTermination, kscm_memory_getAPI },
                        { KSCrashMonitorTypeWatchdog, kscm_watchdog_getAPI } };
#pragma clang diagnostic pop

static const size_t g_monitorMappingCount = sizeof(g_monitorMappings) / sizeof(g_monitorMappings[0]);

// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** True if KSCrash has been installed. */
static atomic_bool g_installed = false;

static bool g_shouldAddConsoleLogToReport = false;
static bool g_shouldPrintPreviousLog = false;
static char g_consoleLogPath[KSFU_MAX_PATH_LENGTH];
static KSCrashMonitorType g_monitoring = KSCrashMonitorTypeProductionSafeMinimal;
static char g_lastCrashReportFilePath[KSFU_MAX_PATH_LENGTH];
static KSCrashReportStoreCConfiguration g_reportStoreConfig;
// TODO: Remove in 3.0
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static KSReportWriteCallback g_legacyCrashNotifyCallback;
static KSReportWrittenCallback g_legacyReportWrittenCallback;
#pragma clang diagnostic pop
static KSCrashWillWriteReportCallback g_willWriteReportCallback;
static KSCrashIsWritingReportCallback g_isWritingReportCallback;
static KSCrashDidWriteReportCallback g_didWriteReportCallback;
static KSCrashMonitorAPI g_plugins[KSC_MAX_PLUGINS];
static int g_pluginCount = 0;

// Run ID: a UUID generated once during kscrash_install().
// Read-only after that, so safe to access from crash handlers.
static char g_runID[KSC_UUID_STRING_LENGTH + 1];

// Previous run's ID, read from Data/last_run_id during install.
// Used by the Lifecycle monitor to find the previous sidecar.
static char g_lastRunID[KSC_UUID_STRING_LENGTH + 1];

// ============================================================================
#pragma mark - Utility -
// ============================================================================

/** Generate a new run ID, read the previous run's ID from disk, and persist the new one.
 *  After this call both g_runID and g_lastRunID are available.
 *  Must be called after the Data directory exists.
 */
static void rotateRunID(const char *installPath)
{
    uuid_t uuid;
    uuid_generate(uuid);
    uuid_unparse_lower(uuid, g_runID);

    char path[KSFU_MAX_PATH_LENGTH];
    if (snprintf(path, sizeof(path), "%s/Data/last_run_id", installPath) >= (int)sizeof(path)) {
        KSLOG_ERROR("last_run_id path too long");
        return;
    }

    g_lastRunID[0] = '\0';
    int fd = open(path, O_RDWR | O_CREAT, KSC_RUN_ID_FILE_MODE);
    if (fd < 0) {
        KSLOG_ERROR("Could not open %s: %s", path, strerror(errno));
        return;
    }

    ssize_t n = read(fd, g_lastRunID, KSC_UUID_STRING_LENGTH);
    if (n == KSC_UUID_STRING_LENGTH) {
        g_lastRunID[KSC_UUID_STRING_LENGTH] = '\0';
        // Reject non-UUID values to prevent path traversal via crafted file.
        uuid_t parsed;
        if (uuid_parse(g_lastRunID, parsed) != 0) {
            KSLOG_ERROR("last_run_id is not a valid UUID, ignoring");
            g_lastRunID[0] = '\0';
        }
    } else if (n < 0) {
        KSLOG_ERROR("Failed to read last_run_id: %s", strerror(errno));
        g_lastRunID[0] = '\0';
    } else if (n > 0) {
        KSLOG_ERROR("last_run_id has unexpected length %zd (expected %d), ignoring", n, KSC_UUID_STRING_LENGTH);
        g_lastRunID[0] = '\0';
    }
    // n == 0: empty file (first run), g_lastRunID already cleared above.

    // Always attempt to write the new run ID, even if truncate/seek fail.
    // A partial failure here leaves a malformed file that UUID validation
    // will reject on next launch — better than leaving a stale ID that
    // points to the wrong sidecar.
    if (ftruncate(fd, 0) != 0) {
        KSLOG_ERROR("Failed to truncate %s: %s", path, strerror(errno));
    }
    if (lseek(fd, 0, SEEK_SET) == (off_t)-1) {
        KSLOG_ERROR("Failed to seek in %s: %s", path, strerror(errno));
    }
    if (!ksfu_writeBytesToFD(fd, g_runID, KSC_UUID_STRING_LENGTH)) {
        KSLOG_ERROR("Failed to write new run ID to %s", path);
    }
    close(fd);
}

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

// ============================================================================
#pragma mark - Callback Adapters -
// ============================================================================

/** Adapter function that bridges legacy crash notify callback to new signature.
 * This allows old callbacks without plan awareness to be used with the new system.
 */
static void legacyCrashNotifyCallbackAdapter(__unused const KSCrash_ExceptionHandlingPlan *const plan,
                                             const KSCrashReportWriter *writer)
{
    if (g_legacyCrashNotifyCallback) {
        KSLOG_WARN(
            "Using deprecated crash notify callback without plan awareness. "
            "Consider upgrading to isWritingReportCallback.");
        g_legacyCrashNotifyCallback(writer);
    }
}

/** Adapter function that bridges legacy report written callback to new signature.
 * This allows old callbacks without plan awareness to be used with the new system.
 */
static void legacyReportWrittenCallbackAdapter(__unused const KSCrash_ExceptionHandlingPlan *const plan,
                                               int64_t reportID)
{
    if (g_legacyReportWrittenCallback) {
        KSLOG_WARN(
            "Using deprecated report written callback without plan awareness. "
            "Consider upgrading to didWriteReportCallback.");
        g_legacyReportWrittenCallback(reportID);
    }
}

// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

/** Called when a crash occurs.
 *
 * This function gets passed as a callback to a crash handler.
 */
static void onExceptionEvent(struct KSCrash_MonitorContext *monitorContext, KSCrash_ReportResult *result)
{
    // Check if the user wants to modify the plan for this crash.
    if (g_willWriteReportCallback) {
        KSCrash_ExceptionHandlingPlan plan = ksexc_monitorContextToPlan(monitorContext);
        g_willWriteReportCallback(&plan, monitorContext);
        ksexc_modifyMonitorContextUsingPlan(monitorContext, &plan);
    }

    // If we shouldn't write a report, then there's nothing left to do here.
    if (!monitorContext->requirements.shouldWriteReport) {
        return;
    }

    monitorContext->consoleLogPath = g_shouldAddConsoleLogToReport ? g_consoleLogPath : NULL;

    if (monitorContext->requirements.crashedDuringExceptionHandling) {
        kscrashreport_writeRecrashReport(monitorContext, g_lastCrashReportFilePath);
    } else if (monitorContext->reportPath) {
        kscrashreport_writeStandardReport(monitorContext, monitorContext->reportPath);
    } else {
        char crashReportFilePath[KSFU_MAX_PATH_LENGTH];
        int64_t reportID = kscrs_getNextCrashReport(crashReportFilePath, &g_reportStoreConfig);
        strncpy(g_lastCrashReportFilePath, crashReportFilePath, sizeof(g_lastCrashReportFilePath));
        kscrashreport_writeStandardReport(monitorContext, crashReportFilePath);

        if (result) {
            result->reportId = reportID;
            strncpy(result->path, g_lastCrashReportFilePath, sizeof(result->path));
        }

        if (g_didWriteReportCallback != NULL) {
            KSCrash_ExceptionHandlingPlan plan = ksexc_monitorContextToPlan(monitorContext);
            g_didWriteReportCallback(&plan, reportID);
        }
    }
}

static void setPluginMonitors(KSCrashMonitorAPI *apis, int count)
{
    g_pluginCount = 0;
    if (apis == NULL || count <= 0) {
        return;
    }
    for (int i = 0; i < count && i < KSC_MAX_PLUGINS; i++) {
        g_plugins[i] = apis[i];
        kscm_addMonitor(&g_plugins[i]);
        g_pluginCount++;
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

static void handleConfiguration(KSCrashCConfiguration *configuration)
{
    g_reportStoreConfig = KSCrashReportStoreCConfiguration_Copy(&configuration->reportStoreConfiguration);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (configuration->userInfoJSON != NULL) {
        kscrashreport_setUserInfoJSON(configuration->userInfoJSON);
    }
#pragma clang diagnostic pop
#if KSCRASH_HAS_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    kscm_setDeadlockHandlerWatchdogInterval(configuration->deadlockWatchdogInterval);
#pragma clang diagnostic pop
#endif
    kstc_setSearchQueueNames(configuration->enableQueueNameSearch);
    kscrashreport_setIntrospectMemory(configuration->enableMemoryIntrospection);
    if (configuration->doNotIntrospectClasses.strings != NULL) {
        kscrashreport_setDoNotIntrospectClasses(configuration->doNotIntrospectClasses.strings,
                                                configuration->doNotIntrospectClasses.length);
    }

    // TODO: Remove in 3.0 - Set up deprecated callbacks for backward compatibility
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    g_legacyCrashNotifyCallback = configuration->crashNotifyCallback;
    g_legacyReportWrittenCallback = configuration->reportWrittenCallback;
#pragma clang diagnostic pop

    if (configuration->isWritingReportCallback) {
        g_isWritingReportCallback = configuration->isWritingReportCallback;
    } else if (g_legacyCrashNotifyCallback) {
        g_isWritingReportCallback = legacyCrashNotifyCallbackAdapter;
    } else {
        g_isWritingReportCallback = NULL;
    }

    if (configuration->didWriteReportCallback) {
        g_didWriteReportCallback = configuration->didWriteReportCallback;
    } else if (g_legacyReportWrittenCallback) {
        g_didWriteReportCallback = legacyReportWrittenCallbackAdapter;
    } else {
        g_didWriteReportCallback = NULL;
    }

    kscrashreport_setIsWritingReportCallback(g_isWritingReportCallback);
    kscm_watchdog_setReportsHangs(configuration->enableHangReporting);
    kscrashreport_setCompactBinaryImages(configuration->enableCompactBinaryImages);
    g_shouldAddConsoleLogToReport = configuration->addConsoleLogToReport;
    g_shouldPrintPreviousLog = configuration->printPreviousLogOnStartup;
    g_willWriteReportCallback = configuration->willWriteReportCallback;

    if (configuration->enableSwapCxaThrow) {
        kscm_enableSwapCxaThrow();
    }
}
static bool getReportSidecarFilePathCallback(const char *monitorId, const char *name, const char *extension,
                                             char *pathBuffer, size_t pathBufferLength)
{
    return kscrs_getReportSidecarFilePath(monitorId, name, extension, pathBuffer, pathBufferLength,
                                          &g_reportStoreConfig);
}

static bool getReportSidecarPathCallback(const char *monitorId, int64_t reportID, char *pathBuffer,
                                         size_t pathBufferLength)
{
    return kscrs_getReportSidecarFilePathForReport(monitorId, reportID, pathBuffer, pathBufferLength,
                                                   &g_reportStoreConfig);
}

static bool getRunSidecarPathCallback(const char *monitorId, char *pathBuffer, size_t pathBufferLength)
{
    return kscrs_getRunSidecarFilePath(monitorId, pathBuffer, pathBufferLength, &g_reportStoreConfig);
}

static bool getRunSidecarPathForRunIDCallback(const char *monitorId, const char *runID, char *pathBuffer,
                                              size_t pathBufferLength)
{
    return kscrs_getRunSidecarFilePathForRunID(monitorId, runID, pathBuffer, pathBufferLength, &g_reportStoreConfig);
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

    // Create Data directory early so run IDs and memory tracking are available
    // before report store initialization.
    char path[KSFU_MAX_PATH_LENGTH];
    if (snprintf(path, sizeof(path), "%s/Data", installPath) >= (int)sizeof(path)) {
        KSLOG_ERROR("Data path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    if (ksfu_makePath(path) == false) {
        KSLOG_ERROR("Could not create path: %s", path);
        return KSCrashInstallErrorCouldNotCreatePath;
    }
    ksmemory_initialize(path);
    rotateRunID(installPath);

    if (g_reportStoreConfig.appName == NULL) {
        g_reportStoreConfig.appName = strdup(appName);
    }

    if (g_reportStoreConfig.reportsPath == NULL) {
        if (snprintf(path, sizeof(path), "%s/" KSCRS_DEFAULT_REPORTS_FOLDER, installPath) >= (int)sizeof(path)) {
            KSLOG_ERROR("Reports path is too long.");
            return KSCrashInstallErrorPathTooLong;
        }
        g_reportStoreConfig.reportsPath = strdup(path);
    }

    if (g_reportStoreConfig.reportSidecarsPath == NULL) {
        if (snprintf(path, sizeof(path), "%s/Sidecars", installPath) >= (int)sizeof(path)) {
            KSLOG_ERROR("Sidecars path is too long.");
            return KSCrashInstallErrorPathTooLong;
        }
        g_reportStoreConfig.reportSidecarsPath = strdup(path);
    }

    if (g_reportStoreConfig.runSidecarsPath == NULL) {
        if (snprintf(path, sizeof(path), "%s/RunSidecars", installPath) >= (int)sizeof(path)) {
            KSLOG_ERROR("RunSidecars path is too long.");
            return KSCrashInstallErrorPathTooLong;
        }
        g_reportStoreConfig.runSidecarsPath = strdup(path);
    }

    kscrs_initialize(&g_reportStoreConfig);
    kscm_setReportSidecarFilePathProvider(getReportSidecarFilePathCallback);
    kscm_setReportSidecarPathProvider(getReportSidecarPathCallback);
    kscm_setRunSidecarPathProvider(getRunSidecarPathCallback);
    kscm_setRunSidecarPathForRunIDProvider(getRunSidecarPathForRunIDCallback);

    if (snprintf(g_consoleLogPath, sizeof(g_consoleLogPath), "%s/Data/ConsoleLog.txt", installPath) >=
        (int)sizeof(g_consoleLogPath)) {
        KSLOG_ERROR("Console log path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    if (g_shouldPrintPreviousLog) {
        printPreviousLog(g_consoleLogPath);
    }
    kslog_setLogFilename(g_consoleLogPath, true);

    kstc_init(60);

    ksdl_init();

    kscm_setEventCallbackWithResult(onExceptionEvent);

    setMonitors(configuration->monitors);
    setPluginMonitors(configuration->plugins.apis, configuration->plugins.length);

    if (kscm_activateMonitors() == false) {
        KSLOG_ERROR("No crash monitors are active");
        return KSCrashInstallErrorNoActiveMonitors;
    }

    g_installed = true;
    KSLOG_DEBUG("Installation complete.");

    return KSCrashInstallErrorNone;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
void kscrash_setUserInfoJSON(const char *const userInfoJSON) { kscrashreport_setUserInfoJSON(userInfoJSON); }

const char *kscrash_getUserInfoJSON(void) { return kscrashreport_getUserInfoJSON(); }
#pragma clang diagnostic pop

void kscrash_setUserInfoString(const char *key, const char *value) { kscm_userinfo_setString(key, value); }

void kscrash_setUserInfoInt(const char *key, int64_t value) { kscm_userinfo_setInt64(key, value); }

void kscrash_setUserInfoUInt(const char *key, uint64_t value) { kscm_userinfo_setUInt64(key, value); }

void kscrash_setUserInfoDouble(const char *key, double value) { kscm_userinfo_setDouble(key, value); }

void kscrash_setUserInfoBool(const char *key, bool value) { kscm_userinfo_setBool(key, value); }

void kscrash_setUserInfoDate(const char *key, uint64_t nanosecondsSince1970)
{
    kscm_userinfo_setDate(key, nanosecondsSince1970);
}

void kscrash_removeUserInfoValue(const char *key) { kscm_userinfo_removeValue(key); }

void kscrash_reportUserException(const char *name, const char *reason, const char *language, const char *lineOfCode,
                                 const char *stackTrace, bool logAllThreads,
                                 bool terminateProgram) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    kscm_reportUserException(name, reason, language, lineOfCode, stackTrace, logAllThreads, terminateProgram);
    if (g_shouldAddConsoleLogToReport) {
        kslog_clearLogFile();
    }
    KS_THWART_TAIL_CALL_OPTIMISATION
}

int64_t kscrash_addUserReport(const char *report, int reportLength)
{
    return kscrs_addUserReport(report, reportLength, &g_reportStoreConfig);
}

const char *kscrash_getRunID(void) { return g_runID; }

const char *kscrash_getLastRunID(void) { return g_lastRunID; }

const char *kscrash_namespaceIdentifier(void) { return KSCRASH_NS_STRING("KSCrash"); }

// ============================================================================
#pragma mark - Deprecated -
// ============================================================================

void kscrash_notifyObjCLoad(void) { KSLOG_DEBUG("kscrash_notifyObjCLoad is deprecated and does nothing."); }

void kscrash_notifyAppActive(__unused bool isActive)
{
    KSLOG_DEBUG("kscrash_notifyAppActive is deprecated and does nothing.");
}

void kscrash_notifyAppInForeground(__unused bool isInForeground)
{
    KSLOG_DEBUG("kscrash_notifyAppInForeground is deprecated and does nothing.");
}

void kscrash_notifyAppTerminate(void) { KSLOG_DEBUG("kscrash_notifyAppTerminate is deprecated and does nothing."); }

void kscrash_notifyAppCrash(void) { KSLOG_DEBUG("kscrash_notifyAppCrash is deprecated and does nothing."); }

// ============================================================================
#pragma mark - Testing API -
// ============================================================================

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscrash_testcode_setLastRunID(const char *runID)
{
    if (runID != NULL) {
        strncpy(g_lastRunID, runID, sizeof(g_lastRunID) - 1);
        g_lastRunID[sizeof(g_lastRunID) - 1] = '\0';
    } else {
        g_lastRunID[0] = '\0';
    }
}
