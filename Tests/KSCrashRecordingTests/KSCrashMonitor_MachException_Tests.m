//
//  KSCrashMonitor_MachException_Tests.m
//
//  Created by Alexander Cohen on 2026-10-03.
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

#import <XCTest/XCTest.h>

#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_MachException.h"
#import "KSDebug.h"
#import "KSSystemCapabilities.h"

#if KSCRASH_HAS_MACH
#import <mach/mach.h>
#import <signal.h>
#import <stdatomic.h>
#import <sys/sysctl.h>
#import <sys/wait.h>
#import <unistd.h>

typedef struct {
    exception_mask_t masks[EXC_TYPES_COUNT];
    mach_port_t ports[EXC_TYPES_COUNT];
    exception_behavior_t behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t flavors[EXC_TYPES_COUNT];
    mach_msg_type_number_t count;
} ExceptionPorts;

static const exception_mask_t kMonitoredExceptions =
    EXC_MASK_BAD_ACCESS | EXC_MASK_BAD_INSTRUCTION | EXC_MASK_ARITHMETIC | EXC_MASK_SOFTWARE | EXC_MASK_BREAKPOINT;

static kern_return_t getExceptionPorts(ExceptionPorts *ports)
{
    *ports = (ExceptionPorts) { .count = EXC_TYPES_COUNT };
    return task_get_exception_ports(mach_task_self(), kMonitoredExceptions, ports->masks, &ports->count, ports->ports,
                                    ports->behaviors, ports->flavors);
}

static bool isTranslated(void)
{
    int translated = 0;
    size_t size = sizeof(translated);
    return sysctlbyname("sysctl.proc_translated", &translated, &size, NULL, 0) == 0 && translated == 1;
}

// The monitor installs once per process and stays installed; the suite installs it once and hands
// the runner's own ports back when it is done.
static bool g_installAttempted;
static bool g_portsInstalled;
static ExceptionPorts g_runnerPorts;

// Every exception the handler takes on is counted and then dropped (shouldExitImmediately), so a
// handler that wrongly took one on fails an assertion instead of writing a report.
static atomic_int g_notifyCount;
static KSCrash_MonitorContext g_context;

static KSCrash_MonitorContext *countingNotify(__unused thread_t offendingThread,
                                              KSCrash_ExceptionHandlingRequirements requirements)
{
    atomic_fetch_add(&g_notifyCount, 1);
    memset(&g_context, 0, sizeof(g_context));
    g_context.requirements = requirements;
    g_context.requirements.shouldExitImmediately = true;
    return &g_context;
}
#endif

@interface KSCrashMonitor_MachException_Tests : XCTestCase
@end

@implementation KSCrashMonitor_MachException_Tests

#if KSCRASH_HAS_MACH

+ (void)setUp
{
    [super setUp];
    // Installing would replace a debugger's exception ports.
    if (g_installAttempted || ksdebug_isBeingTraced()) {
        return;
    }
    g_installAttempted = true;
    getExceptionPorts(&g_runnerPorts);
    static KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = countingNotify };
    KSCrashMonitorAPI *api = kscm_machexception_getAPI();
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);
    g_portsInstalled = true;
}

+ (void)tearDown
{
    if (g_portsInstalled) {
        kscm_machexception_getAPI()->setEnabled(false, NULL);
        // Disabling the monitor leaves its ports in place, so hand the runner's back. Clearing a
        // port is not a violation under the restrictions: only a valid port is checked.
        task_set_exception_ports(mach_task_self(), kMonitoredExceptions, MACH_PORT_NULL, EXCEPTION_DEFAULT,
                                 THREAD_STATE_NONE);
        for (mach_msg_type_number_t i = 0; i < g_runnerPorts.count; i++) {
            task_set_exception_ports(mach_task_self(), g_runnerPorts.masks[i], g_runnerPorts.ports[i],
                                     g_runnerPorts.behaviors[i], g_runnerPorts.flavors[i]);
        }
        g_portsInstalled = false;
    }
    [super tearDown];
}

- (void)setUp
{
    [super setUp];
    if (!g_portsInstalled) {
        XCTSkip(@"The Mach monitor installs once per process (and not under a debugger); it already ran here");
    }
}

// A process with Enhanced Security's additional runtime platform restrictions is killed with
// EXC_GUARD (SET_EXCEPTION_BEHAVIOR) the moment it sets an exception port whose behavior hands the
// receiver a task or thread port, so the monitor must register an identity-protected one. Rosetta
// refuses that behavior and does not enforce the restriction, so there it falls back to the classic one.
- (void)testInstallsWithAnIdentityProtectedBehavior
{
    ExceptionPorts installed;
    XCTAssertEqual(getExceptionPorts(&installed), KERN_SUCCESS);
    const uint32_t expected = (uint32_t)(isTranslated() ? EXCEPTION_DEFAULT : EXCEPTION_IDENTITY_PROTECTED);
    XCTAssertGreaterThan(installed.count, 0u);
    for (mach_msg_type_number_t i = 0; i < installed.count; i++) {
        XCTAssertTrue(MACH_PORT_VALID(installed.ports[i]), @"mask 0x%x has no handler", installed.masks[i]);
        const uint32_t behavior = (uint32_t)installed.behaviors[i];
        XCTAssertEqual(behavior & ~MACH_EXCEPTION_MASK, expected, @"mask 0x%x", installed.masks[i]);
        XCTAssertTrue(behavior & MACH_EXCEPTION_CODES, @"mask 0x%x", installed.masks[i]);
    }
}

#if !TARGET_OS_TV && !TARGET_OS_WATCH
// A child inherits the task's exception ports, so its exceptions arrive at this process's handler.
// They are not this process's crashes: the handler must decline them and stay installed.
- (void)testDeclinesExceptionsFromAChildProcess
{
    const int notifiesBefore = atomic_load(&g_notifyCount);
    pid_t child = fork();
    if (child == 0) {
        // Default actions, so a sanitizer's handler in the child does not report the fault the test means.
        signal(SIGSEGV, SIG_DFL);
        signal(SIGBUS, SIG_DFL);
        *(volatile int *)0x42 = 1;
        _exit(0);
    }
    XCTAssertGreaterThan(child, 0);
    int status = 0;
    XCTAssertEqual(waitpid(child, &status, 0), child);

    XCTAssertEqual(atomic_load(&g_notifyCount), notifiesBefore, @"The child's exception was handled as ours");
    ExceptionPorts after;
    XCTAssertEqual(getExceptionPorts(&after), KERN_SUCCESS);
    for (mach_msg_type_number_t i = 0; i < after.count; i++) {
        XCTAssertTrue(MACH_PORT_VALID(after.ports[i]), @"mask 0x%x lost its handler", after.masks[i]);
    }
}
#endif

#endif

@end
