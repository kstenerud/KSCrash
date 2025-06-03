//
//  KSJailbreak.h
//
//  Created by Karl Stenerud on 10.02.21.
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
//
// Robust Enough Jailbreak Detection
// ---------------------------------
//
// Perfect jailbreak detection, like perfect copy protection, is a fool's errand.
// But perfection isn't necessary for our purposes. We just need to make it tricky enough
// that only a complicated per-app targeted tweak would work. Once an app gets popular
// enough to warrant the time and effort of a targeted tweak, they'll need custom
// jailbreak detection code anyway for the inevitable cat-and-mouse game.
//
// This code operates on the following anti-anti-jailbreak-detection principles:
//
// - Functions can be patched by a general tweak, but syscalls cannot.
// - "environ" is a global variable, which cannot easily be pre-manipulated without
//   potential breakage elsewhere.
//
// We check the following things:
//
// - Can we create a file in /tmp? (/tmp has perms 777, but sandboxed apps can't see it)
// - Does Cydia's MobileSubstrate library exist? (used for tweaks and cracks)
// - Does /etc/apt exist? (Debian's apt is used for non-app-store app distribution)
// - Does the ENV contain an "insert libraries" directive? (used to override functions)
//
// To guard against function overrides, we use syscalls for some of the checks, with a
// graceful fallback to libc functions if we're on an unknown architecture. We also
// stick to very basic and old syscalls that have remained stable for decades.
//

#ifndef HDR_KSJailbreak_h
#define HDR_KSJailbreak_h

#include <dirent.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <TargetConditionals.h>

// The global environ variable must be imported this way.
// See: https://opensource.apple.com/source/Libc/Libc-1439.40.11/man/FreeBSD/environ.7
extern char **environ;

static inline bool ksj_local_is_insert_libraries_env_var(const char* str) {
    if (str == NULL) {
        return false;
    }

    // DYLD_INSERT_LIBRARIES lets you override functions by loading other libraries first.
    // This is a common technique used for defeating detection.
    // See: https://opensource.apple.com/source/dyld/dyld-832.7.3/doc/man/man1/dyld.1
    const char insert[] = "DYLD_INSERT_LIBRARIES";
    if (strlen(str) < sizeof(insert)) {
        return false;
    }
    return __builtin_memcmp(str, insert, sizeof(insert)) == 0;
}

// Note: The following are written as macros to force them always inline so that there
//       are no function calls (which could be patched out). There's enough repetition
//       going on that the compiler might refuse to inline if these were functions.

// Reminder: Always follow proper macro hygene to prevent unwanted side effects:
// - Surround macros in a do { ... } while(0) construct to prevent leakage.
// - Surround parameters in parentheses when accessing them.
// - Do not access a parameter more than once.
// - Make local copies of input parameters to help enforce their types.
// - Use pointers for output parameters, with labels that identify them as such.
// - Beware of global consts or defines bleeding through.

#if TARGET_CPU_ARM64 && !TARGET_OS_OSX
#define KSCRASH_HAS_CUSTOM_SYSCALL 1

// ARM64 3-parameter syscall
// Writes -1 to *(pResult) on failure, or the actual result on success.
//
// Implementation Details:
// - Syscall# is in x16, params in x0, x1, x2, and return in x0.
// - Carry bit is cleared on success, set on failure (we copy the carry bit to x3).
// - We must also inform the compiler that memory and condition codes may get clobbered.
#define ksj_syscall3(call_num, param0, param1, param2, pResult) do { \
    register uintptr_t call asm("x16") = (uintptr_t)(call_num); \
    register uintptr_t p0 asm("x0") = (uintptr_t)(param0); \
    register uintptr_t p1 asm("x1") = (uintptr_t)(param1); \
    register uintptr_t p2 asm("x2") = (uintptr_t)(param2); \
    register uintptr_t carry_bit asm("x3") = 0; \
    asm volatile("svc #0x80\n" \
                 "mov x3, #0\n" \
                 "adc x3, x3, x3\n" \
                 : "=r"(carry_bit), "=r"(p0),"=r"(p1) \
                 : "r"(p0), "r"(p1), "r"(p2), "r"(call), "r"(carry_bit) \
                 : "memory", "cc"); \
    if(carry_bit == 1) { \
        *(pResult) = -1; \
    } else {\
        *(pResult) = (int)p0; \
    } \
} while(0)

#elif TARGET_CPU_X86_64 && defined(__GCC_ASM_FLAG_OUTPUTS__) && !TARGET_OS_OSX
#define KSCRASH_HAS_CUSTOM_SYSCALL 1

