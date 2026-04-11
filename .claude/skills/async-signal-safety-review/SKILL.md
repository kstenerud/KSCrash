---
name: async-signal-safety-review
description: Review code changes for async-signal-safety violations in KSCrash crash handlers, signal handlers, and monitor code. Verifies suspect system calls by reading the actual implementation in Apple's open-source repos on github.com/apple-oss-distributions rather than guessing. Use when the user asks to review a diff/branch/PR/file for signal safety, or before landing changes that touch signal handlers, Mach exception handlers, or anything reachable from `Sources/KSCrashRecording`, `Sources/KSCrashRecordingCore`, `Sources/KSCrashBootTimeMonitor`, or `Sources/KSCrashDiscSpaceMonitor`.
allowed-tools: Bash(git diff:*), Bash(git show:*), Bash(git log:*), Bash(git status:*), Bash(git merge-base:*), Bash(ls:*), Bash(gh api:*), Bash(gh search:*), Bash(gh repo:*), Read, Grep, Glob, WebFetch, WebSearch
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

The authoritative project rules live in `.claude/rules/async-signal-safety.md`. **Read that file first** — do not rely on memory, it may have been updated. Highlights that MUST hold for any code reachable from a signal handler or Mach exception handler:

- No heap allocation (`malloc`/`calloc`/`realloc`/`free`/`new`/`strdup`/`asprintf`/...).
- No locks, mutexes, semaphores, `@synchronized`, `dispatch_sync`, `os_unfair_lock`, `pthread_mutex_*`.
- No Objective-C / Swift / ObjC runtime calls.
- No `printf`/`snprintf`/`sprintf`/`vsnprintf`/`fprintf` — they take locale locks. Use `ksstring_uint64ToHex` / `ksstring_intToDecimal`.
- No `stdio` file I/O (`fopen`/`fwrite`/...). Use raw `open`/`read`/`write`/`close`.
- No allocating/locking CoreFoundation, Foundation, libdispatch APIs.
- Use C11 atomics (`<stdatomic.h>`) and atomic-exchange patterns (see `KSThreadCache.c`, `KSBinaryImageCache.c`).
- `getsectiondata()` IS safe on Apple. Do not flag it. If a code comment claims otherwise, flag the comment.
- Startup path: `kscrash_install` / `kscrs_initialize` must stay cheap. Flag heavy init work.

Code usually runs in BOTH crash and normal contexts — both must be correct.

## Verify suspect calls against Apple's open source (do not guess)

Apple publishes the source for most of the runtime at **https://github.com/apple-oss-distributions**. Whenever you're unsure whether a system function is async-signal-safe, **go read the actual implementation** in the relevant repo. The POSIX async-signal-safe list is a lower bound; Apple's implementation can take locks on things POSIX calls safe (notably locale), and can be safer than POSIX on others.

### Which repo owns which symbol

Match the function to a repo before fetching. Common ones:

- **`Libc`** — `printf`/`snprintf`/`vfprintf`, `fopen`/`fwrite`/`FILE*` stdio, `str*`, `mem*`, `getenv`, `strtol`, `strerror`, locale machinery (`xlocale`, `__current_locale`), `syslog`.
- **`libplatform`** — `os_unfair_lock_*`, `_os_semaphore_*`, low-level atomics and memory barriers, `setjmp`/`longjmp`, `bzero`.
- **`libpthread`** — `pthread_*` (mutex, rwlock, cond, key, create, self, kill), `pthread_once`.
- **`libdispatch`** — all `dispatch_*`, `dispatch_source_*`, `os_workgroup_*`.
- **`libmalloc`** — `malloc`/`calloc`/`realloc`/`free`/`malloc_zone_*`/`malloc_size`. (All unsafe — they take the zone lock.)
- **`dyld`** — `dlopen`/`dlsym`/`dladdr`, `_dyld_*`, `getsectiondata`, image list iteration. Signal safety of `dladdr` specifically matters for symbolication.
- **`xnu`** — Mach traps, `mach_*`, `task_*`, `thread_*`, `sigaction`/signal delivery internals, `sysctl`, kernel side of syscalls. Usually you want the userspace wrapper first (Libc/libsyscall), then xnu only if needed.
- **`objc4`** — ObjC runtime (`objc_msgSend`, `objc_retain`, class lookup). All unsafe in signal context; the runtime takes its own locks.
- **`CF` (`CoreFoundation` is mirrored as `CF`)** — `CF*` APIs. Almost always unsafe.

