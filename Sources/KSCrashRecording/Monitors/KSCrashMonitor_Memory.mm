//
//  KSCrashMonitor_NSException.m
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
#import "KSCrashMonitor_Memory.h"

#import "KSCrash.h"
#import "KSCrashC.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashAppMemory.h"
#import "KSID.h"
#import "KSStackCursor.h"
#import "KSStackCursor_SelfThread.h"
#import "KSStackCursor_MachineContext.h"
#import "KSCrashReportFields.h"

#import <Foundation/Foundation.h>
#import <mutex>
#import <sys/time.h>

#import "KSLogger.h"

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static volatile bool g_isEnabled = 0;
static volatile bool g_hasPostEnable = 0;

static KSCrash_MonitorContext g_monitorContext;

// Install path for the crash system
static NSURL *g_installURL = nil;

// The memory tracker
@class MemoryTracker;
static MemoryTracker *g_memoryTracker = nil;

// file mapped memory
static std::mutex g_lock [[clang::no_destroy]];
static KSCrash_Memory *g_memory = NULL;

// last memory write from the previous session
static KSCrash_Memory g_previousSessionMemory;
static KSCrashAppMemory *g_previousSessionAppMemory = nil;

// ============================================================================
#pragma mark - Tracking -
// ============================================================================

@interface MemoryTracker : NSObject <KSCrashAppMemoryTrackerDelegate> {
    KSCrashAppMemoryTracker *_tracker;
}
@end

@implementation MemoryTracker

- (instancetype)init
{
    if (self = [super init]) {
        _tracker = [[KSCrashAppMemoryTracker alloc] init];
        _tracker.delegate = self;
        [_tracker start];
    }
}

- (void)dealloc
{
    [_tracker stop];
}

- (KSCrashAppMemory *)memory
{
    _tracker.currentAppMemory;
}

- (void)_updateMappedMemoryFrom:(KSCrashAppMemory *)memory
{
    std::lock_guard<std::mutex> l(g_lock);
    if (!g_memory) {
        return;
    }
    
    struct timeval tp;
    gettimeofday(&tp, NULL);
    int64_t microseconds = ((int64_t)tp.tv_sec) * 1000000 + tp.tv_usec;
    
    *g_memory = (KSCrash_Memory){
        .footprint = memory.footprint,
        .remaining = memory.remaining,
        .limit = memory.limit,
        .pressure = (uint8_t)memory.pressure,
        .level = (uint8_t)memory.level,
        .timestamp = microseconds,
    };
}

- (void)appMemoryTracker:(KSCrashAppMemoryTracker *)tracker memory:(KSCrashAppMemory *)memory changed:(KSCrashAppMemoryTrackerChangeType)changes
{
    if (changes & KSCrashAppMemoryTrackerChangeTypeFootprint) {
        [self _updateMappedMemoryFrom:memory];
    }
    
    if ((changes & KSCrashAppMemoryTrackerChangeTypeLevel) &&
        memory.level >= KSCrashAppMemoryStateCritical) {

        NSString *level = KSCrashAppMemoryStateToString(memory.level).uppercaseString;
        NSString *reason = [NSString stringWithFormat:@"Memory Level Is %@", level];
        
        [[KSCrash sharedInstance] reportUserException:@"Memory Level"
                                               reason:reason
                                             language:@""
                                           lineOfCode:@"0"
                                           stackTrace:@[@"__MEMORY_LEVEL_HIGH___OOM_IS_IMMINENT__"]
                                        logAllThreads:NO
                                     terminateProgram:NO];
    }
    
    if ((changes & KSCrashAppMemoryTrackerChangeTypePressure) &&
        memory.pressure >= KSCrashAppMemoryStateCritical) {

        NSString *pressure = KSCrashAppMemoryStateToString(memory.pressure).uppercaseString;
        NSString *reason = [NSString stringWithFormat:@"Memory Pressure Is %@", pressure];
        
        [[KSCrash sharedInstance] reportUserException:@"Memory Pressure "
                                               reason:reason
                                             language:@""
                                           lineOfCode:@"0"
                                           stackTrace:@[@"__MEMORY_PRESSURE_HIGH___OOM_IS_IMMINENT__"]
                                        logAllThreads:NO
                                     terminateProgram:NO];
    }
}

@end

// ============================================================================
#pragma mark - API -
// ============================================================================

static void ksmemory_write_possible_oom();

static void setEnabled(bool isEnabled)
{
    if (isEnabled != g_isEnabled)
    {
        g_isEnabled = isEnabled;
        if(isEnabled)
        {
            if (g_hasPostEnable) {
                g_memoryTracker = [[MemoryTracker alloc] init];
            }
        }
        else
        {
            g_memoryTracker = nil;
        }
    }
}

static bool isEnabled(void)
{
    return g_isEnabled;
}

static void addContextualInfoToEvent(KSCrash_MonitorContext* eventContext)
{
    if (g_isEnabled)
    {
        // Not sure if I can lock here or not, we might be in an async only state.
        std::lock_guard<std::mutex> l(g_lock);
        if (g_memory) {
            eventContext->AppMemory.footprint = g_memory->footprint;
            eventContext->AppMemory.pressure = g_memory->pressure;
            eventContext->AppMemory.remaining = g_memory->remaining;
            eventContext->AppMemory.limit = g_memory->limit;
            eventContext->AppMemory.level = g_memory->level;
            eventContext->AppMemory.timestamp = g_memory->timestamp;
        }
    }
}

static NSURL *kscm_memory_oom_breacrumb_URL() {
    return [g_installURL URLByAppendingPathComponent:@"Data/oom_breadcrumb_report.json"];
}

