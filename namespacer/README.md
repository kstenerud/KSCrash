Namespacer
==========

A tool to extract all public symbols from a codebase and provide the capability for a C `#define` that will artificially namespace them.

It works by leveraging `clang.cindex` to extract public symbols from C, C++, and Objective-C source files, which it then puts into a header file as defines:

```C
#ifdef KSCRASH_NAMESPACE

#define KSCRASH_NS2(NAMESPACE, SYMBOL) SYMBOL##NAMESPACE
#define KSCRASH_NS1(NAMESPACE, SYMBOL) KSCRASH_NS2(NAMESPACE, SYMBOL)
#define KSCRASH_NS(SYMBOL) KSCRASH_NS1(KSCRASH_NAMESPACE, SYMBOL)

#define AppMemory KSCRASH_NS(AppMemory)
...
```

If a user defines `KSCRASH_NAMESPACE` as `_mylib`, for example, symbols such as `AppMemory` will be written to the binary as `AppMemory_mylib`, effectively "namespacing" them (although they would still appear as-is in source form - excepting in Swift, which only interprets the post-processed code).


Usage
-----

    python namespacer.py <source-tree> <output-header-file>

In this codebase, `source-tree` is the `Sources` directory, and the header file is `Sources/KSCrashCore/include/KSCrashNamespace.h` (see [generate.sh](generate.sh)).


Updating
--------

As public symbols are added/removed/changed in the codebase, this script must be run again in order to keep everything in sync.
