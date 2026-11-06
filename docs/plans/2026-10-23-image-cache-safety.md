# Binary Image Cache: List Rebuilds and Image Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read dyld's image list consistently, drop cache entries when dyld announces an image's removal, and stop handing the report writer a pointer into an image for its UUID.

**Architecture:** Three small changes inside `KSBinaryImageCache.c` and `KSDynamicLinker.c`. `ksbic_getImages` brackets its loads with dyld's change stamp. The dyld notifier's `dyld_image_removing` branch evicts image entries and fans out to a removal callback that `KSDynamicLinker.c` uses to evict symbol entries, with a flush flag for the moment a handler holds a cache. Entries carry their 16 UUID bytes by value. No new types, no syscalls, no change to the hit path.

**Tech Stack:** C11 atomics, XCTest (ObjC) in `Tests/KSCrashRecordingCoreTests`.

**Spec:** `docs/design/2026-10-23-image-cache-safety.md`

## Why this is the whole plan

A nine-task version of this plan existed and was cut after asking, for each task, whether the thing it defends against happens. An image is unmapped only when the app `dlopen`ed a pure C or C++ dylib itself and later closed it; nothing in the shared cache, nothing the main executable links, and nothing with ObjC or Swift content ever unmaps. That does not happen on iOS and is uncommon on macOS. The list-rebuild race happens on every `dlopen` but lasts microseconds. What survived is the set of changes that are cheap, correct, and fix a stated assumption in the code that dyld's source contradicts. The design's "Non-goals" section lists what was dropped and why.

## The five pillars

Every task states what it does to each of these.

- **Speed**: latency of one lookup on the crash path, hit and miss.
- **Correctness**: the answer names the image and symbol that are actually at the address now.
- **Optimization**: kernel calls, stack bytes and static bytes spent.
- **Performance**: cost of whole operations on the host app, a report write or a `dlopen`/`dlclose`.
- **Reliability**: no fault, no hang, no wait, in a handler or in the dyld notifier.

## Global Constraints

- Hit path: unchanged. No new loads, compares or validation on a cache hit.
- No syscalls, no `malloc`, no new stack buffers on any path reachable from a handler.
- Never wait, spin or sleep where a handler can run; the dyld notifier never waits either (it runs on the `dlclose` thread under dyld's lock).
- Everything touched stays async-signal-safe (`.claude/rules/async-signal-safety.md`).
- After adding or removing C symbols run `make namespace`; before committing run `make all`.
- Run `swift test --sanitize address` and `swift test --sanitize thread` without `--filter` at the end of Task 3.
- Commit messages: no `Co-Authored-By`, no AI mention, no em dashes.

## Review Focus

1. A crash in thread A while thread B is inside `dlopen` with `infoArray` NULL: `ksbic_getImages` returns NULL, every miss returns "not found", `binary_images` is an empty array, and the report still writes. Pinned in Task 1 (`testGetImagesReturnsNULLWhileDyldRebuilds`).
2. The list rebuilt between the first and last loads of `ksbic_getImages`: the caller never gets an old pointer with a new count. Pinned in Task 1 (`testGetImagesRejectsListRebuiltBetweenLoads`).
3. A plugin host `dlclose`s a pure-C plugin whose entries are cached: both caches drop their entries before dyld unmaps, so the next lookup misses instead of reading the old UUID, name or symbol string. Pinned in Task 2 (`testRemovalNotificationEvictsCachedImage`, `testRemovalNotificationEvictsSymbolCacheEntries`).
4. A `dlclose` that lands while a handler holds a cache: the removal is not lost; the next acquire flushes. Pinned in Task 2 (`testRemovalWhileCacheBusyFlushesOnNextAcquire`).
5. Cache entries shift when a lower-addressed image is inserted: a UUID copied out before the shift is the right 16 bytes, and one copied after is too. Pinned in Task 3 (`testCopyUUIDForHeader_SurvivesEntryShift`).

What is not pinned, by choice: an unmap landing inside a handler's walk after a hit, and dyld freeing the old `infoArray` buffer after `ksbic_getImages` accepted it. Both are microsecond windows that need an unload. The code comment at the list read says so.

---

### Task 1: A consistent read of dyld's image list

**Why.** `ksbic_getImages` loads `infoArray`, checks it for NULL, then loads `infoArrayCount`. dyld-1378 writes NULL, then the count, then `infoArrayChangeTimestamp`, then the pointer, on every load and unload. A pointer loaded before a rebuild and a count loaded after it describe two different lists; on a removal the count is smaller and the tail entries read past the new end into stale data. The comment above the atomics says items are never removed and the count is written after the array, which is wrong on both points and will mislead the next person.

**What.** Load the stamp, the count, the pointer, then the stamp again, all acquire loads from dyld's struct (always mapped, no syscall). Accept only a non-NULL pointer with equal stamps; retry up to three times; otherwise return NULL as today. Given dyld's write order, equal stamps around a non-NULL pointer mean the count and the pointer were published together under that stamp. The signature does not change, so all callers (three in `Sources`, about forty in tests) keep working. Rewrite the comment to state dyld's behavior and the window that stays open.

**Pillars.**
- Speed: unchanged. Two extra atomic loads per `ksbic_getImages` call, which runs only on misses and in the all-images report path.
- Correctness: a caller never iterates an old pointer with a new count.
- Optimization: unchanged. No syscall, no buffer.
- Performance: unchanged.
- Reliability: a crash during another thread's `dlopen` gets NULL (today's handled case) or a consistent list, never a torn one.

