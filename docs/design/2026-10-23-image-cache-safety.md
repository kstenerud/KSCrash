# Binary image cache: list rebuilds and image removal

## Intent

The in-process binary image cache (`KSBinaryImageCache.c`) and the symbol lookup
built on it (`KSDynamicLinker.c`) answer every frame of every report. They are
fast: a hit is a binary search with no kernel calls, and dyld's notifier
pre-populates images loaded after install. Two assumptions in the code are
contradicted by dyld's source:

- The comment above `ksbic_getImages` says items are never removed from
  `infoArray` and the count is written after the array. dyld-1378 removes items
  on unload, publishes `infoArray` as NULL while it rebuilds the list on every
  load and unload, and writes the count before the pointer.
- The notifier ignores `dyld_image_removing` "because dlclose doesn't actually
  unload". It does unload a pure C or C++ dylib the app loaded itself.

This design fixes both with the smallest change that is actually correct, and
records what it deliberately leaves alone and why.

## Facts this rests on

- `dyld_images.h` (SDK): "If infoArray is NULL, it means it is being modified,
  come back later."
- dyld-1378 `ExternallyViewableState::addImages` and `removeImages` both do
  `infoArray = nullptr`, rebuild, then write `infoArrayCount`,
  `infoArrayChangeTimestamp`, `infoArray`, in that order, then call
  `notification(mode, count, info)`.
- dyld-1378 `RuntimeState`: `notifyUnload` (which calls `removeImages` and so
  fires `dyld_image_removing`) runs before `removeLoaders`, which unmaps the
  image and frees its `Loader`. The `Loader`'s `path()` is what
  `imageFilePath` points at. So the notifier sees a removal while the image is
  still mapped, and after `removeLoaders` both the image and its path string
  are gone.
- `removeLoaders` never unmaps a shared-cache dylib or an `RTLD_NODELETE` image.
  `dlclose(3)`: an image is never unloaded if the main executable links it, it
  is in the shared cache, it has thread-local variables, or it contains ObjC
  classes. Swift code on Apple platforms carries ObjC image info.
- `KSCrashMonitor.c` allows up to 200 reports in flight; reports are not
  serialized.
- Deployment floor is iOS 15 / macOS 12, so `infoArrayChangeTimestamp` is
  always present.

## What actually happens on Apple platforms

Unloading requires a dylib the app `dlopen`ed itself, that nothing links, that
is not in the shared cache, with no thread-locals and no ObjC or Swift content.
On iOS no mainstream pattern does this. On macOS it happens in plugin hosts:
Audio Unit v2 hosts, JNI, apps with native C plugins. KSCrash's macOS users
are a small share.

The list-rebuild window opens on every `dlopen`, on every platform, and lasts
the microseconds dyld spends rebuilding a vector. A crash on another thread has
to land inside it.

`ksbic_init` caches only the main executable and dyld; the notifier covers
images loaded after install. So in a crash, the first lookup of every other
image is a miss that reads dyld's list. The list read is on the crash path of
every report, even though the race it is exposed to is rare.

## Goals

- `ksbic_getImages` never returns a pointer and count from two different
  versions of the list, and returns NULL while dyld is rebuilding it.
- After dyld announces an image's removal, no cache entry, image or symbol,
  answers for it. dyld announces before it unmaps, so this runs ahead of the
  hazard.
- The report writer never dereferences a pointer into an image to read a UUID.
- The hit path stays as it is: zero kernel calls, no new validation.

## Non-goals, with the reason each was dropped

- Bounded (`vm_read`) reads of load commands and dyld's array. They protect
  against an unmap landing inside a handler's walk, a microsecond window on a
  platform where unmaps already do not happen, at the cost of a reader type, a
  cursor type and syscalls on the miss path.
- Stamp-based lazy revalidation of cache entries. Eviction at notification
  time covers the same case without per-hit work. The one gap (a removal that
  lands while a handler holds the cache) is covered by a flush flag.