// X86_64 3-parameter syscall
// Writes -1 to *(pResult) on failure, or the actual result on success.
//
// Implementation Details:
// - Syscall# is in RAX, params in RDI, RSI, RDX, and return in RAX.
// - Carry bit is cleared on success, set on failure.
// - We must also inform the compiler that memory, rcx, r11 may get clobbered.
// The "=@ccc" constraint requires __GCC_ASM_FLAG_OUTPUTS__, not available in Xcode 10
// https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html#index-asm-flag-output-operands
#define ksj_syscall3(call_num, param0, param1, param2, pResult) do { \
    register uintptr_t rax = (uintptr_t)(call_num) | (2<<24); \
    register uintptr_t p0 = (uintptr_t)(param0); \
    register uintptr_t p1 = (uintptr_t)(param1); \
    register uintptr_t p2 = (uintptr_t)(param2); \
    register uintptr_t carry_bit = 0; \
    asm volatile( \
        "syscall" \
        : "=@ccc"(carry_bit), "+a"(rax) \
        : "D" (p0), "S" (p1), "d" (p2) \
        : "memory", "rcx", "r11"); \
    if(carry_bit == 1) { \
        *(pResult) = -1; \
    } else { \
        *(pResult) = (int)rax; \
    } \
} while(0)

#else
#define KSCRASH_HAS_CUSTOM_SYSCALL 0

// Unhandled architecture.
// We fall back to the libc functions in this case, mimicing the syscall-like API.
// See definitions below.

#endif /* TARGET_CPU_XYZ */


#if KSCRASH_HAS_CUSTOM_SYSCALL

// See: https://opensource.apple.com/source/xnu/xnu-7195.81.3/bsd/kern/syscalls.master
#define KSCRASH_SYSCALL_OPEN 5
#define ksj_syscall_open(path, flags, mode, pResult) ksj_syscall3(KSCRASH_SYSCALL_OPEN, (uintptr_t)path, flags, mode, pResult)

#else

#define ksj_syscall_open(path, flags, mode, pResult) do {*(pResult) = open(path, flags, mode);} while(0)

#endif /* KSCRASH_HAS_CUSTOM_SYSCALL */


/**
 * Get this device's jailbreak status.
 * Stores nonzero in *(pIsJailbroken) if the device is jailbroken, 0 otherwise.
 * Note: Implemented as a macro to force it inline always.
 */
#if !TARGET_OS_SIMULATOR && !TARGET_OS_OSX && KSCRASH_HAS_SYSCALL
#define get_jailbreak_status(pIsJailbroken) do { \
    int fd = 0; \
 \
    bool tmp_file_is_accessible = false; \
    bool mobile_substrate_exists = false; \
    bool etc_apt_exists = false; \
    bool has_insert_libraries = false; \
 \
    const char* test_write_file = "/tmp/bugsnag-check.txt"; \
    remove(test_write_file); \
    ksj_syscall_open(test_write_file, O_CREAT, 0644, &fd); \
    if(fd > 0) { \
        close(fd); \
        tmp_file_is_accessible = true; \
    } else { \
        ksj_syscall_open(test_write_file, O_RDONLY, 0, &fd); \
        if(fd > 0) { \
            close(fd); \
            tmp_file_is_accessible = true; \
        } \
    } \
    remove(test_write_file); \
 \
    const char* mobile_substrate_path = "/Library/MobileSubstrate/MobileSubstrate.dylib"; \
    ksj_syscall_open(mobile_substrate_path, O_RDONLY, 0, &fd); \
    if(fd > 0) { \
        close(fd); \
        mobile_substrate_exists = true; \
    } \
 \
    const char* etc_apt_path = "/etc/apt"; \
    DIR *dirp = opendir(etc_apt_path); \
    if(dirp) { \
        etc_apt_exists = true; \
        closedir(dirp); \
    } \
 \
    for(int i = 0; environ[i] != NULL; i++) { \
        if(ksj_local_is_insert_libraries_env_var(environ[i])) { \
            has_insert_libraries = true; \
            break; \
        } \
    } \
 \
    *(pIsJailbroken) = tmp_file_is_accessible || \
                       mobile_substrate_exists || \
                       etc_apt_exists || \
                       has_insert_libraries; \
} while(0)

#else

// "/tmp" is accessible on the simulator, which makes the JB test come back positive, so
// report false on the simulator.
#define get_jailbreak_status(pIsJailbroken) do { *(pIsJailbroken) = 0; } while(0)

#endif /* !TARGET_OS_SIMULATOR */


#endif /* HDR_KSJailbreak_h */
