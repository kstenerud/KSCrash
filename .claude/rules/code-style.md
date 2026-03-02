## Inline Comments

Comment for your future self — the person who has to change this code safely without re-deriving the scary parts. Focus on:

- **Invariants that would break silently**: lock ordering, why a field is atomic (or isn't), why something is intentionally *not* guarded.
- **Non-obvious "why"**: if the reason for a choice isn't clear from the code alone, say why. "Load enterTime once — a second load could see a newer value if the main thread briefly woke" is useful. "Loads enterTime" is not.
- **Threading contracts**: which thread runs a function, and what's safe to touch from it.
- **Simulated or fake values**: when code produces synthetic data (e.g., faking a SIGKILL for watchdog reports), say what it's mimicking and who undoes it.
- **Crash-time constraints**: if code runs in a signal handler or with all threads suspended, say so and say what that means (no lock, no ObjC, etc.).

Do **not** comment:
- What a function does when the name already says it (`monotonicUptime`, `currentTaskRole`).
- Every struct field — only the ones with non-obvious lifetimes, ownership, or threading rules.
- Obvious control flow or standard patterns.

A good test: if removing the comment would make a future change risky, keep it. If the code reads fine without it, skip it.

## Formatting

- C/C++/Objective-C: Follow clang-format style defined in the project
- Swift: Follow Swift standard conventions and Xcode's recommended settings
- Formatting applies to files with extensions: .c, .cpp, .h, .m, .mm
- Use consistent naming patterns:
  - Classes: `KSCrashMonitor_*`, `KSCrash*` (prefix with KS)
  - Methods: descriptive, camelCase
  - **Swift SPM modules**: Do **not** use the `KSCrash` prefix. Use plain names (e.g., `SwiftCore`, `Monitors`, `Profiler`, `Report`). The `KSCrash` prefix is only for C/ObjC targets.
- Error handling: Use proper error handling conventions for Objective-C/Swift
- Module organization: Maintain the existing module structure
- API design: Keep public APIs clean and well-documented
- **Testing**: Always run sanitizers (ASan, TSan, UBSan) after changes to catch issues early

## File Headers

Every source file must include a header with the following components:

1. **Filename**: The name of the file as a comment
2. **Created by**: Author name and creation date
3. **Copyright**: Original copyright year (2012) and copyright holder (Karl Stenerud)
4. **License**: The MIT license text

**Standard header format:**
```c
//
//  KSExample.c
//
//  Created by Your Name on YYYY-MM-DD.
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
```

**For files derived from or inspired by other projects:**
If a file is based on code from another project, include the original copyright and license after the KSCrash license:

```c
//
//  KSExample.c
//
//  Created by Your Name on YYYY-MM-DD.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// [KSCrash MIT license text...]
//
// Inspired by original-project/original-file
// https://github.com/original/project
//
// [Original project's copyright and license text...]
//
```
