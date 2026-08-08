# Apple OSS Signal-Safety Verification Reference

How to verify whether a system function is async-signal-safe by reading Apple's actual source at **https://github.com/apple-oss-distributions**.

## Which repo owns which symbol

Match the function to a repo before fetching:

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

## How to fetch and read the source

Prefer `gh` over raw WebFetch — it authenticates, handles rate limits, and returns clean text:

```
gh api repos/apple-oss-distributions/Libc/contents/stdio/FreeBSD/vfprintf.c -H "Accept: application/vnd.github.raw"
gh search code --owner apple-oss-distributions --filename vfprintf.c
gh api repos/apple-oss-distributions/Libc/git/trees/main?recursive=1   # only if you really need the layout
```

If `gh` isn't available or the path is already known, use WebFetch against the `raw.githubusercontent.com` URL for the repo's default branch (usually `main`). Example: `https://raw.githubusercontent.com/apple-oss-distributions/Libc/main/stdio/FreeBSD/vfprintf.c`. Do not guess tags/versions — stick to `main` unless the user asks for a specific OS version.

## What to look for in the source

1. **Lock primitives.** Grep the file (and any helpers it calls) for:
   `FLOCKFILE`, `FUNLOCKFILE`, `pthread_mutex_lock`, `pthread_rwlock_`, `os_unfair_lock`, `OSSpinLock`, `LOCK(`, `_MUTEX_LOCK`, `xlocale`, `__current_locale`, `lock_`, `_lock`.
2. **Heap.** `malloc`, `calloc`, `realloc`, `asprintf`, zone allocation, VLA growth, `__sbuf` grow paths. Any of these disqualifies the call for signal context.
3. **Follow helpers.** `snprintf` looks innocent but calls `__vfprintf` → locale helpers → `__current_locale()` which takes a lock. Trace until you hit either a lock/alloc (unsafe) or a leaf that's obviously lock-free (safe).
4. **Cite the evidence.** In your report, give the repo + path + line + the exact lock/alloc call you saw (e.g., `apple-oss-distributions/Libc stdio/FreeBSD/vfprintf.c:123 — FLOCKFILE(fp)`). A verdict with no citation is a guess; don't ship guesses.

If the symbol isn't published on apple-oss-distributions at all (some `libsystem_*` shims, some kernel-only paths), say so explicitly rather than guessing.

## Delegate verifications to subagents (in parallel)

Each "is function X actually async-signal-safe on Apple?" lookup is **independent** and **context-heavy** (you may have to read several files to trace helpers). Do not do them inline in the main conversation — spawn a subagent per suspect symbol and run them in parallel. This keeps the main context clean and is much faster.

- Use the `Agent` tool with `subagent_type: "general-purpose"` (it has `gh`, `WebFetch`, `Read`, `Grep`). `Explore` also works but is read-only; `general-purpose` is safer since you may need `gh api`.
- Launch **all independent lookups in a single message** with multiple `Agent` tool calls. Don't serialize them.
- Give each subagent a tight, self-contained prompt: the symbol, which repo you think it lives in (or say "find it"), the specific question ("does this take a lock or allocate on the signal-handler path?"), and require it to cite `<repo>/<path>:LINE` for every lock/alloc it finds. Ask for ≤150 words.
- Do **not** delegate the review itself — only the factual lookups. You still decide the verdict, map findings back to the KSCrash diff, and write the report.

Example subagent prompt:

> Verify whether `strerror_r` is async-signal-safe on Apple. It's in apple-oss-distributions/Libc. Fetch the implementation (try `gen/FreeBSD/strerror.c` first via `gh api repos/apple-oss-distributions/Libc/contents/...`), trace any helpers it calls, and report: (1) does it take any lock (FLOCKFILE, pthread_mutex, os_unfair_lock, xlocale, __current_locale)? (2) does it allocate? (3) cite file+line for every lock/alloc you find, or state "no locks, no allocs found on this path". ≤150 words.

Only skip delegation if the answer is already in the "Common findings" list below AND the diff doesn't touch a variant/edge case.

## Common findings — use as priors but still verify

- `snprintf` / `vsnprintf` / `printf` family → **unsafe** (locale lock via `__current_locale`, plus stdio FLOCKFILE).
- `asprintf` → **unsafe** (calls `malloc`).
- `strerror` → **unsafe** (locale-dependent); `strerror_r` with a caller buffer is safer but still locale-touching on Apple — verify.
- `fopen` / `fwrite` / `fclose` / any `FILE*` API → **unsafe** (FLOCKFILE).
- `open` / `read` / `write` / `close` / `lseek` / `fstat` → **safe** (raw syscalls).
- `memcpy` / `memset` / `memmove` / `memcmp` / `strlen` / `strncmp` / `strcmp` → **safe**.
- `getsectiondata` → **safe** on Apple (confirmed via dyld source; its only non-trivial call is `strncmp`).
- `mach_*` task/thread APIs called by KSCrash → mostly safe; verify per-call if the diff touches new ones.
