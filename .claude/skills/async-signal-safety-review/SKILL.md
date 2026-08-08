---
name: async-signal-safety-review
description: Review code changes for async-signal-safety violations in KSCrash crash handlers, signal handlers, and monitor code. Verifies suspect system calls by reading the actual implementation in Apple's open-source repos on github.com/apple-oss-distributions rather than guessing. Use when the user asks to review a diff/branch/PR/file for signal safety, or before landing changes that touch signal handlers, Mach exception handlers, or anything reachable from `Sources/KSCrashRecording`, `Sources/KSCrashRecordingCore`, `Sources/KSCrashBootTimeMonitor`, or `Sources/KSCrashDiscSpaceMonitor`.
argument-hint: "[PR-number, branch, or file path]"
allowed-tools: Bash(git diff:*), Bash(git show:*), Bash(git log:*), Bash(git status:*), Bash(git merge-base:*), Bash(gh api repos/apple-oss-distributions:*), Bash(gh search code --owner apple-oss-distributions:*), Bash(gh pr view:*), Bash(gh pr diff:*), Read, Grep, Glob, WebFetch, WebSearch
---

# Async-Signal-Safety Review (with Libc ground-truthing)

**Scope is strict: async-signal-safety and crash-time correctness only.** This is NOT a general PR review. You are not evaluating whether the PR should land, whether the design is good, whether doc comments read well, whether names are clear, whether tests exist, or whether refactors are worthwhile. You are answering exactly one question per changed line: *does this break async-signal-safety on the signal-handler path?*

**Do NOT include in the report:**
- Style, naming, readability, or refactor opinions.
- Doc / comment wording suggestions, unless the comment makes a false claim about signal safety (e.g. says something is unsafe when it is, or vice versa).
- DX concerns, API-shape feedback, "the author should clarify intent", "worth a second look" items that aren't concrete signal-safety issues.
- Test coverage commentary.
- Summaries of what the diff does beyond the one-line Scope.
- Praise, "looks good", "nice refactor", or any editorial voice.

If a concern is not "X calls a lock/alloc/ObjC from a signal-reachable path" or "a comment misstates signal safety", it does not belong in the output. When in doubt, cut it.

## Ground rules

The authoritative rules live in `.claude/rules/async-signal-safety.md`. **Read that file before every review** — do not summarize or duplicate the rules here; they may have been updated since this skill was last edited. Apply all rules from that file as-is.

## Verify suspect calls against Apple's open source (do not guess)

Whenever you're unsure whether a system function is async-signal-safe, **do not guess** — read the actual implementation. Full instructions for how to look up symbols, which Apple OSS repo owns which function, how to fetch source via `gh`, how to delegate lookups to parallel subagents, and a list of common findings are in [apple-oss-reference.md](apple-oss-reference.md). **Read that file** when you encounter a suspect system call.

## What to review

Determine the review mode from the user's input:

- **PR number** (e.g. `#809`, `PR 809`): fetch the PR diff with `gh pr diff <number>` and review only those changes.
- **Branch name**: diff that branch against `master` and review only those changes.
- **File or module name** (e.g. `signal monitor`, `KSCrashMonitor_Signal.c`, `KSObjC`): **ambiguous** — the user might mean the whole file or just changes to it. Ask: "Do you want me to review the entire file or only the changes on the current branch?" Do not guess.
- **No argument**: default to current branch vs `master` — `git merge-base HEAD master`, then `git diff <base>...HEAD`.

Only review files where async-signal-safety applies (the `paths:` list in `.claude/rules/async-signal-safety.md`). Ignore Swift modules, Filters, Sinks, Installations, sample app, and docs — mention that you skipped them once, then move on.

## How to review

### 1. Identify signal-reachable functions

Not every function in a file needs signal-safety. First, determine which functions are on the **critical path** — reachable (directly or transitively) from a signal/crash handler. Entry points to trace from: `ksmach_*` exception handlers, `kssignal_*` signal handlers, `KSCrashMonitorAPI.handleException` / `notifyPostSystemEnable`, `kscm_*_getAPI`, `kscrashsentry_*`, anything registered via `sigaction` or `thread_set_exception_ports`. Functions only called from `+load`, init, setup, or background threads don't need signal-safety — skip them.

