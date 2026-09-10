//
//  KSCxaThrowSwapper_Tests.mm
//
//  Created by Alexander Cohen on 2025-01-11.
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

// clang-format off
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreserved-macro-identifier"
#import <XCTest/XCTest.h>
#pragma clang diagnostic pop
// clang-format on

#include <dlfcn.h>
#include <errno.h>
#include <mach-o/getsect.h>
#include <mach/mach.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include <atomic>
#include <exception>
#include <stdexcept>
#include <string>
#include <thread>
#include <typeinfo>
#include <utility>
#include <vector>

#include "KSCxaThrowSwapper.h"
#include "KSPlatformSpecificDefines.h"
#include "KSSystemCapabilities.h"

#pragma mark - Test Exception Classes

class TestException : public std::exception
{
   public:
    TestException() = default;
    TestException(const TestException &) = default;
    TestException &operator=(const TestException &) = default;
    ~TestException() override;
    const char *what() const noexcept override { return "Test exception"; }
};

// Out-of-line destructor to anchor the vtable
TestException::~TestException() = default;

#pragma mark - Handler State

static std::atomic<int> g_handlerCallCount { 0 };
static std::atomic<void *> g_lastThrownException { nullptr };
static std::atomic<std::type_info *> g_lastTypeInfo { nullptr };

static void testHandler(void *thrown_exception, std::type_info *tinfo, void (*dest)(void *) __unused)
{
    g_handlerCallCount.fetch_add(1, std::memory_order_relaxed);
    g_lastThrownException.store(thrown_exception, std::memory_order_relaxed);
    g_lastTypeInfo.store(tinfo, std::memory_order_relaxed);
}

static void resetHandlerState()
{
    g_handlerCallCount.store(0, std::memory_order_relaxed);
    g_lastThrownException.store(nullptr, std::memory_order_relaxed);
    g_lastTypeInfo.store(nullptr, std::memory_order_relaxed);
}

#pragma mark - Memory Protection Helpers

// Deliberately not ksmacho_getSectionProtection, so the code under test is not its own oracle.
static vm_prot_t protectionOfPage(uintptr_t page)
{
    vm_address_t regionAddress = (vm_address_t)page;
    vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    memory_object_name_t object;
    kern_return_t kr = vm_region_64(mach_task_self(), &regionAddress, &regionSize, VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_64_t)&info, &count, &object);
    return kr == KERN_SUCCESS ? info.protection : VM_PROT_NONE;
}

static const mach_header_t *headerOfThisImage(void)
{
    Dl_info info;
    if (dladdr((const void *)&testHandler, &info) == 0) {
        return NULL;
    }
    return (const mach_header_t *)info.dli_fbase;
}

/// __DATA_CONST of the image containing this test code, which holds its __cxa_throw binding.
static bool dataConstSegmentOfThisImage(uintptr_t *outStart, size_t *outSize)
{
    const mach_header_t *header = headerOfThisImage();
    if (header == NULL) {
        return false;
    }
    unsigned long size = 0;
    uint8_t *start = getsegmentdata(header, SEG_DATA_CONST, &size);
    if (start == NULL || size == 0) {
        return false;
    }
    *outStart = (uintptr_t)start;
    *outSize = (size_t)size;
    return true;
}

/// Copy of this image's __DATA_CONST,__got entries, to detect whether the swapper rewrote one.
static std::vector<void *> dataConstGotEntriesOfThisImage(void)
{
    const mach_header_t *header = headerOfThisImage();
    if (header == NULL) {
        return {};
    }
    unsigned long size = 0;
    // Cast via void* to avoid alignment warnings
    void *sectionStart = getsectiondata(header, SEG_DATA_CONST, "__got", &size);
    if (sectionStart == NULL) {
        return {};
    }
    void **entries = (void **)sectionStart;
    return std::vector<void *>(entries, entries + size / sizeof(void *));
}

static size_t countChangedEntries(const std::vector<void *> &before, const std::vector<void *> &after)
{
    size_t changed = 0;
    for (size_t i = 0; i < before.size() && i < after.size(); i++) {
        if (before[i] != after[i]) {
            changed++;
        }
    }
    return changed;
}

static size_t countPagesWithProtection(uintptr_t start, size_t size, vm_prot_t protection, bool present)
{
    size_t pageSize = (size_t)getpagesize();
    size_t matched = 0;
    for (uintptr_t page = start & ~(pageSize - 1); page < start + size; page += pageSize) {
        bool hasProtection = (protectionOfPage(page) & protection) != 0;
        if (hasProtection == present) {
            matched++;
        }
    }
    return matched;
}

