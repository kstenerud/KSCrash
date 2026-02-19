#!/usr/bin/env python3
#
#  Copyright (c) 2025 Karl Stenerud. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall remain in place
# in this source code.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

### Reads a directory tree containing C/C++/ObjC source files and generates a
### namespacing header for all publicly accessible symbols


import clang.cindex
from pathlib import Path
import os
import re
import sys


## ----------------------------------------------------------------------------
## Configuration
## ----------------------------------------------------------------------------

# As more edge cases crop up, you may need to add to these.
# Clang is pretty good at finding things, but not perfect.
#
# Please keep the lists alphabetically sorted to play nice with source control.

# Manually added symbols because clang.cindex misses them
ALWAYS_ADDED_SYMBOLS = [
                        "i_kslog_logObjC",
                        "i_kslog_logObjCBasic",
                        "KSCrashAlertViewProcess",
                        "KSCrashAppMemory",
                        "KSCrashAppMemoryTrackerDelegate",
                        "KSCrashMailProcess",
                       ]

# Ignore anything in an `NS_SWIFT_NAME()` macro that matches any of these:
SWIFT_NAME_IGNORED = [
                        re.compile(".*\\).*"),
                        re.compile(".*\\..*"),
                        re.compile("[^A-Z]"),
                     ]

# Ignore function names that match any of these:
FUNCTION_NAME_IGNORED = [
                            re.compile("^__CF.*"),
                            re.compile("^CF_.*"),
                            re.compile("^KSCRASH_DEPRECATED$"),
                            re.compile("^NS_.*"),
                        ]

# Make sure libc functions don't get swept up
LIBC_IGNORED = [
                re.compile("^_Exit$"),
                re.compile("^__acos$"),
                re.compile("^__acosf$"),
                re.compile("^__acosh$"),
                re.compile("^__acoshf$"),
                re.compile("^__acoshl$"),
                re.compile("^__acosl$"),
                re.compile("^__asin$"),
                re.compile("^__asinf$"),
                re.compile("^__asinh$"),
                re.compile("^__asinhf$"),
                re.compile("^__asinhl$"),
                re.compile("^__asinl$"),
                re.compile("^__asprintf$"),
                re.compile("^__assert$"),
                re.compile("^__assert_fail$"),
                re.compile("^__assert_perror_fail$"),
                re.compile("^__atan$"),
                re.compile("^__atan2$"),
                re.compile("^__atan2f$"),
                re.compile("^__atan2l$"),
                re.compile("^__atanf$"),
                re.compile("^__atanh$"),
                re.compile("^__atanhf$"),
                re.compile("^__atanhl$"),
                re.compile("^__atanl$"),
                re.compile("^__cbrt$"),
                re.compile("^__cbrtf$"),
                re.compile("^pthread_exit$"),
                re.compile("^pthread_getcpuclockid$"),
                re.compile("^pthread_getschedparam$"),
                re.compile("^pthread_getspecific$"),
                re.compile("^pthread_join$"),
                re.compile("^pthread_key_create$"),
                re.compile("^pthread_key_delete$"),
                re.compile("^pthread_kill$"),
                re.compile("^pthread_mutex_consistent$"),
                re.compile("^pthread_mutex_destroy$"),
                re.compile("^pthread_mutex_getprioceiling$"),
                re.compile("^pthread_mutex_init$"),
                re.compile("^pthread_mutex_lock$"),
                re.compile("^pthread_mutex_setprioceiling$"),
                re.compile("^pthread_mutex_timedlock$"),
                re.compile("^pthread_mutex_trylock$"),
                re.compile("^pthread_mutex_unlock$"),
                re.compile("^pthread_mutexattr_destroy$"),
                re.compile("^pthread_mutexattr_getprioceiling$"),
                re.compile("^pthread_mutexattr_getprotocol$"),
                re.compile("^pthread_mutexattr_getpshared$"),
                re.compile("^pthread_mutexattr_getrobust$"),
                re.compile("^pthread_mutexattr_gettype$"),
                re.compile("^pthread_mutexattr_init$"),
                re.compile("^pthread_mutexattr_setprioceiling$"),
                re.compile("^pthread_mutexattr_setprotocol$"),
                re.compile("^pthread_mutexattr_setpshared$"),
                re.compile("^pthread_mutexattr_setrobust$"),
                re.compile("^pthread_mutexattr_settype$"),
                re.compile("^pthread_once$"),
                re.compile("^pthread_rwlock_destroy$"),
                re.compile("^pthread_rwlock_init$"),
                re.compile("^pthread_rwlock_rdlock$"),
                re.compile("^pthread_rwlock_timedrdlock$"),
                re.compile("^pthread_rwlock_timedwrlock$"),
                re.compile("^pthread_rwlock_tryrdlock$"),
                re.compile("^pthread_rwlock_trywrlock$"),
                re.compile("^pthread_rwlock_unlock$"),
                re.compile("^pthread_rwlock_wrlock$"),
                re.compile("^pthread_rwlockattr_destroy$"),
                re.compile("^pthread_rwlockattr_getkind_np$"),
                re.compile("^pthread_rwlockattr_getpshared$"),
                re.compile("^pthread_rwlockattr_init$"),
                re.compile("^pthread_rwlockattr_setkind_np$"),
                re.compile("^pthread_rwlockattr_setpshared$"),
                re.compile("^pthread_self$"),
                re.compile("^pthread_setcancelstate$"),
                re.compile("^pthread_setcanceltype$"),
                re.compile("^pthread_setschedparam$"),
                re.compile("^pthread_setschedprio$"),
                re.compile("^pthread_setspecific$"),
                re.compile("^pthread_sigmask$"),
                re.compile("^pthread_spin_destroy$"),
                re.compile("^pthread_spin_init$"),
                re.compile("^pthread_spin_lock$"),
                re.compile("^pthread_spin_trylock$"),
                re.compile("^pthread_spin_unlock$"),
                re.compile("^pthread_testcancel$"),
                re.compile("^putc$"),
                re.compile("^putc_unlocked$"),
                re.compile("^putchar$"),
                re.compile("^putchar_unlocked$"),
                re.compile("^putenv$"),
                re.compile("^puts$"),
                re.compile("^putw$"),
                re.compile("^pwrite$"),
               ]