### 2. Trace transitive calls (across files)

For each signal-reachable function, follow **every call it makes** — including into other files, other modules, and system libraries. A function that looks clean itself but calls a helper in `KSString.c` or `KSLogger.c` that uses `snprintf` is still unsafe. Grep for the callee, read its implementation, and recurse until you reach either a leaf (safe primitive, raw syscall, atomic op) or a violation (lock, alloc, ObjC). This is where subagents are most valuable — delegate cross-file lookups in parallel per [apple-oss-reference.md](apple-oss-reference.md).

### 3. Check dual-context correctness

If a signal-reachable function also runs in a non-crash context (normal thread, background queue), thread-safety and signal-safety must BOTH hold. A lock-free path that races with a concurrent writer is still a bug.

### 4. Scan for violations

Then check for concrete violations. For any system call you're not 100% certain about, **fetch the source from apple-oss-distributions and verify** before flagging or clearing it. Cite `file.c:LINE` for the KSCrash change and `<repo>/<path>:LINE` for the evidence.

Be especially suspicious of:

- New `static` mutable state without `_Atomic`, without documented single-thread ownership.
- New format strings or `KSLOG_*` calls — check the configured log level constant; verbose logging uses `snprintf` under the hood and is compiled out only at low levels.
- New includes of `<Foundation/...>`, `<dispatch/...>`, `<os/lock.h>`, `<stdio.h>`.
- Ring buffers / caches: verify producer/consumer contract holds under signal interruption (pattern: `KSThreadCache.c`, `KSBinaryImageCache.c`).
- Changes under `kscrash_install` / `kscrs_initialize` that add I/O or parsing.
- Stale comments: "not async-signal-safe" on something that now is, or vice versa.

## Output format

The output uses **only** the sections shown in the template below. No other sections, headers, labels, or free-text are allowed. Do not add "Analysis details", "Notes", "Context", "Summary", explanations of why something is safe, or any prose outside these sections.

```
Scope: <one line>
Signal-handler reachable files: <list>
Skipped (not on signal path): <list>

Violations:

Root cause: <unsafe primitive, e.g. "vsnprintf (locale lock + FLOCKFILE)">
Evidence: apple-oss-distributions/<repo> <path>:LINE — <lock/alloc seen>
Fix: <one fix that addresses all instances of this root cause>
Instances:
- Sources/.../file.c:LINE in func_name — call chain: handler → ... → func_name → unsafe_call
- Sources/.../other.c:LINE in other_func — call chain: handler → ... → other_func → unsafe_call
- ...

Root cause: <next distinct unsafe primitive>
...

Suspected (unverified) violations:
- <symbol, call chain showing how it's reachable, and what needs verifying>

Stale signal-safety claims in comments:
- <comment that falsely claims signal safety or unsafety>

Verdict: signal-safe | NOT signal-safe (see violations above)
```

Strict rules — violating any of these makes the report wrong:
- **Group violations by root cause.** If 15 call sites all hit `vsnprintf`, that's one root cause with 15 instances — not 15 separate violations. The Evidence and Fix appear once per root cause; instances are a flat list with call chains.
- **Every instance must include its call chain** from the signal handler entry point to the unsafe call. Example: `handleSignal → kscrashreport_writeStandardReport → ksjson_addFloatingPointElement → formatDouble → snprintf`. Without the chain, the reader can't verify reachability.
- **Only the sections above exist.** If you catch yourself writing any heading or label not in the template, delete it.
- If a section has no entries, **omit it entirely**. For a clean report with no violations, output is exactly three lines: Scope, Signal-handler reachable files, Verdict.
- The verdict is binary. Never write "safe to land", "needs clarification", "looks good".
- **Nothing comes after the Verdict line.** No caveats, no "in practice", no analysis, no mitigating context. The Verdict line is the end.
- **Every Evidence line must cite a concrete file:line from apple-oss-distributions.** If you spawned a subagent, wait for it and use its citation. Do not write "well-known to use fprintf" — cite the source or mark as unverified.
- Do not explain why things are safe. Do not restate what the code does. The reader already knows.
