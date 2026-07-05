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
#include "KSCrashMonitorType+Private.h"
#include "KSCrashMonitorType.h"
#include "KSCrashMonitor_CPPException.h"
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
#define KSC_UUID_STRING_LENGTH 36
#define KSC_RUN_ID_FILE_MODE 0644

// KSCrashCConfiguration is filled by Objective-C and Swift and read here as C;
// its layout only agrees while the monitor mask has NSUInteger's width.
_Static_assert(sizeof(KSCrashMonitorType) == sizeof(unsigned long), "KSCrashMonitorType must be NSUInteger-wide in C");

static const struct KSCrashMonitorMapping {
    KSCrashMonitorType type;
    KSCrashMonitorAPI *(*getAPI)(void);
} g_monitorMappings[] = { { KSCrashMonitorTypeMachException, kscm_machexception_getAPI },
                          { KSCrashMonitorTypeSignal, kscm_signal_getAPI },
                          { KSCrashMonitorTypeCPPException, kscm_cppexception_getAPI },
                          { KSCrashMonitorTypeNSException, kscm_nsexception_getAPI },
                          { KSCrashMonitorTypeUserReported, kscm_user_getAPI },
                          { KSCrashMonitorTypeSystem, kscm_system_getAPI },
                          { KSCrashMonitorTypeTermination, kscm_termination_getAPI },
                          { KSCrashMonitorTypeApplicationState, kscm_lifecycle_getAPI },
                          { KSCrashMonitorTypeZombie, kscm_zombie_getAPI },
                          { KSCrashMonitorTypeHang, kscm_watchdog_getAPI },
                          { KSCrashMonitorTypeUserInfo, kscm_userinfo_getAPI },
                          { KSCrashMonitorTypeResource, kscm_resource_getAPI } };

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
    if (snprintf(path, sizeof(path), "%s/" KSCRS_DEFAULT_DATA_FOLDER "/last_run_id", installPath) >=
        (int)sizeof(path)) {
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
        // The rewritten file keeps its identity: the id is parsed from the
        // path's own filename (async-signal-safe), so it can never pair with
        // another crash's id the way a second id global could.
        char recrashReportID[KSID_SIZE] = { 0 };
        const char *filename = strrchr(g_lastCrashReportFilePath, '/');
        filename = filename != NULL ? filename + 1 : g_lastCrashReportFilePath;
        kscrs_parseReportFilename(filename, recrashReportID);
        kscrashreport_writeRecrashReport(monitorContext, g_lastCrashReportFilePath, recrashReportID);
    } else if (monitorContext->reportPath) {
        kscrashreport_writeStandardReport(monitorContext, monitorContext->reportPath);
        // No store ID for a caller-supplied path, but report the write in the result so a
        // caller can tell it happened; an event rerouted away from this branch (recrash,
        // vetoed write) leaves the result empty.
        if (result) {
            strlcpy(result->path, monitorContext->reportPath, sizeof(result->path));
        }
    } else {
        // The event id minted with the context is the report's identity.
        char crashReportFilePath[KSFU_MAX_PATH_LENGTH];
        kscrs_getNextCrashReport(monitorContext->eventID, crashReportFilePath, &g_reportStoreConfig);
        strlcpy(g_lastCrashReportFilePath, crashReportFilePath, sizeof(g_lastCrashReportFilePath));
        kscrashreport_writeStandardReport(monitorContext, crashReportFilePath);
        if (result) {
            strlcpy(result->reportId, monitorContext->eventID, sizeof(result->reportId));
            strlcpy(result->path, g_lastCrashReportFilePath, sizeof(result->path));
        }
        if (g_didWriteReportCallback != NULL) {
            KSCrash_ExceptionHandlingPlan plan = ksexc_monitorContextToPlan(monitorContext);
            g_didWriteReportCallback(&plan, monitorContext->eventID);
        }
    }
}

static void onFinalizeReport(__unused struct KSCrash_MonitorContext *monitorContext, const KSCrash_ReportResult *result)
{
    kscrs_finalizeReport(result->path, result->reportId);
}

bool kscrash_isBuiltInMonitorID(const char *monitorID)
{
    if (monitorID == NULL) {
        return false;
    }
    for (size_t i = 0; i < g_monitorMappingCount; i++) {
        KSCrashMonitorAPI *api = g_monitorMappings[i].getAPI();
        if (api == NULL || api->monitorId == NULL) {
            continue;
        }
        const char *id = api->monitorId(api->context);
        if (id != NULL && strncmp(id, monitorID, KSCRASH_MONITOR_ID_MAX_LENGTH) == 0) {
            return true;
        }
    }
    return false;
}