static int posixProtection(vm_prot_t protection)
{
    int result = PROT_NONE;
    if (protection & VM_PROT_READ) {
        result |= PROT_READ;
    }
    if (protection & VM_PROT_WRITE) {
        result |= PROT_WRITE;
    }
    if (protection & VM_PROT_EXECUTE) {
        result |= PROT_EXEC;
    }
    return result;
}

#pragma mark - Test Class

@interface KSCxaThrowSwapper_Tests : XCTestCase
@end

@implementation KSCxaThrowSwapper_Tests

- (void)setUp
{
    [super setUp];
    resetHandlerState();
}

- (void)tearDown
{
    ksct_swapReset();
    [super tearDown];
}

#pragma mark - Basic Functionality Tests

/// Test that swap returns success
- (void)testSwapReturnsSuccess
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    int result = ksct_swap(testHandler);
    XCTAssertEqual(result, 0, @"ksct_swap should return 0 on success");
}

/// Test that handler is called when exception is thrown
- (void)testHandlerIsCalledOnThrow
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    ksct_swap(testHandler);

    XCTAssertEqual(g_handlerCallCount.load(), 0, @"Handler should not be called yet");

    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }

    XCTAssertEqual(g_handlerCallCount.load(), 1, @"Handler should be called once after throw");
}

/// Test that handler receives correct type info
- (void)testHandlerReceivesTypeInfo
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    ksct_swap(testHandler);

    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }

    std::type_info *capturedType = g_lastTypeInfo.load();
    XCTAssertNotEqual(capturedType, nullptr, @"Type info should be captured");
    XCTAssertTrue(*capturedType == typeid(TestException), @"Type info should match TestException");
}

/// Test that exceptions still work correctly after swap
- (void)testExceptionStillWorksAfterSwap
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    ksct_swap(testHandler);

    bool exceptionCaught = false;
    try {
        throw std::runtime_error("test error");
    } catch (const std::runtime_error &e) {
        exceptionCaught = true;
        XCTAssertTrue(strcmp(e.what(), "test error") == 0, @"Exception message should be preserved");
    }

    XCTAssertTrue(exceptionCaught, @"Exception should be caught normally");
}

#pragma mark - Reset Tests

/// Test that reset can be called without prior swap
- (void)testResetWithoutSwap
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    // Should not crash
    ksct_swapReset();
}

/// Test that handler is not called after reset
- (void)testHandlerNotCalledAfterReset
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    ksct_swap(testHandler);

    // Verify handler works
    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 1, @"Handler should be called once");

    // Reset
    ksct_swapReset();
    resetHandlerState();

    // Throw again - handler should not be called
    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }

    XCTAssertEqual(g_handlerCallCount.load(), 0, @"Handler should not be called after reset");
}

/// Test that exceptions still work after reset
- (void)testExceptionsWorkAfterReset
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    ksct_swap(testHandler);
    ksct_swapReset();

    bool exceptionCaught = false;
    try {
        throw std::runtime_error("after reset");
    } catch (const std::runtime_error &e) {
        exceptionCaught = true;
        XCTAssertTrue(strcmp(e.what(), "after reset") == 0, @"Exception message should be preserved");
    }

    XCTAssertTrue(exceptionCaught, @"Exception should be caught after reset");
}

#pragma mark - Multiple Swap Tests

/// Test that calling swap multiple times works correctly
- (void)testMultipleSwapCalls
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    // First swap
    int result1 = ksct_swap(testHandler);
    XCTAssertEqual(result1, 0);

    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 1);

    // Second swap (should reset first, then rebind)
    resetHandlerState();
    int result2 = ksct_swap(testHandler);
    XCTAssertEqual(result2, 0);

    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 1, @"Handler should be called once after re-swap");
}

/// Test swap-reset-swap cycle
- (void)testSwapResetSwapCycle
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    for (int cycle = 0; cycle < 3; cycle++) {
        resetHandlerState();

        ksct_swap(testHandler);

        try {
            throw TestException();
        } catch (const TestException &e) {
            (void)e;
        }
        XCTAssertEqual(g_handlerCallCount.load(), 1, @"Handler should be called in cycle %d", cycle);

        ksct_swapReset();
        resetHandlerState();

        try {
            throw TestException();
        } catch (const TestException &e) {
            (void)e;
        }
        XCTAssertEqual(g_handlerCallCount.load(), 0, @"Handler should not be called after reset in cycle %d", cycle);
    }
}