**Files:**
- Modify: `Sources/KSCrashRecordingCore/KSBinaryImageCache.c` (`ksbic_getImages`, the comment block above `g_all_image_infos`)
- Test: `Tests/KSCrashRecordingCoreTests/KSBinaryImageCache_Tests.m`

**Interfaces:**
- `ksbic_getImages(uint32_t *count)` keeps its signature and NULL-on-unavailable contract.
- File-internal: loads via `__atomic_load_n(&allInfo->infoArrayChangeTimestamp, __ATOMIC_ACQUIRE)` and the same for `infoArrayCount` and `infoArray`, in the order stamp, count, pointer, stamp; `KSBIC_IMAGE_LIST_READ_ATTEMPTS 3`.
- Test seams (defined in the `.c`, declared `extern` in the test, like `ksbic_resetCache`):
  - `void ksbic_testcode_setAllImageInfos(struct dyld_all_image_infos *_Nullable infos);` swaps `g_all_image_infos`; NULL restores the real one captured at `ksbic_init`.
  - `void ksbic_testcode_setImageListLoadHook(void (*_Nullable hook)(int step));` called after each of the four loads with `step` 0 to 3; one NULL check per load, always compiled.

- [ ] **Step 1: Write the failing tests**

```objc
- (void)testGetImagesCountMatchesDyld  // ksbic_getImages(&count) != NULL and count == _dyld_image_count()
- (void)testGetImagesReturnsNULLWhileDyldRebuilds
{
    // struct dyld_all_image_infos fake = *real; fake.infoArray = NULL; ksbic_testcode_setAllImageInfos(&fake);
    // ksbic_resetCache(); ksbic_init(); (init under the fake caches dyld only, must not crash)
    // Assert ksbic_getImages(&count) == NULL, count == 0, and ksbic_findImageForAddress((uintptr_t)&testFunctionInThisBundle) == NULL.
    // @finally: ksbic_testcode_setAllImageInfos(NULL); ksbic_resetCache(); ksbic_init();
}
- (void)testGetImagesRejectsListRebuiltBetweenLoads
{
    // fake = *real. static struct dyld_image_info second[count + 1] = real entries plus a copy of entry 0.
    // Hook at step 1 (after the count load), once: fake.infoArray = NULL; fake.infoArrayCount = count + 1;
    //   fake.infoArrayChangeTimestamp += 1; fake.infoArray = second; then uninstall itself.
    // Assert ksbic_getImages(&got) == second and got == count + 1. The first attempt read the old count with the new stamp and was rejected.
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter KSCrashRecordingCore_Tests/KSBinaryImageCache_Tests`
Expected: the seams are undefined; after adding stubs, the third test fails with `got == count` or the old array.

- [ ] **Step 3: Implement the four-load read, the attempts loop, the two seams, and rewrite the comment.** The comment states: dyld NULLs the pointer during a rebuild, writes count then stamp then pointer, removes entries on unload, and that an old buffer freed after this read is accepted as the window this leaves open.

- [ ] **Step 4: Run the suite**

Run: `swift test --filter KSCrashRecordingCore_Tests`
Expected: PASS.

- [ ] **Step 5: Commit** `Read dyld's image list under its change stamp`

**Superseded by the review-fix commits.** The stamp bracket above is wrong on both dyld generations
in the support range: dyld-1378 publishes the new stamp before the count (so stamp, count, pointer,
stamp accepted the old count with the new pointer) and dyld-941 publishes it after the count and
last on a removal (so stamp, pointer, count, stamp accepted the new count with the old pointer).
The code reads stamp, pointer and count twice and accepts only an identical pair with a non-NULL
pointer; the design doc has the reasoning and the remaining arm64 gap. The hooks fire after the
reader's second and third loads, and four tests model the two generations' sequences.