static void notifyPostSystemEnable()
{
    g_hasPostEnable = 1;
    
    // here we check to see if the previous run was an OOM
    // if it was, we load up the report created in the previous
    // session and modify it, save it out to the reports location,
    // and let the system run its course.
    if (g_previousSessionAppMemory.isOutOfMemory) {
        NSURL *url = kscm_memory_oom_breacrumb_URL();
        const char *reportContents = kscrash_readReportAtPath(url.path.UTF8String);
        if (reportContents) {
            NSData *data = [NSData dataWithBytes:reportContents length:strlen(reportContents)];
            NSMutableDictionary *json = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers|NSJSONReadingMutableLeaves error:nil] mutableCopy];
            if (json) {
                json[@KSCrashField_System][@KSCrashField_AppMemory] = g_previousSessionAppMemory.serialize;
                json[@KSCrashField_Report][@KSCrashField_Timestamp] = @(g_previousSessionMemory.timestamp);
                json[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashExcType_MemoryTermination] = g_previousSessionAppMemory.serialize;
                json[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashExcType_Mach] = nil;
                json[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashExcType_Signal] = @{
                    @KSCrashField_Signal: @(SIGKILL),
                    @KSCrashField_Name: @"SIGKILL",
                };
                
                data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
                kscrash_addUserReport((const char *)data.bytes, data.length);
            }
            free((void *)reportContents);
        }
    }
    
    // remove the old breadcrumb oom file
    unlink(kscm_memory_oom_breacrumb_URL().path.UTF8String);

    if (g_isEnabled)
    {
        ksmemory_write_possible_oom();
        g_memoryTracker = [[MemoryTracker alloc] init];
    }
}

KSCrashMonitorAPI* kscm_memory_getAPI(void)
{
    static KSCrashMonitorAPI api =
    {
        .setEnabled = setEnabled,
        .isEnabled = isEnabled,
        .addContextualInfoToEvent = addContextualInfoToEvent,
        .notifyPostSystemEnable = notifyPostSystemEnable,
    };
    return &api;
}

static void ksmemory_read(const char* path)
{
    int fd = open(path, O_RDWR, 0644);
    if (fd == -1) {
        unlink(path);
        return;
    }
    
    size_t size = sizeof(KSCrash_Memory);
    void *mem = malloc(size);
    if (!mem) {
        close(fd);
        unlink(path);
        return;
    }
    
    memset(mem, 0, size);
    
    size_t count = read(fd, mem, size);
    if (count != size) {
        close(fd);
        unlink(path);
        free(mem);
        return;
    }
    
    KSCrash_Memory memory = {};
    memcpy(&memory, mem, size);
    g_previousSessionMemory = memory;
    
    g_previousSessionAppMemory = [[KSCrashAppMemory alloc] initWithFootprint:memory.footprint
                                                                   remaining:memory.remaining
                                                                    pressure:(KSCrashAppMemoryState)memory.pressure];
    
    close(fd);
    unlink(path);
    free(mem);
}

static void ksmemory_map(const char* path)
{
    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd == -1) {
        unlink(path);
        return;
    }
    
    size_t size = sizeof(KSCrash_Memory);
    if (lseek(fd, size, SEEK_SET) == -1) {
        close(fd);
        unlink(path);
        return;
    }
    
    if (write(fd, "", 1) == -1) {
        close(fd);
        return;
        unlink(path);
    }
    
    void *ptr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (ptr != MAP_FAILED) {
        g_memory = (KSCrash_Memory *)ptr;
        
        KSCrashAppMemory *memory = g_memoryTracker.memory;
        *g_memory = (KSCrash_Memory){
            .footprint = memory.footprint,
            .remaining = memory.remaining,
            .pressure = (uint8_t)memory.pressure,
            .level = (uint8_t)memory.level,
            .limit = memory.limit,
            .timestamp = 0, // put good time in here
        };
    }
    
    close(fd);
}

static void ksmemory_write_possible_oom()
{
    NSURL *reportURL = kscm_memory_oom_breacrumb_URL();
    const char *reportPath = reportURL.path.UTF8String;
    
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t numThreads = 0;
    kscm_notifyFatalExceptionCaptured(false);
    
    KSMC_NEW_CONTEXT(machineContext);
    ksmc_getContextForThread(ksthread_self(), machineContext, false);
    KSStackCursor stackCursor;
    kssc_initWithMachineContext(&stackCursor, KSSC_MAX_STACK_DEPTH, machineContext);
    
    char eventID[37];
    ksid_generate(eventID);
    
    KSCrash_MonitorContext context;
    memset(&context, 0, sizeof(context));
    context.crashType = KSCrashMonitorTypeMemoryTermination;
    context.eventID = eventID;
    context.registersAreValid = false;
    context.offendingMachineContext = machineContext;
    context.currentSnapshotUserReported = true;
    
    // we don't need all the images, we have no stack
    context.omitBinaryImages = true;
    
    // _reportPath_ only valid within this scope
    context.reportPath = reportPath;

    kscm_handleException(&context);
}

void ksmemory_initialize(const char* installPath)
{
    g_installURL = [NSURL fileURLWithPath:@(installPath)];
    NSURL *memoryURL = [[g_installURL URLByAppendingPathComponent:@"Data"] URLByAppendingPathComponent:@"memory"];
    const char *path = memoryURL.path.UTF8String;
    
    // load up the old data
    ksmemory_read(path);
    
    // map new data
    ksmemory_map(path);
}

bool ksmemory_previous_session_was_terminated_due_to_memory(void)
{
    return g_previousSessionAppMemory.isOutOfMemory;
}
