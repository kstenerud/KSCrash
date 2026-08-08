//
//  KSTerminationReason.c
//
//  Created by Alexander Cohen on 2026-03-15.
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

#include "KSTerminationReason.h"

const char *kstermination_reasonToString(KSTerminationReason reason)
{
    switch (reason) {
        case KSTerminationReasonClean:
            return "clean";
        case KSTerminationReasonCrash:
            return "crash";
        case KSTerminationReasonHang:
            return "hang";
        case KSTerminationReasonFirstLaunch:
            return "first_launch";
        case KSTerminationReasonLowBattery:
            return "low_battery";
        case KSTerminationReasonMemoryLimit:
            return "memory_limit";
        case KSTerminationReasonMemoryPressure:
            return "memory_pressure";
        case KSTerminationReasonThermal:
            return "thermal";
        case KSTerminationReasonCPU:
            return "cpu";
        case KSTerminationReasonOSUpgrade:
            return "os_upgrade";
        case KSTerminationReasonAppUpgrade:
            return "app_upgrade";
        case KSTerminationReasonReboot:
            return "reboot";
        case KSTerminationReasonUnexplained:
            return "unexplained";
        case KSTerminationReasonNone:
        default:
            return "none";
    }
}

bool kstermination_producesReport(KSTerminationReason reason)
{
    switch (reason) {
        case KSTerminationReasonCrash:
        case KSTerminationReasonHang:
        case KSTerminationReasonLowBattery:
        case KSTerminationReasonMemoryLimit:
        case KSTerminationReasonMemoryPressure:
        case KSTerminationReasonThermal:
        case KSTerminationReasonCPU:
        case KSTerminationReasonUnexplained:
            return true;
        default:
            return false;
    }
}