#pragma mark - Multiple Exception Types

/// Test handler is called for different exception types
- (void)testDifferentExceptionTypes
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    ksct_swap(testHandler);

    // Test with custom exception
    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 1);

    // Test with runtime_error
    try {
        throw std::runtime_error("test");
    } catch (const std::runtime_error &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 2);

    // Test with int
    try {
        throw 42;
    } catch (int e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 3);

    // Test with string
    try {
        throw std::string("test string");
    } catch (const std::string &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 4);
}

#pragma mark - Concurrency Stress Tests

/// Stress test: multiple threads throwing exceptions concurrently.
/// This exercises findAddress under concurrent load. Combined with TSan,
/// this would catch data races in the address lookup.
- (void)testConcurrentExceptionThrows
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    ksct_swap(testHandler);

    const int numThreads = 8;
    const int throwsPerThread = 100;
    std::atomic<int> successCount { 0 };
    std::atomic<int> failureCount { 0 };

    std::vector<std::thread> threads;
    threads.reserve(numThreads);

    for (int t = 0; t < numThreads; t++) {
        threads.emplace_back([&successCount, &failureCount]() {
            for (int i = 0; i < throwsPerThread; i++) {
                try {
                    throw std::runtime_error("concurrent test");
                } catch (const std::runtime_error &e) {
                    if (strcmp(e.what(), "concurrent test") == 0) {
                        successCount.fetch_add(1, std::memory_order_relaxed);
                    } else {
                        failureCount.fetch_add(1, std::memory_order_relaxed);
                    }
                } catch (...) {
                    failureCount.fetch_add(1, std::memory_order_relaxed);
                }
            }
        });
    }

    for (auto &thread : threads) {
        thread.join();
    }

    int expectedThrows = numThreads * throwsPerThread;
    XCTAssertEqual(successCount.load(), expectedThrows, @"All exceptions should be caught successfully");
    XCTAssertEqual(failureCount.load(), 0, @"No exceptions should fail");
    XCTAssertEqual(g_handlerCallCount.load(), expectedThrows, @"Handler should be called for each throw");
}

/// Stress test: concurrent swap/reset cycles while throwing exceptions.
/// This tests the thread safety of the swap/reset mechanism itself.
- (void)testConcurrentSwapResetWithThrows
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    const int numCycles = 20;
    const int numThrowThreads = 4;
    const int throwsPerCycle = 100;
    const int resetIterations = 5;

    for (int cycle = 0; cycle < numCycles; cycle++) {
        resetHandlerState();
        ksct_swap(testHandler);

        std::atomic<bool> start { false };
        std::atomic<int> readyCount { 0 };
        std::atomic<int> successCount { 0 };
        std::vector<std::thread> threads;
        threads.reserve(numThrowThreads);

        for (int t = 0; t < numThrowThreads; t++) {
            threads.emplace_back([&start, &readyCount, &successCount]() {
                readyCount.fetch_add(1, std::memory_order_relaxed);
                while (!start.load(std::memory_order_acquire)) {
                    std::this_thread::yield();
                }
                for (int i = 0; i < throwsPerCycle; i++) {
                    try {
                        throw TestException();
                    } catch (const TestException &) {
                        successCount.fetch_add(1, std::memory_order_relaxed);
                    } catch (...) {
                        // Unexpected exception type
                    }
                    if ((i & 0xF) == 0) {
                        std::this_thread::yield();
                    }
                }
            });
        }

        while (readyCount.load(std::memory_order_acquire) < numThrowThreads) {
            std::this_thread::yield();
        }
        start.store(true, std::memory_order_release);

        for (int i = 0; i < resetIterations; i++) {
            ksct_swapReset();
            ksct_swap(testHandler);
        }

        for (auto &thread : threads) {
            thread.join();
        }

        int expectedThrows = numThrowThreads * throwsPerCycle;
        XCTAssertEqual(successCount.load(), expectedThrows, @"All exceptions should be caught in cycle %d", cycle);

        ksct_swapReset();
    }
}

#pragma mark - Memory Protection Tests