---

### Task 2: Evict both caches when dyld announces a removal

**Why.** The notifier already receives `dyld_image_removing` and ignores it, on the stated assumption that `dlclose` never unloads. It does unload a pure C or C++ dylib the app loaded itself, and `RuntimeState::notifyUnload` fires the notification before `removeLoaders` unmaps the image and frees the `Loader` whose `path()` backs `imageFilePath`. After that, the image cache entry's `name` and `uuid` pointers and every symbol cache entry's `dli_sname` pointer for that image point at unmapped memory, and a frame in that image (the crash in a plugin host is usually the call into the closed plugin) faults the handler. If a new image is mapped at the same address, the stale sorted entry answers for it.

**What.** The `dyld_image_removing` branch acquires the image cache by atomic exchange and removes each named header from the sorted array. If a handler holds the cache, it sets a flush flag and the next successful acquire empties the cache (entries repopulate by misses, as they do after install). It then calls a registered removal callback per header, the mirror of `ksbic_registerForImageAdded`. `KSDynamicLinker.c` registers one that drops symbol entries whose `imageBase` is that header, with the same flag fallback. The notifier's comment and the header docs state dyld's order.

**Pillars.**
- Speed: unchanged on hits. Each acquire gains one relaxed atomic load of the flush flag.
- Correctness: no entry in either cache answers for an image dyld has announced as removed, including a replacement at the same address.
- Optimization: one `bool` per cache. No ring, no copies.
- Performance: per removed image, one `memmove` of the sorted tail and one pass over the symbol cache, on the `dlclose` thread, which is already unmapping. A flush (removal during a handler) costs the misses that rebuild the cache afterwards.
- Reliability: the notifier never waits on either cache, so a suspended handler can never block `dlclose`.

**Files:**
- Modify: `Sources/KSCrashRecordingCore/include/KSBinaryImageCache.h`, `Sources/KSCrashRecordingCore/KSBinaryImageCache.c` (notifier, every `atomic_exchange(&g_cache_ptr, NULL)` site), `Sources/KSCrashRecordingCore/KSDynamicLinker.c` (`ksdl_init`, `ksdl_dladdr`, new callback)
- Test: `Tests/KSCrashRecordingCoreTests/KSBinaryImageCache_Tests.m`, `Tests/KSCrashRecordingCoreTests/KSDynamicLinker_Tests.m`

**Interfaces:**
- Produces (public to RecordingCore, in `KSBinaryImageCache.h`, documented with `@param`):
  - `typedef void (*ksbic_imageRemovedCallback)(const struct mach_header *_Nonnull mh);`
  - `void ksbic_registerForImageRemoved(ksbic_imageRemovedCallback _Nullable callback);` one callback, replaces the previous, called on the `dlclose` thread after the image cache has evicted the header and before dyld unmaps it. No slide: computing one would re-parse and re-cache the header.
- File-internal in `KSBinaryImageCache.c`:
  - `static _Atomic bool g_flushPending;`
  - `static KSBinaryImageRangeCache *acquireCache(void)`: `atomic_exchange(&g_cache_ptr, NULL)`; when non-NULL and `atomic_exchange(&g_flushPending, false)` is true, set `cache->count = 0`. Every existing `atomic_exchange(&g_cache_ptr, NULL)` becomes `acquireCache()`.
  - `static void removeCacheEntry(KSBinaryImageRangeCache *cache, int32_t index)`: `memmove` the tail down, `count--`.
  - `static void handleImageNotification(enum dyld_image_mode mode, uint32_t infoCount, const struct dyld_image_info info[])`: the current notifier body plus the removing branch; `ksbic_dyld_image_notifier` calls it and then chains to `g_original_notifier`.
- File-internal in `KSDynamicLinker.c`:
  - `static _Atomic bool g_symbolFlushPending;`
  - `static void symbolCacheImageRemoved(const struct mach_header *mh)`: `atomic_exchange(&g_symbol_cache_ptr, NULL)`; NULL sets the flag; otherwise compacts out entries with `imageBase == mh` and releases.
  - `ksdl_dladdr`: after a successful exchange, `if (atomic_exchange(&g_symbolFlushPending, false)) cache->count = 0;`.
  - `ksdl_init` calls `ksbic_registerForImageRemoved(symbolCacheImageRemoved)`.
