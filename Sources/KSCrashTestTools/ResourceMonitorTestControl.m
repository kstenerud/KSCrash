//
//  ResourceMonitorTestControl.m
//
//  Created by Alexander Cohen on 2026-11-22.
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

#import "ResourceMonitorTestControl.h"

#import <string.h>

#import "KSCrashMonitor_Resource.h"

static char g_sidecarPath[1024];

static bool testRunSidecarPath(__unused const char *monitorId, char *path, size_t length)
{
    if (g_sidecarPath[0] == '\0') {
        return false;
    }
    return strlcpy(path, g_sidecarPath, length) < length;
}

void resourcetest_arm(const char *sidecarPath)
{
    strlcpy(g_sidecarPath, sidecarPath, sizeof(g_sidecarPath));
    KSCrashMonitorAPI *api = kscm_resource_getAPI();
    api->setEnabled(false, NULL);
    KSCrash_ExceptionHandlerCallbacks callbacks = { .getRunSidecarPath = testRunSidecarPath };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);
}

void resourcetest_disarm(void)
{
    KSCrashMonitorAPI *api = kscm_resource_getAPI();
    api->setEnabled(false, NULL);
    KSCrash_ExceptionHandlerCallbacks callbacks = {};
    api->init(&callbacks, NULL);
    g_sidecarPath[0] = '\0';
}

bool resourcetest_read(const char *sidecarPath, ResourceTestSnapshot *outSnapshot)
{
    KSCrash_ResourceData data = {};
    if (ksresource_readSnapshotFromPath(sidecarPath, &data) != KSCrashSidecarReadOK) {
        return false;
    }
    outSnapshot->batteryLevel = data.batteryLevel;
    outSnapshot->batteryState = data.batteryState;
    outSnapshot->batteryUpdatedAtNs = data.batteryUpdatedAtNs;
    outSnapshot->dataProtectionActive = data.dataProtectionActive;
    outSnapshot->dataProtectionUpdatedAtNs = data.dataProtectionUpdatedAtNs;
    return true;
}
