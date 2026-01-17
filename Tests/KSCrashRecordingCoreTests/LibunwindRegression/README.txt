These regression test cases were extracted from Apple's libunwind-35.1 via
PLCrashReporter, where they are used to validate compact frame and DWARF
unwinding implementations.

The ARM64 test cases were ported from the x86-64 tests by Plausible Labs.

The test cases themselves are licensed under libunwind's APSL license, and are
only used as part of the regression tests:

 Copyright (c) 2008-2011 Apple Inc. All rights reserved.
 Copyright (c) 2013 Plausible Labs Cooperative, Inc. All rights reserved.

 This file contains Original Code and/or Modifications of Original Code
 as defined in and that are subject to the Apple Public Source License
 Version 2.0 (the 'License'). You may not use this file except in
 compliance with the License. Please obtain a copy of the License at
 http://www.opensource.apple.com/apsl/ and read it before using this
 file.

 The Original Code and all software distributed under the License are
 distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 Please see the License for the specific language governing rights and
 limitations under the License.

KSCrash Modifications:
- Renamed _uwind_to_main to _ksunwind_to_main in assembly files
- Created new test harness that verifies DWARF parsing without using
  unw_resume() (which KSCrash does not implement)