/// Makes this image's __DATA_CONST writable; a teardown block restores each page's original protection.
- (void)makeDataConstOfThisImageWritable:(uintptr_t)start size:(size_t)size
{
    size_t pageSize = (size_t)getpagesize();
    uintptr_t pageStart = start & ~(pageSize - 1);
    std::vector<std::pair<uintptr_t, vm_prot_t>> originalProtections;
    for (uintptr_t page = pageStart; page < start + size; page += pageSize) {
        originalProtections.emplace_back(page, protectionOfPage(page));
    }
    [self addTeardownBlock:^{
        for (const auto &pageAndProtection : originalProtections) {
            mprotect((void *)pageAndProtection.first, pageSize, posixProtection(pageAndProtection.second));
        }
    }];
    XCTAssertEqual(mprotect((void *)pageStart, (start - pageStart) + size, PROT_READ | PROT_WRITE), 0,
                   @"Precondition: could not make __DATA_CONST writable: %s", strerror(errno));
}

/// A __DATA_CONST page that is writable when the swapper runs must stay writable after swap and reset.
- (void)testSwapKeepsWritableDataConstWritable
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    uintptr_t start = 0;
    size_t size = 0;
    XCTSkipUnless(dataConstSegmentOfThisImage(&start, &size), @"Test image has no __DATA_CONST segment");
    [self makeDataConstOfThisImageWritable:start size:size];

    std::vector<void *> gotBeforeSwap = dataConstGotEntriesOfThisImage();
    ksct_swap(testHandler);
    XCTSkipIf(countChangedEntries(gotBeforeSwap, dataConstGotEntriesOfThisImage()) == 0,
              @"__cxa_throw of the test image is not bound in __DATA_CONST on this platform");
    XCTAssertEqual(countPagesWithProtection(start, size, VM_PROT_WRITE, false), 0UL,
                   @"ksct_swap must not make a writable __DATA_CONST page read-only");

    ksct_swapReset();
    XCTAssertEqual(countPagesWithProtection(start, size, VM_PROT_WRITE, false), 0UL,
                   @"ksct_swapReset must not make a writable __DATA_CONST page read-only");
}

/// A read-only __DATA_CONST page must come back read-only after swap and reset.
- (void)testSwapKeepsReadOnlyDataConstReadOnly
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    uintptr_t start = 0;
    size_t size = 0;
    XCTSkipUnless(dataConstSegmentOfThisImage(&start, &size), @"Test image has no __DATA_CONST segment");
    XCTSkipIf(countPagesWithProtection(start, size, VM_PROT_WRITE, true) != 0,
              @"__DATA_CONST of the test image is writable on this platform");

    std::vector<void *> gotBeforeSwap = dataConstGotEntriesOfThisImage();
    ksct_swap(testHandler);
    XCTSkipIf(countChangedEntries(gotBeforeSwap, dataConstGotEntriesOfThisImage()) == 0,
              @"__cxa_throw of the test image is not bound in __DATA_CONST on this platform");
    XCTAssertEqual(countPagesWithProtection(start, size, VM_PROT_WRITE, true), 0UL,
                   @"ksct_swap must not leave a read-only __DATA_CONST page writable");

    ksct_swapReset();
    XCTAssertEqual(countPagesWithProtection(start, size, VM_PROT_WRITE, true), 0UL,
                   @"ksct_swapReset must not leave a read-only __DATA_CONST page writable");
}

#pragma mark - Image Loading Tests

/// Loads Metal after the swap. On the iOS 26.5 simulator this maps MetalSerializer.framework, whose
/// unprotected __DATA_CONST page the swapper used to turn read-only, crashing map_images_nolock.
- (void)testSwapDoesNotBreakImagesLoadedLater
{
    XCTSkipIf(KSCRASH_HAS_SANITIZER, @"Sanitizers conflict with __cxa_throw swapper");

    ksct_swap(testHandler);

    void *metal = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOW);
    XCTSkipIf(metal == NULL, @"Metal is not available on this platform");
    typedef CFTypeRef (*CreateSystemDefaultDevice)(void);
    CreateSystemDefaultDevice createDevice = (CreateSystemDefaultDevice)dlsym(metal, "MTLCreateSystemDefaultDevice");
    XCTSkipIf(createDevice == NULL, @"MTLCreateSystemDefaultDevice is not available on this platform");

    CFTypeRef device = createDevice();
    if (device != NULL) {
        CFRelease(device);
    }

    // Only count this test's throw; images loaded by Metal may throw internally.
    resetHandlerState();
    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 1, @"Handler should still be called after loading more images");
}

@end