- Verifying symbol cache hits against the image cache. Same case, same
  answer: evict the symbol entries at notification time.
- Copying names and metadata into the compact-mode referenced set. Compact
  mode is off by default and the window (an unload between a frame and the
  section of a non-fatal report) needs an unload.
- UUIDs by value in `KSBinaryImage` and `KSSymbolInformation`. Those results
  are filled from a live image at lookup time; the pointer-lifetime concern is
  the one every `dladdr` caller has.
- A faster miss path (candidate header by load address). It is a performance
  change, not a safety one, and belongs in its own PR after the device
  benchmarks say what a miss costs today.

## Design

### 1. A consistent read of dyld's list

`ksbic_getImages` loads the stamp, the count, the pointer, then the stamp again,
all with acquire loads from dyld's own struct (always mapped, so no syscall),
and accepts only a non-NULL pointer bracketed by equal stamps, retrying three
times before returning NULL. dyld writes NULL, then the count, then the stamp,
then the pointer. A count read after the first stamp and a pointer read before
the second, with both stamps equal, were therefore published together under
that stamp. Three independent loads could pair an old pointer with a new count.

The signature does not change; every caller, including some forty tests, keeps
working. The comment above the atomics is rewritten to say what dyld does.

### 2. Eviction on `dyld_image_removing`

The notifier runs on the `dlclose` thread under dyld's lock and must not wait.
It acquires the cache by atomic exchange and removes each named header from the
sorted array. If a handler holds the cache at that moment, it sets a flush flag
instead, and the next successful acquire empties the cache; images are then
repopulated by misses as today. A flush trades one cold cache for a race that
needs a `dlclose` to coincide with a handler.

The image cache then calls a registered removal callback per header, the mirror
of `ksbic_registerForImageAdded`. `KSDynamicLinker.c` registers one that drops
symbol cache entries whose image base is that header, with the same flag
fallback when the symbol cache is held. Symbol entries hold `dli_sname`
pointers into the image's string table, so they go when the image goes.

### 3. UUID bytes live in the entry

`KSBinaryImageRange.uuid` becomes a 16-byte copy plus `hasUUID`, filled when
the entry is populated from the still-mapped header. `ksbic_getUUIDForHeader`
becomes `bool ksbic_copyUUIDForHeader(header, uint8_t out[16])`, because
entries move when the sorted array shifts and a pointer into an entry is not
stable either. The report writer and the system monitor copy out.

## What stays open

- A handler that is already walking an image when dyld unmaps it. dyld
  notifies before it unmaps, and the notifier evicts first, so this needs the
  unmap to land in the microseconds between a hit and the writer's use of it.
- A `dlopen` that frees the old `infoArray` buffer after `ksbic_getImages`
  accepted it and before the caller finishes reading. Same window, same odds.
- Both of those on a platform where unloads do not happen, and in a plugin host
  where the crash being reported is usually the use-after-`dlclose` itself.

These are stated in the code comment at the list read.

## Follow-up, measured first

The miss path parses images in dyld's order until one contains the address.
With `ksbic_init` caching only two images, a typical crash report pays this for
every image it touches. No existing benchmark measures it: every lookup in
`Tests/KSCrashBenchmarks/KSDynamicLinkerBenchmarks.swift` goes through
`ksdl_dladdr` and `measure` repeats its block, so after the first pass every
lookup is a hit.

The follow-up PR adds a cold-miss benchmark as its first commit, before any
shortcut: reset both caches at the top of each measured pass, resolve the last
twenty images in dyld's list (the worst case for a scan in load order) through
`ksbic_findImageForAddress` so the symbol walk is not on top, and register it in
`.github/data/benchmark-tests.json`. The class is already in a device shard and
in both build systems. The PR comment then shows before and after on the same
device, and the numbers decide whether a candidate-by-load-address shortcut is
worth landing.
