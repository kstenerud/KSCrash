//
//  CrashCallback.m
//  KSCrashSamplesCommon
//
//  Created by Karl Stenerud on 10.08.25.
//

#import "CrashCallback.h"
#import <errno.h>
#import <fcntl.h>
#if defined(__arm64__)
#import <mach/arm/thread_status.h>
#endif
#import <signal.h>
#import <stdint.h>
#import <stdio.h>
#import <sys/ucontext.h>
#import <unistd.h>
#import "KSCrashC.h"

static void (^g_integrationTestWillWriteReportCallback)(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context) =
^void (KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context) {
    // Do nothing by default
};

void integrationTestWillWriteReportCallback(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context) {
    g_integrationTestWillWriteReportCallback(plan, context);
}

void setIntegrationTestWillWriteReportCallback(void (^ _Nonnull implementation)(KSCrash_ExceptionHandlingPlan *_Nonnull const plan, const struct KSCrash_MonitorContext *_Nonnull context)) {
    g_integrationTestWillWriteReportCallback = implementation;
}

static void (^g_integrationTestIsWritingReportCallback)(const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer) =
^void (const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer) {
    // Do nothing by default
};

void integrationTestIsWritingReportCallback(const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer) {
    g_integrationTestIsWritingReportCallback(plan, writer);
}

void setIntegrationTestIsWritingReportCallback(void (^implementation)(const KSCrash_ExceptionHandlingPlan *const plan, const struct KSCrashReportWriter * _Nonnull writer)) {
    g_integrationTestIsWritingReportCallback = implementation;
}

static void (^g_integrationTestDidWriteReportCallback)(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, int64_t reportID) =
^void (const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, int64_t reportID) {
    // Do nothing by default
};

void integrationTestDidWriteReportCallback(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, int64_t reportID) {
    g_integrationTestDidWriteReportCallback(plan, reportID);
}

void setIntegrationTestDidWriteReportCallback(void (^ _Nonnull implementation)(const KSCrash_ExceptionHandlingPlan *const _Nonnull plan, int64_t reportID)) {
    g_integrationTestDidWriteReportCallback = implementation;
}

static void (^g_integrationTestSwiftAsyncTrigger)(void) = ^void(void) {
    printf("No Swift async crash trigger registered\n");
};

void integrationTestSwiftAsyncTrigger(void) { g_integrationTestSwiftAsyncTrigger(); }

void setIntegrationTestSwiftAsyncTrigger(void (^implementation)(void))
{
    g_integrationTestSwiftAsyncTrigger = implementation;
}

int integrationTestIgnoreSIGPIPE(void)
{
    struct sigaction action = { { 0 } };
    action.sa_handler = SIG_IGN;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGPIPE, &action, NULL) != 0) {
        return errno;
    }
    return 0;
}

static int g_postKSCrashSignalMarkerFD = -1;
static struct sigaction g_previousSIGSEGVHandler;

static uint64_t instructionAddressForSignalContext(void *userContext)
{
    const ucontext_t *context = userContext;
#if defined(__arm64__)
    return arm_thread_state64_get_pc(context->uc_mcontext->__ss);
#elif defined(__x86_64__)
    return context->uc_mcontext->__ss.__rip;
#elif defined(__arm__)
    return context->uc_mcontext->__ss.__pc;
#elif defined(__i386__)
    return context->uc_mcontext->__ss.__eip;
#else
    return 0;
#endif
}

static void handlePostKSCrashSIGSEGV(int sigNum, siginfo_t *signalInfo, void *userContext)
{
    // The marker FD is opened before the handler is installed.
    const IntegrationTestSignalMarker marker = { .signalNumber = sigNum,
                                             .signalCode = signalInfo->si_code,
                                             .instructionAddress = instructionAddressForSignalContext(userContext),
                                             .faultAddress = (uintptr_t)signalInfo->si_addr };
    if (g_postKSCrashSignalMarkerFD >= 0) {
        (void)write(g_postKSCrashSignalMarkerFD, &marker, sizeof(marker));
    }

    // Behave like a cooperating crash handler: remove only ourselves and pass
    // the signal to the handler that KSCrash installed before us.
    if (sigaction(sigNum, &g_previousSIGSEGVHandler, NULL) != 0 || raise(sigNum) != 0) {
        _exit(128 + sigNum);
    }
}

int integrationTestInstallPostKSCrashSIGSEGVHandler(const char *markerPath)
{
    const int markerFD = open(markerPath, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (markerFD < 0) {
        return errno;
    }

    g_postKSCrashSignalMarkerFD = markerFD;

    struct sigaction action = { { 0 } };
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    action.sa_sigaction = handlePostKSCrashSIGSEGV;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGSEGV, &action, &g_previousSIGSEGVHandler) != 0) {
        const int error = errno;
        g_postKSCrashSignalMarkerFD = -1;
        close(markerFD);
        return error;
    }
    return 0;
}
