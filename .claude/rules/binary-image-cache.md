---
paths:
  - "Sources/KSCrashRecordingCore/KSBinaryImageCache.c"
  - "Sources/KSCrashRecordingCore/include/KSBinaryImageCache.h"
  - "Sources/KSCrashRecordingCore/KSDynamicLinker.c"
---

# Binary Image Cache

The image cache (`KSBinaryImageCache.c`) and the symbol cache built on it
(`KSDynamicLinker.c`) answer every frame of every report from inside the crash
handler. A hit is a binary search over a static sorted array, acquired by one
atomic pointer exchange, with no kernel calls and no locks. Everything below
exists to keep that sentence true. Do not add work to the hit path to defend
against an event that does not happen.

## What dyld actually does

These are read from dyld's source, not from the header comments, and the code
comments at the list read and in the notifier repeat them.

- `dyld_all_image_infos.infoArray` is set to NULL while dyld rebuilds the list,
  on every load and every unload. Where the change stamp lands differs by dyld
  generation. dyld-1378 (macOS 15 era) writes the new stamp, the count, the
  stamp again, the pointer, rewriting the array in place. dyld-941 (macOS 12 /
  iOS 15, the floor) writes the count, the stamp, the pointer on an add (the
  push can reallocate and free the old buffer), and on a removal the count, the
  pointer, then the stamp last. Inside dyld the pointer and the stamp are
  `std::atomic`, so those are release stores; the count is a plain store. Items
  are removed on unload.
- dyld fires `dyld_image_removing` before it unmaps the image and frees the
  string behind `imageFilePath`. The notifier therefore sees a removal while the
  image is still mapped.
- An image is never unloaded if the main executable links it, it is in the
  shared cache, it has thread-local variables, or it carries ObjC classes.
  Swift code carries ObjC image info. On iOS no mainstream pattern unloads an
  image. On macOS, plugin hosts (Audio Unit v2, JNI, native C plugins) do.

## What the cache defends against, and how

- **A list rebuild racing a miss.** `ksbic_getImages` reads the stamp, the
  pointer and the count twice, with acquire loads, and accepts only an
  identical pair with a non-NULL pointer. The stamp brackets the other two on
  neither dyld generation, so no single load order is right for both; a rebuild
  landing inside either read NULLs the pointer or changes the count and the two
  snapshots differ. Six loads, three retries, then NULL. Zero syscalls.
- **An image dyld has announced it will unmap.** The notifier evicts the entry
  by `memmove` on the `dlclose` thread, then calls the registered removal
  callback, which the symbol cache uses to drop entries whose image base is that
  header. The notifier runs under dyld's lock and must never wait: if a handler
  holds a cache, the notifier sets a flush flag and the next successful acquire
  empties that cache. Entries come back through misses, as after install, and
  the miss path checks dyld's own header after the list, because dyld is not in
  its own list and a flush would otherwise lose it for the run. An add for a
  header already cached replaces the entry: dyld only announces new mappings,
  so what is there is a stale entry for the previous image or an identical one
  a miss inserted after dyld published the list. A lookup by header that misses
  answers from the header and does not insert: only dyld's list and notifier
  put images in the cache, so a removed image cannot be re-added by a report
  that still holds one of its frames.
- **A pointer into an image surviving in an entry.** The entry owns its 16 UUID
  bytes. `ksbic_copyUUIDForHeader` copies out, because entries also move when
  the sorted array shifts.

## What was considered and left out

Each of these was designed, then dropped, because the event it guards against
does not occur on the platforms that matter or its cost lands on every hit.

- Bounded `vm_read` of load commands and of dyld's array. Guards an unmap
  landing inside a handler's walk, a microsecond window, at the price of
  syscalls on every miss and a reader type nobody else needs.
- Lazy revalidation of entries against a change stamp on every hit. Eviction
  at notification time covers the same case with no per-hit work.
- Verifying each symbol cache hit against the image cache. Same case, same
  answer: evict at notification time.
- Copying names into the compact-mode referenced image set. Compact mode is
  off by default and the window needs an unload between a frame and the
  section of a non-fatal report.
- A faster miss path. A miss parses dyld's images in load order until one
  contains the address; picking the candidate by load address would make it
  one parse. It is a speed change to a path that already works, and no
  existing benchmark measures a miss (they all measure hits), so it waits for
  a cold-miss benchmark on device before it gets its own change.

## Still open, on purpose

A handler already walking an image when dyld unmaps it; a rebuild rewriting
`infoArray` in place under a reader that `ksbic_getImages` already accepted;
and, on arm64, dyld's plain count store becoming visible before the release
store that precedes it, so that both snapshots see the next version's count
with this version's pointer. All need the event to land in the nanoseconds
between a check and its use, the first on a platform where unloads do not
happen, and no reader-side load order closes the third. In a plugin host the crash being reported is
usually the use-after-`dlclose` itself. Closing these costs the hit path; a
proposal to close them must say what new evidence changed the odds.

## The principle

Defend against events that occur, at the moment they are announced, and prefer
one cold cache to a race. A flag and a `memmove` at notification time beat a
validation on every lookup. When a safety proposal for this code arrives, ask
first whether the event happens on iOS, then whether it can be handled when dyld
tells us rather than when a handler asks.
