KSCrash Architecture
====================

KSCrash is implemented as a layered architecture. Each layer can in theory be
compiled without the layers adjacent or above.

    +-------------------------------------------------------------+
    |                         Installation                        |
    |        +----------------------------------------------------+
    |        |                  KSCrash                           |
    |    +--------------------------------------------------------+
    |    | Crash Reporting | Crash Recording | Crash Report Store |
    +----+-----------------+-----------------+--------------------+
    |       Filters        |     Monitors    |
    +----------------------+-----------------+


### Installation

This top level layer provides a "clean" interface to the crash system.
It is expected that the API at this level will be largely idiomatic to
the backend system it will be communicating with.

Primary entry points: KSCrashInstallation.h, KSCrashInstallationXYZ.h


### KSCrash

Handles high level configuration and installation of the crash recording and
crash reporting systems.

Primary entry point: KSCrash.h


### Crash Report Store

Provides storage and retrieval of crash reports and other configuration data.
Also provides file paths for more primitive access by other layers.

Primary entry point: KSCrashReportStore.h


### Crash Recording

Records a single crash event. This layer is implemented in async-safe C.

Primary entry point: KSCrashC.h


### Crash Reporting

Processes, transforms, and sends reports to a remote system.

Primary entry point: KSCrash.h


### Monitors

Traps application errors and passes control to a supplied function.
It handles the following errors:

* Mach Exception
* Signal
* NSException
* Main Thread Deadlock

Primary entry point: KSCrashMonitor.h


### Filters

Low level interface for transforming, processing, and sending crash reports.

Primary entry points: KSCrashReportFilter.h, KSCrashReportFilterXYZ.h