- Test seams: `void ksbic_testcode_notify(enum dyld_image_mode mode, uint32_t infoCount, const struct dyld_image_info *_Nonnull info);` (calls `handleImageNotification` only, never dyld's original notifier), `void ksbic_testcode_holdCache(void);`, `void ksbic_testcode_releaseCache(void);`, `uint32_t ksbic_testcode_cacheCount(void);`, `uint32_t ksdl_testcode_symbolCacheCount(void);`.
- Test helper (test file only): `static void *makeSyntheticImage(void)`: `vm_allocate` one page; write `mach_header_64` (`MH_MAGIC_64`, host `cputype`, `MH_DYLIB`), one `LC_SEGMENT_64` `__TEXT` (`vmaddr 0`, `vmsize PAGE_SIZE`, `fileoff 0`, `filesize PAGE_SIZE`), one `LC_UUID` with bytes `0x42`; set `ncmds` and `sizeofcmds`. Caller `vm_deallocate`s.

- [ ] **Step 1: Write the failing tests**

```objc
// KSBinaryImageCache_Tests.m
- (void)testRemovalNotificationEvictsCachedImage
{
    // page = makeSyntheticImage(); ksbic_getUnwindInfoForHeader(page) caches it on a miss; before = ksbic_testcode_cacheCount();
    // struct dyld_image_info info = { page, "/fake/libfake.dylib", 0 }; ksbic_testcode_notify(dyld_image_removing, 1, &info);
    // Assert ksbic_testcode_cacheCount() == before - 1 and ksbic_findImageForAddress((uintptr_t)page + 64) == NULL (page still mapped, so the miss path is safe).
}
- (void)testRemovalWhileCacheBusyFlushesOnNextAcquire
{
    // Same setup. ksbic_testcode_holdCache(); notify removing; ksbic_testcode_releaseCache();
    // Assert ksbic_findImageForAddress((uintptr_t)page + 64) == NULL and ksbic_testcode_cacheCount() <= 1 (flushed; at most what that lookup repopulated).
}
- (void)testRemovalNotificationIgnoresUnknownHeader  // notify removing for a header never cached; count unchanged; no crash

// KSDynamicLinker_Tests.m
- (void)testRemovalNotificationEvictsSymbolCacheEntries
{
    // ksdl_resetCache(); ksdl_init(); uintptr_t address = (uintptr_t)&someFunctionInThisTestBundle;
    // Dl_info real; dladdr((void *)address, &real); ksdl_dladdr(address, &info); XCTAssertEqual(ksdl_testcode_symbolCacheCount(), 1);
    // struct dyld_image_info rm = { real.dli_fbase, real.dli_fname, 0 }; ksbic_testcode_notify(dyld_image_removing, 1, &rm);
    // Assert ksdl_testcode_symbolCacheCount() == 0, and ksdl_dladdr(address, &info) is still true (the bundle is really still loaded; the miss repopulates both caches).
}
```

- [ ] **Step 2: Run to verify they fail** (seams undefined; after stubs, the eviction asserts fail).

- [ ] **Step 3: Implement** `acquireCache`, `removeCacheEntry`, `handleImageNotification` with the removing branch, the removal callback registration, the symbol-cache callback and flush, the seams, and the comments. Replace the "removal is effectively a no-op" comment with dyld's order (`notifyUnload` before `removeLoaders`).

- [ ] **Step 4: `make namespace`; run** `swift test --filter KSCrashRecordingCore_Tests` and `swift test --filter KSCrashRecording_Tests`. Expected: PASS.

- [ ] **Step 5: Commit** `Evict image and symbol cache entries when dyld removes an image`

---

### Task 3: UUID bytes live in the entry

**Why.** `KSBinaryImageRange.uuid` is a pointer into the mapped header, and `ksbic_getUUIDForHeader` returns it to the report writer, which reads 16 bytes through it inside the handler. With Task 2 the entry is gone before the image unmaps, so the remaining exposure is the window between a hit and the writer's read. Copying 16 bytes at populate time removes the pointer entirely, and a copy-out API is needed anyway because entries move when the sorted array shifts.

**What.** The entry holds `uint8_t uuid[16]` and `hasUUID`, filled in `populateCacheEntry` from the geometry's pointer into the still-mapped header. `ksbic_getUUIDForHeader` becomes `ksbic_copyUUIDForHeader`, returning `bool` and filling the caller's 16 bytes. The two callers copy out; the five existing UUID tests are rewritten against bytes.

**Pillars.**
- Speed: unchanged. A hit copies 16 bytes instead of returning a pointer.
- Correctness: the same 16 bytes, now owned by the entry; `ObjectUUID` is written only when the copy succeeds.
- Optimization: about 9 bytes more per entry (16 + flag, minus the pointer), 18 KB across 2048 entries, resident only as entries fill.
- Performance: unchanged.
- Reliability: no pointer into an image survives in the cache for the report writer to dereference.

**Files:**
- Modify: `Sources/KSCrashRecordingCore/include/KSBinaryImageCache.h:191`, `Sources/KSCrashRecordingCore/KSBinaryImageCache.c` (`KSBinaryImageRange`, `populateCacheEntry`, `ksbic_getUUIDForHeader` and its two uncached return sites), `Sources/KSCrashRecording/KSCrashReportC.c:983`, `Sources/KSCrashRecording/Monitors/KSCrashMonitor_System.m:193-201`
- Test: `Tests/KSCrashRecordingCoreTests/KSBinaryImageCache_Tests.m:662-730`

**Interfaces:**
- `KSBinaryImageRange`: `uint8_t uuid[16]; bool hasUUID;` replaces `const uint8_t *_Nullable uuid`.
- `bool ksbic_copyUUIDForHeader(const struct mach_header *_Nullable header, uint8_t *_Nonnull outUUID);` replaces `ksbic_getUUIDForHeader`. Same contract otherwise: a header not in the cache is populated from the header (the caller got it from a lookup, so it is mapped); false for NULL, for an image without `LC_UUID`, or when the header cannot be parsed. Documented with `@param` and `@return`.
- `KSCrashReportC.c`: `uint8_t uuid[16]; if (ksbic_copyUUIDForHeader(header, uuid)) { writer->addUUIDElement(writer, KSCrashField_ObjectUUID, uuid); }`.
- `KSCrashMonitor_System.m` `getAppUUIDInto`: copy into a local and pass it to `uuidBytesToStringInto`, else empty string as today.

- [ ] **Step 1: Rewrite the five existing tests and add one**

```objc
- (void)testCopyUUIDForHeader_ReturnsValidUUID        // true for the app header; not all zeros
- (void)testCopyUUIDForHeader_MatchesDynamicLinker    // memcmp with ksdl_binaryImageForHeader's uuid == 0
- (void)testCopyUUIDForHeader_DyldHasUUID             // true for ksbic_getDyldHeader()
- (void)testCopyUUIDForHeader_NullHeaderReturnsFalse
- (void)testCopyUUIDForHeader_ConsistentAcrossCalls   // two copies, memcmp == 0
- (void)testCopyUUIDForHeader_SurvivesEntryShift
{
    // high = makeSyntheticImage() (LC_UUID 0x42); ksbic_copyUUIDForHeader(high, a) caches it.
    // low = a second synthetic image whose page address is lower (allocate both, pick by address); cache low: it is inserted before high and shifts it.
    // Assert ksbic_copyUUIDForHeader(high, b) == true and b is sixteen 0x42 bytes.
}
```

- [ ] **Step 2: Run to verify compile failure.**

- [ ] **Step 3: Implement the fields, the copy API, and the two callers.**

- [ ] **Step 4: `make namespace`; `make all`; run** `swift test`, then `swift test --sanitize address` and `swift test --sanitize thread` (whole suite, no `--filter`). Expected: PASS.

- [ ] **Step 5: Commit** `Keep each cached image's UUID bytes in the entry`

---

## Follow-up, not in this branch

Measure the miss path before touching it. `ksbic_init` caches only the main executable and dyld, so in a crash the first lookup of every other image parses dyld's list in load order until one contains the address. `Tests/KSCrashBenchmarks/KSDynamicLinkerBenchmarks.swift` measures lookups; run it on device through the PR workflow. If a miss costs enough to matter across a report's distinct images, a candidate-by-greatest-load-address shortcut with a full-scan fallback is the change, as its own PR.

### Task 4: Record the reasoning where agents and users will read it

**Why.** Alex asked (2026-10-24) for a short account of why this branch chose a stamp-bracketed read, eviction at notification time, and UUID bytes by value, over bounded reads, lazy revalidation, per-hit verification and the rest, and why the smaller change is the better one. The design doc holds the long form; the two places people actually look are the agent rules and the wiki.

**What.** One rule file for agents and one wiki page for the 3.0 publish, each short, each stating what dyld does, what happens on Apple platforms, the three things kept, each thing dropped with its reason, and the principle to apply next time.

**Files:**
- Create: `.claude/rules/binary-image-cache.md`
- Create: `docs/wiki/Binary-Image-Cache-Safety.md`
- Modify: `.claude/CLAUDE.md` (one line in Architecture Overview pointing at the rule)

- [ ] **Step 1: Write both files from `docs/design/2026-10-23-image-cache-safety.md`.** No code changes, no tests.
- [ ] **Step 2: Commit** `Record why the image cache defends against what it does`
