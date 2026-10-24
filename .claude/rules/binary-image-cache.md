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
  on every load and every unload. dyld then writes the count, the change stamp,
  and the pointer, in that order. Items are removed on unload.
- dyld fires `dyld_image_removing` before it unmaps the image and frees the
  string behind `imageFilePath`. The notifier therefore sees a removal while the
  image is still mapped.
- An image is never unloaded if the main executable links it, it is in the
  shared cache, it has thread-local variables, or it carries ObjC classes.
  Swift code carries ObjC image info. On iOS no mainstream pattern unloads an
  image. On macOS, plugin hosts (Audio Unit v2, JNI, native C plugins) do.

## What the cache defends against, and how

- **A list rebuild racing a miss.** `ksbic_getImages` loads the stamp, the
  count, the pointer, then the stamp again, and accepts only a non-NULL pointer
  bracketed by equal stamps. Three retries, then NULL. Zero syscalls.
- **An image dyld has announced it will unmap.** The notifier evicts the entry
  by `memmove` on the `dlclose` thread, then calls the registered removal
  callback, which the symbol cache uses to drop entries whose image base is that
  header. The notifier runs under dyld's lock and must never wait: if a handler
  holds a cache, the notifier sets a flush flag and the next successful acquire
  empties that cache. Entries come back through misses, as after install.
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

A handler already walking an image when dyld unmaps it, or a `dlopen` freeing
the old `infoArray` after `ksbic_getImages` accepted it. Both need the unmap or
the free to land in the microseconds between a check and its use, on a platform
where unloads do not happen. In a plugin host the crash being reported is
usually the use-after-`dlclose` itself. Closing these costs the hit path; a
proposal to close them must say what new evidence changed the odds.

## The principle

Defend against events that occur, at the moment they are announced, and prefer
one cold cache to a race. A flag and a `memmove` at notification time beat a
validation on every lookup. When a safety proposal for this code arrives, ask
first whether the event happens on iOS, then whether it can be handled when dyld
tells us rather than when a handler asks.