// false when the plugin count exceeds the cap: nothing is registered then,
// and the install fails rather than silently dropping crash coverage.
static bool setPluginMonitors(KSCrashMonitorAPI *apis, int count)
{
    g_pluginCount = 0;
    if (apis == NULL || count <= 0) {
        return true;
    }
    if (count > KSC_MAX_PLUGINS) {
        KSLOG_ERROR("%d plugins exceed the %d cap; failing the install", count, KSC_MAX_PLUGINS);
        return false;
    }
    for (int i = 0; i < count; i++) {
        g_plugins[i] = apis[i];
        kscm_addMonitor(&g_plugins[i]);
        g_pluginCount++;
    }
    return true;
}

// Undoes setPluginMonitors. The registry holds pointers into g_plugins, whose
// context fields are unretained references owned by the caller: a failed
// install releases them, so the entries must go before they dangle.
static void clearPluginMonitors(void)
{
    for (int i = 0; i < g_pluginCount; i++) {
        kscm_removeMonitor(&g_plugins[i]);
    }
    g_pluginCount = 0;
}

static void setMonitors(KSCrashMonitorType monitorTypes)
{
    // The required set (infrastructure plus UserReported) is always on; see
    // KSCrashMonitorTypeRequired.
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
    // The store paths are the install loop's strdups; a retry after a failed
    // install re-enters here, so release the previous attempt's strings
    // before the reset drops the pointers.
    free((char *)g_reportStoreConfig.reportsPath);
    free((char *)g_reportStoreConfig.reportSidecarsPath);
    free((char *)g_reportStoreConfig.runSidecarsPath);
    free((char *)g_reportStoreConfig.runSummariesPath);
    g_reportStoreConfig = KSCrashReportStoreCConfiguration_Default();
    g_reportStoreConfig.maxReportCount = configuration->maxReportCount;
    g_reportStoreConfig.maxRunSummaryCount = configuration->maxRunSummaryCount;

    kstc_setSearchQueueNames(configuration->enableQueueNameSearch);
    kscrashreport_setIntrospectMemory(configuration->enableMemoryIntrospection);
    if (configuration->doNotIntrospectClasses.strings != NULL) {
        kscrashreport_setDoNotIntrospectClasses(configuration->doNotIntrospectClasses.strings,
                                                configuration->doNotIntrospectClasses.length);
    }

    g_isWritingReportCallback = configuration->isWritingReportCallback;
    kscrashreport_setIsWritingReportCallback(g_isWritingReportCallback);
    kscm_watchdog_setReportsHangs(configuration->enableHangReporting);
    kscm_resource_setReportsCPUExceptions(configuration->enableCPUExceptionReporting);
    kscrashreport_setCompactBinaryImages(configuration->enableCompactBinaryImages);
    kssc_setSwiftAsyncStackTracesEnabled(configuration->enableSwiftAsyncStackTraces);
    g_shouldAddConsoleLogToReport = configuration->addConsoleLogToReport;
    g_shouldPrintPreviousLog = configuration->printPreviousLogOnStartup;
    g_willWriteReportCallback = configuration->willWriteReportCallback;
    g_didWriteReportCallback = configuration->didWriteReportCallback;

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

static bool getReportSidecarPathCallback(const char *monitorId, const char *reportID, char *pathBuffer,
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

static bool getSummarySidecarPathCallback(const char *runID, const char *extension, char *pathBuffer,
                                          size_t pathBufferLength)
{
    // maxRunSummaryCount only gates .run persistence. Sessions are recorded
    // either way so crash reports keep their session id; stale session files
    // are reclaimed at the end of any send flow.
    return kscrs_getSummarySidecarFilePath(runID, extension, pathBuffer, pathBufferLength, &g_reportStoreConfig);
}

/** Fill any unset report store paths with their defaults under installPath.
 *  Shared by both install entry points so a store configured either way scans the same layout.
 */
static KSCrashInstallErrorCode resolveStoreConfigDefaults(const char *const installPath)
{
    char path[KSFU_MAX_PATH_LENGTH];

    // The store directories live under the install root, by the names the
    // Swift install's Locations derive from the same constants.
    const struct {
        const char *folder;
        const char **field;
    } storeDirectories[] = {
        { KSCRS_DEFAULT_REPORTS_FOLDER, &g_reportStoreConfig.reportsPath },
        { KSCRS_DEFAULT_REPORT_SIDECARS_FOLDER, &g_reportStoreConfig.reportSidecarsPath },
        { KSCRS_DEFAULT_RUN_SIDECARS_FOLDER, &g_reportStoreConfig.runSidecarsPath },
        { KSCRS_DEFAULT_RUNS_FOLDER, &g_reportStoreConfig.runSummariesPath },
    };
    for (size_t i = 0; i < sizeof(storeDirectories) / sizeof(storeDirectories[0]); i++) {
        if (snprintf(path, sizeof(path), "%s/%s", installPath, storeDirectories[i].folder) >= (int)sizeof(path)) {
            KSLOG_ERROR("%s path is too long.", storeDirectories[i].folder);
            return KSCrashInstallErrorPathTooLong;
        }
        *storeDirectories[i].field = strdup(path);
        if (*storeDirectories[i].field == NULL) {
            return KSCrashInstallErrorCouldNotInitializeStore;
        }
    }

    return KSCrashInstallErrorNone;
}

// ============================================================================
#pragma mark - API -
// ============================================================================

KSCrashInstallErrorCode kscrash_install(const char *const installPath, KSCrashCConfiguration *configuration)
{
    KSLOG_DEBUG("Installing crash reporter.");

    if (g_installed) {
        KSLOG_DEBUG("Crash reporter already installed.");
        return KSCrashInstallErrorAlreadyInstalled;
    }

    if (installPath == NULL) {
        KSLOG_ERROR("Invalid parameters: installPath is NULL.");
        return KSCrashInstallErrorInvalidParameter;
    }

    handleConfiguration(configuration);

    // Create Data directory early so run IDs are available
    // before report store initialization.
    char path[KSFU_MAX_PATH_LENGTH];
    if (snprintf(path, sizeof(path), "%s/" KSCRS_DEFAULT_DATA_FOLDER, installPath) >= (int)sizeof(path)) {
        KSLOG_ERROR("Data path is too long.");
        return KSCrashInstallErrorPathTooLong;
    }
    if (ksfu_makePath(path) == false) {
        KSLOG_ERROR("Could not create path: %s", path);
        return KSCrashInstallErrorCouldNotCreatePath;
    }
    rotateRunID(installPath);

    KSCrashInstallErrorCode pathResult = resolveStoreConfigDefaults(installPath);
    if (pathResult != KSCrashInstallErrorNone) {
        return pathResult;
    }

    KSCrashInstallErrorCode storeInitResult = kscrs_initialize(&g_reportStoreConfig);
    if (storeInitResult != KSCrashInstallErrorNone) {
        return storeInitResult;
    }
    // Register the install's config as the source of paths for the no-config
    // readers (readReportAtPath, readReportByPathAndID, finalizeReport). Only
    // the install does this.
    kscrs_setStitchConfig(&g_reportStoreConfig);
    kscm_setReportSidecarFilePathProvider(getReportSidecarFilePathCallback);
    kscm_setReportSidecarPathProvider(getReportSidecarPathCallback);
    kscm_setRunSidecarPathProvider(getRunSidecarPathCallback);
    kscm_setRunSidecarPathForRunIDProvider(getRunSidecarPathForRunIDCallback);
    kscm_setSummarySidecarPathProvider(getSummarySidecarPathCallback);

    if (snprintf(g_consoleLogPath, sizeof(g_consoleLogPath), "%s/" KSCRS_DEFAULT_DATA_FOLDER "/ConsoleLog.txt",
                 installPath) >= (int)sizeof(g_consoleLogPath)) {
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
    if (!setPluginMonitors(configuration->plugins.apis, configuration->plugins.length)) {
        return KSCrashInstallErrorInvalidParameter;
    }

    // Monitor startup is four steps, order matters:
    //  1. enableMonitors         — installs signal/mach handlers, creates sidecars for the current run.
    //  2. postMonitorsEnabled    — monitors populate current-run sidecar data that RunContext needs
    //                              (e.g. BootTime writes kern.boottime so reboot detection works).
    //  3. RunContext init        — reads *previous* run's sidecars, compares against current, determines
    //                              the termination reason.
    //  4. postSystemEnable       — tells monitors RunContext is ready so they can act on previous-run data
    //                              (e.g. Termination injects a report, Memory checks for OOM).
    // The required monitors are always in the set, so a false here is a
    // registry failure, never an empty selection.
    if (kscm_enableMonitors() == false) {
        KSLOG_ERROR("The crash monitors could not be enabled");
        clearPluginMonitors();
        return KSCrashInstallErrorCouldNotInitializeCrashState;
    }
    kscm_notifyPostMonitorsEnabled();
    ksruncontext_init(getRunSidecarPathForRunIDCallback);
    // g_reportStoreConfig has the resolved default path, whereas `configuration`
    // still holds whatever the caller passed in (NULL is valid there). Skip
    // when the caller disabled the feature via maxRunSummaryCount <= 0.
    //
    // Install only appends — the retention cap is enforced on the send path,
    // which prunes when it snapshots the runs directory. Intentionally not
    // pruning here so retention policy stays a send-time concern rather than
    // being coupled to launch timing.
    if (g_reportStoreConfig.maxRunSummaryCount > 0) {
        ksruncontext_persistPreviousRunSummary(g_reportStoreConfig.runSummariesPath);
    }
    kscm_notifyPostSystemEnable();

    g_installed = true;
    KSLOG_DEBUG("Installation complete.");

    return KSCrashInstallErrorNone;
}

void kscrash_thwartTailCallOptimisation(void) { KS_THWART_TAIL_CALL_OPTIMISATION }

KSCrashInstallErrorCode kscrash_installForExtensionReporting(const char *const installPath,
                                                             KSCrashMonitorAPI *pluginAPIs, int pluginCount)
{
    KSLOG_DEBUG("Installing crash reporter in extension (reporter-only) mode.");

    if (g_installed) {
        KSLOG_DEBUG("Crash reporter already installed.");
        return KSCrashInstallErrorAlreadyInstalled;
    }
    if (installPath == NULL) {
        KSLOG_ERROR("Invalid parameters: installPath is NULL.");
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
    KSCrashInstallErrorCode pathResult = resolveStoreConfigDefaults(installPath);
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

bool kscrash_addUserReport(const char *report, int reportLength, char *reportIDOut)
{
    return kscrs_addUserReport(report, reportLength, &g_reportStoreConfig, reportIDOut);
}

const KSCrashReportStoreCConfiguration *kscrash_getReportStoreConfiguration(void) { return &g_reportStoreConfig; }

bool kscrash_isInstalled(void) { return g_installed; }

KSTerminationReason kscrash_getPreviousTerminationReason(void)
{
    return ksruncontext_previousRunContext()->terminationReason;
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

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscrash_testcode_setLastRunID(const char *runID)
{
    if (runID != NULL) {
        strlcpy(g_lastRunID, runID, sizeof(g_lastRunID));
    } else {
        g_lastRunID[0] = '\0';
    }
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

const char *kscrash_getRunSummariesPath(void) { return g_reportStoreConfig.runSummariesPath; }

const char *kscrash_getRunSidecarsPath(void) { return g_reportStoreConfig.runSidecarsPath; }

int kscrash_getMaxRunSummaryCount(void) { return g_reportStoreConfig.maxRunSummaryCount; }

const char *kscrash_getLastRunID(void) { return g_lastRunID; }

const char *kscrash_namespaceIdentifier(void) { return KSCRASH_NS_STRING("KSCrash"); }

__attribute__((unused))  // For tests. Declared as extern in TestCase
// ============================================================================
#pragma mark - Testing API -
// ============================================================================

void kscrash_testcode_setMonitors(KSCrashMonitorType monitorTypes)
{
    setMonitors(monitorTypes);
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscrash_testcode_setPluginMonitors(KSCrashMonitorAPI *apis, int count)
{
    setPluginMonitors(apis, count);
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscrash_testcode_clearPluginMonitors(void)
{
    clearPluginMonitors();
}

// The registry stores pointers into g_plugins, so a test that registers its own
// plugins overwrites the tables the live entries point at. Saving and restoring
// the table keeps those entries pointing at what they described before.
__attribute__((unused))  // For tests. Declared as extern in TestCase
void *
kscrash_testcode_savePluginMonitors(void)
{
    size_t size = sizeof(g_plugins) + sizeof(g_pluginCount);
    char *saved = malloc(size);
    if (saved != NULL) {
        memcpy(saved, g_plugins, sizeof(g_plugins));
        memcpy(saved + sizeof(g_plugins), &g_pluginCount, sizeof(g_pluginCount));
    }
    return saved;
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscrash_testcode_restorePluginMonitors(void *saved)
{
    if (saved == NULL) {
        return;
    }
    memcpy(g_plugins, saved, sizeof(g_plugins));
    memcpy(&g_pluginCount, (char *)saved + sizeof(g_plugins), sizeof(g_pluginCount));
    free(saved);
}