If you can't tell which repo a symbol lives in, `gh search code --owner apple-oss-distributions '<symbol>'` first.

### How to fetch and read the source

Prefer `gh` over raw WebFetch when possible — it authenticates, handles rate limits, and returns clean text:

```
gh api repos/apple-oss-distributions/Libc/contents/stdio/FreeBSD/vfprintf.c -H "Accept: application/vnd.github.raw"
gh search code --owner apple-oss-distributions --filename vfprintf.c
gh api repos/apple-oss-distributions/Libc/git/trees/main?recursive=1   # only if you really need the layout
```

If `gh` isn't available or the path is already known, use WebFetch against the `raw.githubusercontent.com` URL for the repo's default branch (usually `main`). Example: `https://raw.githubusercontent.com/apple-oss-distributions/Libc/main/stdio/FreeBSD/vfprintf.c`. Do not guess tags/versions — stick to `main` unless the user asks for a specific OS version.

### Delegate verifications to subagents (in parallel)

Each "is function X actually async-signal-safe on Apple?" lookup is **independent** and **context-heavy** (you may have to read several files to trace helpers). Do not do them inline in the main conversation — spawn a subagent per suspect symbol and run them in parallel. This keeps the main context clean and is much faster.

- Use the `Agent` tool with `subagent_type: "general-purpose"` (it has `gh`, `WebFetch`, `Read`, `Grep`). `Explore` also works but is read-only; `general-purpose` is safer since you may need `gh api`.
- Launch **all independent lookups in a single message** with multiple `Agent` tool calls. Don't serialize them.
- Give each subagent a tight, self-contained prompt: the symbol, which repo you think it lives in (or say "find it"), the specific question ("does this take a lock or allocate on the signal-handler path?"), and require it to cite `<repo>/<path>:LINE` for every lock/alloc it finds. Ask for ≤150 words.
- Do **not** delegate the review itself — only the factual lookups. You still decide the verdict, map findings back to the KSCrash diff, and write the report.

Example subagent prompt:

> Verify whether `strerror_r` is async-signal-safe on Apple. It's in apple-oss-distributions/Libc. Fetch the implementation (try `gen/FreeBSD/strerror.c` first via `gh api repos/apple-oss-distributions/Libc/contents/...`), trace any helpers it calls, and report: (1) does it take any lock (FLOCKFILE, pthread_mutex, os_unfair_lock, xlocale, __current_locale)? (2) does it allocate? (3) cite file+line for every lock/alloc you find, or state "no locks, no allocs found on this path". ≤150 words.

Only skip delegation if the answer is already in the "Common findings" list below AND the diff doesn't touch a variant/edge case.

### What to look for in the source

1. **Lock primitives.** Grep the file (and any helpers it calls) for:
   `FLOCKFILE`, `FUNLOCKFILE`, `pthread_mutex_lock`, `pthread_rwlock_`, `os_unfair_lock`, `OSSpinLock`, `LOCK(`, `_MUTEX_LOCK`, `xlocale`, `__current_locale`, `lock_`, `_lock`.
2. **Heap.** `malloc`, `calloc`, `realloc`, `asprintf`, zone allocation, VLA growth, `__sbuf` grow paths. Any of these disqualifies the call for signal context.
3. **Follow helpers.** `snprintf` looks innocent but calls `__vfprintf` → locale helpers → `__current_locale()` which takes a lock. Trace until you hit either a lock/alloc (unsafe) or a leaf that's obviously lock-free (safe).
4. **Cite the evidence.** In your report, give the repo + path + line + the exact lock/alloc call you saw (e.g., `apple-oss-distributions/Libc stdio/FreeBSD/vfprintf.c:123 — FLOCKFILE(fp)`). A verdict with no citation is a guess; don't ship guesses.

If the symbol isn't published on apple-oss-distributions at all (some `libsystem_*` shims, some kernel-only paths), say so explicitly rather than guessing.

### Common findings — use as priors but still verify