# Ignore global variables that match any of these:
VARIABLE_NAME_IGNORED = [
                            re.compile("^environ$"),
                            re.compile("^BOOL$"),
                            re.compile("^Boolean$"),
                            re.compile("^CFBasicHashValue$"),
                            re.compile("^CFIndex$"),
                            re.compile("^FOUNDATION_EXPORT$"),
                            re.compile("^id$"),
                            re.compile("^instancetype$"),
                            re.compile("^namespace$"),
                            re.compile("^NS.*"),
                            re.compile("^nullable$"),
                            re.compile("^objc_debug_.*"),
                            re.compile("^uintptr_t$"),
                        ]

# Ignore any objective-c classes, protocols, categries etc that match any of these:
OBJC_NAME_IGNORED = [
                    ]

# Ignore any C++ names or templates that match any of these:
CPP_NAME_IGNORED = [
                   ]


## ----------------------------------------------------------------------------
## Script
## ----------------------------------------------------------------------------

def generate_header_contents(symbols):
    namespace = "KSCRASH"
    namespace_define = f"{namespace}_NAMESPACE"
    header_define    = f"{namespace}_NAMESPACE_H"
    namespace_macro  = f"{namespace}_NS"

    contents = f"""//
// Auto-generated file. DO NOT EDIT!
//
// Generated by namespacer.py
//
// This header conditionally applies namespaces to all exposed symbols so that multiple instances of
// this library can coexist in the same binary without causing duplicate symbol errors during linking.
// Each instance will appear to be accessed the same way, such as `someFunction()`, but the
// actual symbols in the binary will be `someFunction_mylib`, `someFunction_yourlib`, etc.
//
// To use this feature, define {namespace_define} as whatever you'd like appended to all public symbols.
// - Example: `{namespace_define}=_mylib` will append _mylib to all public symbols.
//
// When public symbols are changed/added/removed, this file must be regenerated.
// - To regenerate this file, run the Makefile command: `make namespace`
//

#ifndef {header_define}
#define {header_define}

#ifdef {namespace_define}

#define {namespace_define}_STRINGIFY(X) {namespace_define}_STRINGIFY2(X)
#define {namespace_define}_STRINGIFY2(X) #X
#define {namespace_define}_STRING {namespace_define}_STRINGIFY({namespace_define})

#define {namespace_macro}2(NAMESPACE, SYMBOL) SYMBOL##NAMESPACE
#define {namespace_macro}1(NAMESPACE, SYMBOL) {namespace_macro}2(NAMESPACE, SYMBOL)
#define {namespace_macro}(SYMBOL) {namespace_macro}1({namespace_define}, SYMBOL)

"""
    for symbol in symbols:
        line = f"#define {symbol} {namespace_macro}({symbol})"
        if len(line) > 120:
            line = f"#define {symbol} \\\n    {namespace_macro}({symbol})"
        contents += f"{line}\n"
    contents += f"""
#else

#define {namespace_define}_STRING ""

#endif

#define {namespace_macro}_STRING(STR) STR {namespace_define}_STRING

#endif /* {header_define} */
"""
    return contents


