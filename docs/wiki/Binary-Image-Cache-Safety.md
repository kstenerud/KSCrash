# Binary Image Cache Safety

Every frame in a KSCrash report is resolved from inside the crash handler: which
image contains this address, what is its slide, its UUID, its unwind sections,
which symbol is nearest. KSCrash answers those questions from an in-process
cache rather than asking dyld each time. A hit is a binary search over a static
sorted array, acquired with one atomic pointer exchange. There are no kernel
calls and no locks on that path, which is what lets it run with every other
thread suspended.

This page explains what that cache has to be careful about, what it does about
it, and why it does so little. The choices here were made against the
alternatives, not in ignorance of them.

## What dyld does

The cache reads dyld's own `dyld_all_image_infos` struct and listens to dyld's
image notifier. Two facts from dyld's source shape everything else.

First, dyld publishes the image list as **NULL while it rebuilds it**, on every
load and every unload, then writes the count, a change stamp, and the array
pointer, in that order. A reader that loads the count and the pointer as two
independent steps can pair an old array with a new count.

Second, dyld fires its **removal notification before it unmaps** the image and
frees the string behind its path. So when KSCrash hears that an image is going,
the image is still there, and every pointer into it is about to dangle.

## What happens on Apple platforms

Images are almost never unloaded. dyld refuses to unload an image that the main
executable links, that lives in the shared cache, that has thread-local
variables, or that carries Objective-C classes. Swift code carries Objective-C
image info, so it stays too. What is left is a plain C or C++ dylib the app
`dlopen`ed itself. On iOS no mainstream pattern does this. On macOS, plugin
hosts do: Audio Unit v2 hosts, Java through JNI, apps with native C plugins.

The list rebuild, by contrast, happens on every `dlopen` on every platform. It
lasts the microseconds dyld spends rebuilding a vector, and a crash on another
thread has to land inside it. Rare, but on the crash path of every report,
because the cache starts with only the main executable and dyld and fills the
rest through misses that read dyld's list.

## What KSCrash does

Three things, each at the moment the hazard is announced rather than on every
lookup.

**The list read is bracketed by dyld's change stamp.** Load the stamp, the
count, the pointer, then the stamp again; accept only a non-NULL pointer with
equal stamps on both sides; retry three times, then report no list. This costs
four loads from a struct that is always mapped. No syscall.

**Removal evicts.** When dyld announces an image's removal, the notifier removes
that image's entry from the sorted array and then tells the symbol cache, which
drops every entry whose image base is that header. The notifier runs on the
thread calling `dlclose`, under dyld's lock, and must never wait. If a crash
handler happens to hold one of the caches at that instant, the notifier sets a
flag instead, and the next successful acquire of that cache empties it. The
entries come back through misses, exactly as they do after install. One cold
cache is the price of never making `dlclose` wait on a suspended handler.

**UUID bytes live in the entry.** Each entry copies its image's 16 UUID bytes
when it is populated from the still-mapped header. Nothing in the cache points
into an image any more, and the report writer copies the bytes out, because
entries also move when a lower address is inserted into the sorted array.

## What KSCrash deliberately does not do

Each of these was designed before it was dropped.

- **Bounded reads** (`vm_read`) of load commands and of dyld's array, so an
  unmap landing inside a handler's walk would fault into an error instead of a
  crash. That window is microseconds wide, on a platform where unmaps already
  do not happen, and the price is a syscall on every cache miss plus a reader
  type the rest of the code does not need.
- **Revalidating every hit** against a change stamp. Eviction at notification
  time covers the same case without touching the hit path.
- **Checking every symbol cache hit** against the image cache. Same case, same
  answer.
- **Copying image names** into the report's referenced image set, for the
  compact binary images mode. That mode is off by default, and the window needs
  an unload to land between a frame and the images section of a non-fatal
  report.
- **A faster miss path.** A cache miss today parses dyld's images in load
  order until one contains the address. Picking the candidate by load address
  would cut that to one parse, but it is a speed change to a path that already
  works, so it waits for the device benchmarks to say what a miss costs before
  it gets its own change.

## What stays open

A handler that is already walking an image when dyld unmaps it, and a `dlopen`
that frees the old list after the stamp check accepted it but before the caller
finished reading. Both need the unmap or the free to land in the microseconds
between a check and its use, on a platform where unloads do not occur. In a
plugin host that does unload, the crash being reported is usually the
use-after-`dlclose` itself. Closing these would cost every hit of every report,
and the code comment at the list read says so.

## Why simple won

A crash reporter that slows down the app it watches, or that fails inside the
handler because its own safety machinery took a lock or made a syscall at the
wrong moment, has failed at its one job. Every defense added to the hit path is
paid by every frame of every report on every device, while the events those
defenses guard against are confined to one platform and to a window measured in
microseconds. The rule that came out of this work: defend against events that
occur, handle them when dyld announces them rather than when a handler asks,
and prefer one cold cache to a race. A flag and a `memmove` at notification
time beat a validation on every lookup.