- `snprintf` / `vsnprintf` / `printf` family → **unsafe** (locale lock via `__current_locale`, plus stdio FLOCKFILE).
- `asprintf` → **unsafe** (calls `malloc`).
- `strerror` → **unsafe** (locale-dependent); `strerror_r` with a caller buffer is safer but still locale-touching on Apple — verify.
- `fopen` / `fwrite` / `fclose` / any `FILE*` API → **unsafe** (FLOCKFILE).
- `open` / `read` / `write` / `close` / `lseek` / `fstat` → **safe** (raw syscalls).
- `memcpy` / `memset` / `memmove` / `memcmp` / `strlen` / `strncmp` / `strcmp` → **safe**.
- `getsectiondata` → **safe** on Apple (confirmed via dyld source; its only non-trivial call is `strncmp`).
- `mach_*` task/thread APIs called by KSCrash → mostly safe; verify per-call if the diff touches new ones.

## What to review

If the user named a scope, use that. Otherwise default to the current branch vs `master`:

1. `git status` — note uncommitted changes.
2. `git merge-base HEAD master`, then `git diff <base>...HEAD`.
3. Include `git diff HEAD` if there are uncommitted changes.

Only review files where async-signal-safety applies (the `paths:` list in `.claude/rules/async-signal-safety.md`). Ignore Swift modules, Filters, Sinks, Installations, sample app, and docs — mention that you skipped them once, then move on.

## How to review each change

For every changed function, answer two questions before judging it:

1. **Is it reachable from a crash/signal handler?** Grep for callers. Entry points to trace from: `ksmach_*` exception handlers, `kssignal_*` signal handlers, `KSCrashMonitorAPI.handleException` / `notifyPostSystemEnable`, `kscm_*_getAPI`, `kscrashsentry_*`, and anything registered via `sigaction` or `thread_set_exception_ports`. If only called from `+load`, init, or the writer's background thread, signal-safety doesn't apply — note it and move on.
2. **Does it also run in a non-crash context?** If yes, thread-safety and signal-safety must BOTH hold. A lock-free path that races with a concurrent writer is still a bug.

Then scan for concrete violations. For any system call you're not 100% certain about, **fetch the source from apple-oss-distributions and verify** before flagging or clearing it. Cite `file.c:LINE` for the KSCrash change and `<repo>/<path>:LINE` for the evidence.

Be especially suspicious of:

- New `static` mutable state without `_Atomic`, without documented single-thread ownership.
- New format strings or `KSLOG_*` calls — check the configured log level constant; verbose logging uses `snprintf` under the hood and is compiled out only at low levels.
- New includes of `<Foundation/...>`, `<dispatch/...>`, `<os/lock.h>`, `<stdio.h>`.
- Ring buffers / caches: verify producer/consumer contract holds under signal interruption (pattern: `KSThreadCache.c`, `KSBinaryImageCache.c`).
- Changes under `kscrash_install` / `kscrs_initialize` that add I/O or parsing.
- Stale comments: "not async-signal-safe" on something that now is, or vice versa.

## Output format

Keep it tight. Only these sections. No preamble, no postscript.

```
Scope: <one line — what you reviewed>
Signal-handler reachable files: <list>
Skipped (not on signal path): <list or "none">

Violations:
- Sources/.../file.c:LINE in func_name — <rule broken>
  Evidence: apple-oss-distributions/<repo> <path>:LINE — <lock/alloc seen>
  Fix: <concrete signal-safety fix>

Suspected (unverified) violations:
- <only if a subagent lookup was inconclusive; name the symbol and what needs verifying>

Stale signal-safety claims in comments:
- <only if a code comment falsely says something is/isn't signal-safe>

Verdict: signal-safe | NOT signal-safe (see violations above)
```

Rules for the output:
- If a section has no entries, **omit the section entirely** (don't write "none").
- The verdict is binary and **scoped to signal safety only**. Never say "safe to land" / "needs author clarification" / "looks good otherwise". Those are PR-review verdicts, not signal-safety verdicts.
- If there are zero violations, the entire body can be just the Scope line, the reachable-files line, and `Verdict: signal-safe`. That's a complete, correct report.
- Do not restate what the diff does. Do not add context the reader already has.
