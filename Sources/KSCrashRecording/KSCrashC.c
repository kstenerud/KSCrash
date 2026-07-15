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
#include "KSCrashMonitor_NSException.h"
#include "KSCrashMonitor_Resource.h"
#include "KSCrashMonitor_Signal.h"
#include "KSCrashMonitor_System.h"
#include "KSCrashMonitor_Termination.h"
#include "KSCrashMonitor_User.h"
#include "KSCrashMonitor_UserInfo.h"
#include "KSCrashMonitor_Watchdog.h"
#include "KSCrashMonitor_Zombie.h"
#include "KSCrashReportC.h"
#include "KSCrashReportFixer.h"
#include "KSCrashReportStoreC+Private.h"
#include "KSCrashRunContext.h"
#include "KSDynamicLinker.h"
#include "KSFileUtils.h"
#include "KSMemory.h"
#include "KSObjC.h"
#include "KSStackCursor_SelfThread.h"
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
                        { KSCrashMonitorTypeTermination, kscm_termination_getAPI },
                        { KSCrashMonitorTypeApplicationState, kscm_lifecycle_getAPI },
                        { KSCrashMonitorTypeZombie, kscm_zombie_getAPI },
                        { KSCrashMonitorTypeWatchdog, kscm_watchdog_getAPI },
                        { KSCrashMonitorTypeUserInfo, kscm_userinfo_getAPI },
                        { KSCrashMonitorTypeResource, kscm_resource_getAPI } };
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

// Run ID: a UUID generated once during kscrash_install(). In a normal app it is read-only after
// that, so it stays safe to access from crash handlers. It lives in a named section so a crash
// extension can locate it in a process corpse and load the crashed run's id
// into its own g_runIDSection (see kscrash_loadRunIDFromCorpse), stamping its report with the same id.
// The payload carries the namespace identifier because the section name can't (Mach-O section
// names are capped at 16 bytes): with two namespaced KSCrash copies in one app, both carry a
// __ks_runid section, and the loader must pick the copy matching its own namespace.
typedef struct {
    char namespaceID[64];
    char runID[KSC_UUID_STRING_LENGTH + 1];
} KSRunIDSectionPayload;

static KSRunIDSectionPayload g_runIDSection __attribute__((section("__DATA,__ks_runid"))) = {
    .namespaceID = KSCRASH_NS_STRING("KSCrash"),
};

// Previous run's ID, read from Data/last_run_id during install.
// Used by the Lifecycle monitor to find the previous sidecar.
static char g_lastRunID[KSC_UUID_STRING_LENGTH + 1];

// ============================================================================
#pragma mark - Utility -
// ============================================================================

/** Generate a new run ID, read the previous run's ID from disk, and persist the new one.
 *  After this call both g_runIDSection.runID and g_lastRunID are available.
 *  Must be called after the Data directory exists.
 */
static void rotateRunID(const char *installPath)
{
    uuid_t uuid;
    uuid_generate(uuid);
    uuid_unparse_lower(uuid, g_runIDSection.runID);

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
    if (!ksfu_writeBytesToFD(fd, g_runIDSection.runID, KSC_UUID_STRING_LENGTH)) {
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
        // No store ID for a caller-supplied path, but report the write in the result so a
        // caller can tell it happened; an event rerouted away from this branch (recrash,
        // vetoed write) leaves the result empty.
        if (result) {
            strlcpy(result->path, monitorContext->reportPath, sizeof(result->path));
        }
    } else {
        char crashReportFilePath[KSFU_MAX_PATH_LENGTH];
        int64_t reportID = kscrs_getNextCrashReport(crashReportFilePath, &g_reportStoreConfig);
        strlcpy(g_lastCrashReportFilePath, crashReportFilePath, sizeof(g_lastCrashReportFilePath));
        kscrashreport_writeStandardReport(monitorContext, crashReportFilePath);

        if (result) {
            result->reportId = reportID;
            strlcpy(result->path, g_lastCrashReportFilePath, sizeof(result->path));
        }

        if (g_didWriteReportCallback != NULL) {
            KSCrash_ExceptionHandlingPlan plan = ksexc_monitorContextToPlan(monitorContext);
            g_didWriteReportCallback(&plan, reportID);
        }
    }
}

