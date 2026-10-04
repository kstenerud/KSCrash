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

#import "KSCrashMonitor_MachException.h"
#import "KSDebug.h"
#import "KSSystemCapabilities.h"

#if KSCRASH_HAS_MACH
#import <mach/mach.h>

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
#endif

@interface KSCrashMonitor_MachException_Tests : XCTestCase
@end

@implementation KSCrashMonitor_MachException_Tests

#if KSCRASH_HAS_MACH

// A process with Enhanced Security's additional runtime platform restrictions is killed with
// EXC_GUARD (SET_EXCEPTION_BEHAVIOR) the moment it sets an exception port whose behavior hands
// the receiver a task or thread port, so the monitor must register an identity-protected one.
- (void)testInstallsWithAnIdentityProtectedBehavior
{
    if (ksdebug_isBeingTraced()) {
        XCTSkip(@"Installing would replace the debugger's exception ports");
    }

    ExceptionPorts original;
    XCTAssertEqual(getExceptionPorts(&original), KERN_SUCCESS);

    KSCrashMonitorAPI *api = kscm_machexception_getAPI();
    api->setEnabled(true, NULL);
    ExceptionPorts installed;
    kern_return_t kr = getExceptionPorts(&installed);
    api->setEnabled(false, NULL);

    // Disabling the monitor leaves its ports in place, so hand the runner's back. Clearing a
    // port is not a violation under the restrictions: only a valid port is checked.
    task_set_exception_ports(mach_task_self(), kMonitoredExceptions, MACH_PORT_NULL, EXCEPTION_DEFAULT,
                             THREAD_STATE_NONE);
    for (mach_msg_type_number_t i = 0; i < original.count; i++) {
        task_set_exception_ports(mach_task_self(), original.masks[i], original.ports[i], original.behaviors[i],
                                 original.flavors[i]);
    }

    XCTAssertEqual(kr, KERN_SUCCESS);
    XCTAssertGreaterThan(installed.count, 0u);
    for (mach_msg_type_number_t i = 0; i < installed.count; i++) {
        XCTAssertTrue(MACH_PORT_VALID(installed.ports[i]), @"mask 0x%x has no handler", installed.masks[i]);
        const uint32_t behavior = (uint32_t)installed.behaviors[i];
        XCTAssertEqual(behavior & ~MACH_EXCEPTION_MASK, (uint32_t)EXCEPTION_IDENTITY_PROTECTED, @"mask 0x%x",
                       installed.masks[i]);
        XCTAssertTrue(behavior & MACH_EXCEPTION_CODES, @"mask 0x%x", installed.masks[i]);
    }
}

#endif

@end
