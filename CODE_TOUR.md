A Brief Tour of the KSCrash Code and Architecture
=================================================

KSCrash used to be simple enough that a quick perusal of the source code would be enough to understand how it worked, but it's gotten big enough now that there should be some guideposts to help readers along. This document introduces you to the main code areas of KSCrash.


### The Heart of KSCrash

The heart of KSCrash lives in [`KSCrashC.c`](https://github.com/kstenerud/KSCrash/blob/master/Source/KSCrash/Recording/KSCrashC.c)

This file contains all of the most important access points to the KSCrash system.

`KSCrashC.c` functions are also Objective-C/Swift wrapped in [`KSCrash.m`](https://github.com/kstenerud/KSCrash/blob/master/Source/KSCrash/Recording/KSCrash.m)

These are the main parts of `KSCrashC.c`:

#### Installation

`kscrash_install()` installs and prepares the KSCrash system to handle crashes. You can configure KSCrash using the various configuration functions in this file (`kscrash_setMonitoring() and such`) before or after install.

#### Configuration

All of the main configuration settings are set via `kscrash_setXYZ()`.

#### App State

Apple operating environments offer a number of notifications that tell you the current app state. These are hooked into various `kscrash_notifyXYZ()` functions.

#### Crash Entry Point

The function `onCrash` is the main function called after a crash is reported. It handles examining the application state, writing the JSON crash report, and then allowing the crash to take its natural course.

#### Report Management

This file also contains the low level primitive functions for managing crash reports: `kscrash_getReportCount()`, `kscrash_getReportIDs()`, `kscrash_readReport()`, `kscrash_deleteReportWithID()`

#### Enabling / Disabling KSCrash

You can use `kscrash_setMonitoring()` to effectively enable or disable crash reporting at runtime.


### Detecting Crashes

Crashes are detected via one of the [monitors](https://github.com/kstenerud/KSCrash/tree/master/Source/KSCrash/Recording/Monitors), which set up the data in a consistent way before passing control to the function `onCrash()`. These files are a bit tricky because some of them have to jump through a few hoops to get around OS differences, system idiosyncrasies, and just plain bugs.


### Recording Crashes

Crashes are recorded to a JSON file via `kscrashreport_writeStandardReport()` in [`KSCrashReport.c`](https://github.com/kstenerud/KSCrash/blob/master/Source/KSCrash/Recording/KSCrashReport.c). It makes use of a number of [tools](https://github.com/kstenerud/KSCrash/tree/master/Source/KSCrash/Recording/Tools) to accomplish this.


### Report Management

Report management is primarily done in [`KSCrashReportStore.c`](https://github.com/kstenerud/KSCrash/blob/master/Source/KSCrash/Recording/KSCrashReportStore.c)


### Reporting

Reporting is done using a probably-overcomplicated system of [filters](https://github.com/kstenerud/KSCrash/tree/master/Source/KSCrash/Reporting/Filters) and [sinks](https://github.com/kstenerud/KSCrash/tree/master/Source/KSCrash/Reporting/Sinks). Generally, to adapt KSCrash to your needs, you'd create your own sink.


### Installations

The [installation](https://github.com/kstenerud/KSCrash/tree/master/Source/KSCrash/Installations) system was an attempt to make the user API a little easier by hiding most of the filter/sink stuff behind a simpler interface. Its success is debatable...

No code depends on the installation code, and KSCrash can actually work just fine without it.