static void onFinalizeReport(__unused struct KSCrash_MonitorContext *monitorContext, const KSCrash_ReportResult *result)
{
    kscrs_finalizeReport(result->path, result->reportId);
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
    // Infrastructure monitors (System, Lifecycle, UserInfo, Resource) are
    // always enabled. They collect context that every report depends on
    // and are not crash detectors, so there is no reason to disable them.
    const KSCrashMonitorType effectiveMonitorTypes = monitorTypes | KSCrashMonitorTypeRequired;

    for (size_t i = 0; i < g_monitorMappingCount; i++) {
        KSCrashMonitorAPI *api = g_monitorMappings[i].getAPI();
        if (api != NULL) {
            if (effectiveMonitorTypes & g_monitorMappings[i].type) {
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
    kscm_resource_setReportsCPUExceptions(configuration->enableCPUExceptionReporting);
    kscrashreport_setCompactBinaryImages(configuration->enableCompactBinaryImages);
    kssc_setSwiftAsyncStackTracesEnabled(configuration->enableSwiftAsyncStackTraces);
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

/** Derive a default store directory (e.g. "Runs", "Sidecars", "RunSidecars")
 *  as a sibling of reportsPath, matching the ObjC KSCrashReportStoreConfiguration
 *  which derives these via -stringByDeletingLastPathComponent. Trailing '/' are
 *  trimmed first, so reportsPath "/a/Reports/" with subdir "Runs" yields
 *  "/a/Runs", not "/a/Reports/Runs" (the store scans the sibling, so the
 *  latter would never be found). Falls back to subdir under installPath when
 *  reportsPath has no usable parent (e.g. "Reports" or "/Reports"). reportsPath
 *  must be non-NULL; the caller fills in a default before this is reached.
 *  Returns false if the result does not fit in out. */
static bool deriveReportsSiblingDir(const char *reportsPath, const char *installPath, const char *subdir, char *out,
                                    size_t outSize)
{
    const char *lastSlash = NULL;
    size_t len = strlen(reportsPath);
    while (len > 1 && reportsPath[len - 1] == '/') {
        len--;
    }
    for (const char *p = reportsPath + len; p > reportsPath; p--) {
        if (p[-1] == '/') {
            lastSlash = p - 1;
            break;
        }
    }
    int written;
    if (lastSlash != NULL && lastSlash != reportsPath) {
        written = snprintf(out, outSize, "%.*s/%s", (int)(lastSlash - reportsPath), reportsPath, subdir);
    } else {
        written = snprintf(out, outSize, "%s/%s", installPath, subdir);
    }
    return written >= 0 && written < (int)outSize;
}

/** Fill any unset report store paths with their defaults under installPath, and the app name.
 *  Shared by both install entry points so a store configured either way scans the same layout.
 */
static KSCrashInstallErrorCode resolveStoreConfigDefaults(const char *appName, const char *const installPath)
{
    char path[KSFU_MAX_PATH_LENGTH];

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

    // Sidecars, RunSidecars and Runs default to siblings of reportsPath,
    // matching the ObjC KSCrashReportStoreConfiguration. Deriving these from
    // installPath instead would write them where a store configured with the
    // same reportsPath does not scan.
    if (g_reportStoreConfig.reportSidecarsPath == NULL) {
        if (!deriveReportsSiblingDir(g_reportStoreConfig.reportsPath, installPath, "Sidecars", path, sizeof(path))) {
            KSLOG_ERROR("Sidecars path is too long.");
            return KSCrashInstallErrorPathTooLong;
        }
        g_reportStoreConfig.reportSidecarsPath = strdup(path);
    }

    if (g_reportStoreConfig.runSidecarsPath == NULL) {
        if (!deriveReportsSiblingDir(g_reportStoreConfig.reportsPath, installPath, "RunSidecars", path, sizeof(path))) {
            KSLOG_ERROR("RunSidecars path is too long.");
            return KSCrashInstallErrorPathTooLong;
        }
        g_reportStoreConfig.runSidecarsPath = strdup(path);
    }

    if (g_reportStoreConfig.runSummariesPath == NULL) {
        if (!deriveReportsSiblingDir(g_reportStoreConfig.reportsPath, installPath, "Runs", path, sizeof(path))) {
            KSLOG_ERROR("Runs path is too long.");
            return KSCrashInstallErrorPathTooLong;
        }
        g_reportStoreConfig.runSummariesPath = strdup(path);
    }

    return KSCrashInstallErrorNone;
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

    // Create Data directory early so run IDs are available
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
    rotateRunID(installPath);

    KSCrashInstallErrorCode pathResult = resolveStoreConfigDefaults(appName, installPath);
    if (pathResult != KSCrashInstallErrorNone) {
        return pathResult;
    }

    KSCrashInstallErrorCode storeInitResult = kscrs_initialize(&g_reportStoreConfig);
    if (storeInitResult != KSCrashInstallErrorNone) {
        return storeInitResult;
    }
    // Register the install's config as the source of paths for the no-config
    // readers (readReportAtPath, readReportByPathAndID, finalizeReport). Only
    // the install does this; constructing a KSCrashReportStore no longer
    // hijacks the stitch path.
    kscrs_setStitchConfig(&g_reportStoreConfig);
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
    kscm_setFinalizeReportCallback(onFinalizeReport);

    setMonitors(configuration->monitors);
    setPluginMonitors(configuration->plugins.apis, configuration->plugins.length);

    // Monitor startup is four steps, order matters:
    //  1. enableMonitors         — installs signal/mach handlers, creates sidecars for the current run.
    //  2. postMonitorsEnabled    — monitors populate current-run sidecar data that RunContext needs
    //                              (e.g. BootTime writes kern.boottime so reboot detection works).
    //  3. RunContext init        — reads *previous* run's sidecars, compares against current, determines
    //                              the termination reason.
    //  4. postSystemEnable       — tells monitors RunContext is ready so they can act on previous-run data
    //                              (e.g. Termination injects a report, Memory checks for OOM).
    if (kscm_enableMonitors() == false) {
        KSLOG_ERROR("No crash monitors are active");
        return KSCrashInstallErrorNoActiveMonitors;
    }
    kscm_notifyPostMonitorsEnabled();
    ksruncontext_init(getRunSidecarPathForRunIDCallback);
    // g_reportStoreConfig has the resolved default path, whereas `configuration`
    // still holds whatever the caller passed in (NULL is valid there). Skip
    // when the caller disabled the feature via maxRunSummaryCount <= 0.
    //
    // Install only appends — the retention cap is enforced on the send path
    // (sendAllRunSummariesWithConfiguration:completion:) and via the public
    // ksruncontext_pruneRunSummaries() API that callers can invoke on their
    // own cadence. Intentionally not pruning here so retention policy stays a
    // caller choice rather than being coupled to launch timing.
    if (g_reportStoreConfig.maxRunSummaryCount > 0) {
        ksruncontext_persistPreviousRunSummary(g_reportStoreConfig.runSummariesPath);
    }
    kscm_notifyPostSystemEnable();

    g_installed = true;
    KSLOG_DEBUG("Installation complete.");

    return KSCrashInstallErrorNone;
}

KSCrashInstallErrorCode kscrash_installForExtensionReporting(const char *appName, const char *const installPath,
                                                             KSCrashMonitorAPI *pluginAPIs, int pluginCount)
{
    KSLOG_DEBUG("Installing crash reporter in extension (reporter-only) mode.");

    if (g_installed) {
        KSLOG_DEBUG("Crash reporter already installed.");
        return KSCrashInstallErrorAlreadyInstalled;
    }
    if (appName == NULL || installPath == NULL) {
        KSLOG_ERROR("Invalid parameters: appName or installPath is NULL.");
        return KSCrashInstallErrorInvalidParameter;
    }

    // A reporter-only process: it writes reports about other processes into its own report
    // area (typically in an App Group container the app reads later) and runs none of the
    // app-lifecycle machinery. No run id (a capture loads the crashed run's), no last_run_id
    // chain, no RunContext or run summaries (previous-run analysis and session counting are
    // the app's job), no console log, no crash-detection monitors, no report pruning, no
    // sidecar or stitch wiring (a corpse report carries its data directly and is stitched by
    // the app at read time), no thread cache (it only knows this process's threads, and the
    // writer degrades to nameless threads without it), and no dynamic-linker symbol cache
    // (a subject's frames must resolve against its provided images, never this process's).
    g_reportStoreConfig = KSCrashReportStoreCConfiguration_Default();
    g_reportStoreConfig.maxReportCount = 0;  // Never prune from here.
    KSCrashInstallErrorCode pathResult = resolveStoreConfigDefaults(appName, installPath);
    if (pathResult != KSCrashInstallErrorNone) {
        return pathResult;
    }
    KSCrashInstallErrorCode storeInitResult = kscrs_initialize(&g_reportStoreConfig);
    if (storeInitResult != KSCrashInstallErrorNone) {
        return storeInitResult;
    }

    kscm_setEventCallbackWithResult(onExceptionEvent);

    setPluginMonitors(pluginAPIs, pluginCount);
    // Plugins are excluded from the "any crash monitor active" verdict by design, and a
    // reporter-only process has no crash monitors, so the verdict is meaningless here.
    (void)kscm_enableMonitors();
    // Same post-enable step as kscrash_install. kscm_notifyPostSystemEnable is deliberately
    // NOT fired: its contract is "RunContext is ready", and RunContext never initializes in
    // extension mode.
    kscm_notifyPostMonitorsEnabled();

    g_installed = true;
    KSLOG_DEBUG("Extension installation complete.");

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

const char *kscrash_getRunID(void) { return g_runIDSection.runID; }

void kscrash_clearRunID(void)
{
    // Extension use only: the run id is per-corpse state there, so each capture clears it
    // before loading the next corpse's. Never called in a normal install, where the id is
    // generated once and stays read-only for signal safety.
    memset(g_runIDSection.runID, 0, sizeof(g_runIDSection.runID));
}

void kscrash_testcode_setRunID(const char *runID)
{
    // Tests only. Install generates the run id once per process and clearing it is otherwise
    // irreversible, so a test that exercises clear-then-failed-load would strand every later
    // test in the process with an empty id. This lets such a test put back what it took.
    if (runID == NULL) {
        memset(g_runIDSection.runID, 0, sizeof(g_runIDSection.runID));
        return;
    }
    strlcpy(g_runIDSection.runID, runID, sizeof(g_runIDSection.runID));
}

bool kscrash_loadRunIDFromCorpse(task_t corpse, const uint64_t *imageLoadAddresses, uint32_t imageCount)
{
    // Runs in a crash extension: scan the corpse's images for the __ks_runid section and
    // load the crashed run's id into g_runIDSection.runID, so a report this process writes for the corpse carries
    // the app's run id rather than this process's own. Caller passes the corpse's image load
    // addresses (it already has them from the crash extension's binary image list).
    // Writes only on success; a capture clears first (kscrash_clearRunID) so a corpse whose
    // id cannot be read is reported with no run id, never a previous corpse's.
    if (corpse == MACH_PORT_NULL || imageLoadAddresses == NULL || imageCount == 0) {
        return false;
    }

    for (uint32_t i = 0; i < imageCount; i++) {
        uintptr_t sectionAddr = 0;
        uintptr_t sectionSize = 0;
        if (!ksbic_findSectionInTaskImage(corpse, (uintptr_t)imageLoadAddresses[i], "__DATA", "__ks_runid",
                                          &sectionAddr, &sectionSize)) {
            continue;
        }
        if (sectionSize < sizeof(KSRunIDSectionPayload)) {
            continue;
        }

        KSRunIDSectionPayload payload;
        if (!ksmem_copySafelyFromTask(corpse, (const void *)sectionAddr, &payload, sizeof(payload))) {
            continue;
        }
        payload.namespaceID[sizeof(payload.namespaceID) - 1] = '\0';
        payload.runID[KSC_UUID_STRING_LENGTH] = '\0';

        // Only accept the KSCrash copy in the same namespace as this one; with multiple
        // namespaced copies in one app each carries its own __ks_runid section.
        if (strcmp(payload.namespaceID, g_runIDSection.namespaceID) != 0) {
            continue;
        }

        // Only accept a well-formed UUID; an uninitialized section reads as zeros and is skipped.
        uuid_t parsed;
        if (uuid_parse(payload.runID, parsed) != 0) {
            continue;
        }

        memcpy(g_runIDSection.runID, payload.runID, KSC_UUID_STRING_LENGTH);
        g_runIDSection.runID[KSC_UUID_STRING_LENGTH] = '\0';
        return true;
    }
    return false;
}

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
bool kscrash_testcode_deriveReportsSiblingDir(const char *reportsPath, const char *installPath, const char *subdir,
                                              char *out, size_t outSize)
{
    return deriveReportsSiblingDir(reportsPath, installPath, subdir, out, outSize);
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscrash_testcode_setMonitors(KSCrashMonitorType monitorTypes)
{
    setMonitors(monitorTypes);
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscrash_testcode_setLastRunID(const char *runID)
{
    if (runID != NULL) {
        strlcpy(g_lastRunID, runID, sizeof(g_lastRunID));
    } else {
        g_lastRunID[0] = '\0';
    }
}