def print_help():
    print(f"Usage: {sys.argv[0]} <sources-path> <dst-header-file>")


def print_all(src_dir):
    paths = get_compilation_unit_files(src_dir, [ # Paths matching these regexes are ignored
                                                    re.compile(".*KSCrashTestTools.*"),
                                                  ])
    for path in paths:
        tu = get_translation_unit(path)
        for cursor in tu.cursor.get_children():
            print(f"{cursor.kind}: {cursor.displayname}")


def matches_any(str, matchers):
    for matcher in matchers:
        if matcher.match(str):
            return True
    return False


def get_translation_unit(file_name):
    index = clang.cindex.Index.create()
    return index.parse(file_name)


def get_compilation_unit_files(path, ignore_matching):
    paths = []
    for p in Path(path).rglob("*"):
        if not p.is_file():
            continue
        if not p.suffix in [".h", ".hpp", ".c", ".cpp", ".m", ".mm"]:
            continue
        if matches_any(str(p), ignore_matching):
            continue;
        paths.append(p)
    return paths


def get_symbols_of_kind(translation_unit, kinds, ignore_matching):
    symbols = []
    for func_cursor in translation_unit.cursor.get_children():
        if not func_cursor.kind in kinds:
            continue
        if func_cursor.storage_class == clang.cindex.StorageClass.STATIC:
            continue
        func_name = re.sub(r"\(.*", "", func_cursor.displayname).strip()
        if len(func_name) == 0:
            continue
        if matches_any(func_name, ignore_matching):
            continue
        symbols.append(func_name)
    return list(dict.fromkeys(symbols))


def extract_swift_names(contents, ignore_matching):
    names = re.findall(r'NS_SWIFT_NAME\((.*)\)', contents)
    return [name for name in names if not matches_any(name, ignore_matching)]


def collect_symbols(path):
    tu = get_translation_unit(path)
    contents = Path(path).read_text()
    symbols = []
    symbols += extract_swift_names(contents, SWIFT_NAME_IGNORED)
    symbols += get_symbols_of_kind(tu, [clang.cindex.CursorKind.FUNCTION_DECL], FUNCTION_NAME_IGNORED + LIBC_IGNORED)
    symbols += get_symbols_of_kind(tu, [clang.cindex.CursorKind.VAR_DECL], VARIABLE_NAME_IGNORED)
    symbols += get_symbols_of_kind(tu, [
                                        clang.cindex.CursorKind.OBJC_INTERFACE_DECL,
                                        clang.cindex.CursorKind.OBJC_CATEGORY_DECL,
                                        clang.cindex.CursorKind.OBJC_PROTOCOL_DECL,
                                        clang.cindex.CursorKind.OBJC_IMPLEMENTATION_DECL,
                                        clang.cindex.CursorKind.OBJC_CATEGORY_IMPL_DECL,
                                       ], OBJC_NAME_IGNORED)
    symbols += get_symbols_of_kind(tu, [
                                        clang.cindex.CursorKind.CLASS_DECL,
                                        clang.cindex.CursorKind.CLASS_TEMPLATE,
                                       ], CPP_NAME_IGNORED)
    # Can't use this because the demangler has a namespace "swift", and blanket
    # replacing "swift" in this codebase will wreak havoc!
    # symbols += get_symbols_of_kind(tu, [clang.cindex.CursorKind.NAMESPACE], NAMESPACE_IGNORED)
    symbols += ALWAYS_ADDED_SYMBOLS
    symbols = list(dict.fromkeys(symbols))
    return symbols


def load_symbols_from_compilation_units(base_path):
    paths = get_compilation_unit_files(base_path, [ # Paths matching these regexes are ignored
                                                    re.compile(".*KSCrashTestTools.*"),
                                                  ])
    symbols = []
    for path in paths:
        symbols += collect_symbols(path)
    symbols = list(dict.fromkeys(symbols))
    symbols.sort()
    return symbols


def generate_header_file(src_dir, dst_file):
    # Clear before generating so that we don't load our own generated symbols.
    with open(dst_file, "w") as f:
        f.write("")

    symbols = load_symbols_from_compilation_units(src_dir)
    contents = generate_header_contents(symbols)

    with open(dst_file, "w") as f:
        f.write(contents)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print_help()
        sys.exit(1)

    src_dir = os.path.normpath(sys.argv[1])
    dst_file = os.path.normpath(sys.argv[2])

    # print_all(src_dir)
    generate_header_file(src_dir, dst_file)
