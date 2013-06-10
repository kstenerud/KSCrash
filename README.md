KSCrash
=======

#### The Ultimate iOS Crash Reporter


### Another crash reporter? Why?

Because while the existing crash reporters do report crashes, there's a heck
of a lot more that they COULD do. Here are some key features of KSCrash:

* On-device symbolication in a way that supports re-symbolication offline
  (necessary for iOS versions where many functions have been redacted).
* Generates full Apple reports, with every field filled in.
* Handles errors that can only be caught at the mach level, such as stack
  overflow.
* Handles a crash in the crash handler itself (or in the user crash handler
  callback).
* Detects zombie (deallocated) object access attempts.
* Recovers lost NSException messages in cases of zombies or memory corruption.
* Introspects objects in registers and on the stack (C strings and Objective-C
  objects, including ivars).
* Extracts information about objects referenced by an exception (such as
  "unrecognized selector sent to instance 0xa26d9a0")
* Its pluggable server reporting architecture makes it easy to adapt to any API
  service (it already supports Hockey and Quincy and sending via email, with
  more to come!).
* Dumps the stack contents.
* Diagnoses crash causes (Crash Doctor).
* Records lots of information beyond what the Apple crash report can, in a JSON
  format.
* Supports including extra data that the programmer supplies (before and during
  a crash).

KSCrash handles the following kinds of crashes:

* Mach kernel exceptions
* Fatal signals
* C++ exceptions
* Objective-C exceptions
* Main thread deadlock (experimental)
* Custom crashes (e.g. from scripting languages)

[Here are some examples of the reports it can generate.](https://github.com/kstenerud/KSCrash/tree/master/Example-Reports/_README.md)


### Beta Note

Although it's now being shipped in production apps, KSCrash is still
officially considered "beta" software because there are a few more
things to do before releasing version 1.0.

The following feature has been causing problems. Please don't use it until
I've found a more robust solution.

- Deadlock detection

Also, the backend side is not done yet, though Hockey, Quincy, and email
integration is fully implemented and working (more on the way as time allows).


### Incompatible API Change Notice

As of Jan 29th, 2013, I've modified the KSCrash main API to use properties
rather than init method parameters for configuration. With all the new options,
things were starting to get a bit unwieldly. This should mark the last major
API change.

Note: The preferred method for initializing KSCrash is now via the installation
      objects rather than using filters directly. See "How to Use KSCrash" for
      details.



How to Build KSCrash
--------------------

1. Select the **KSCrash** scheme.
2. Choose **iOS Device**.
3. Select **Archive** from the **Products** menu.

When it has finished building, it will show you the framework in Finder. You
can use it like you would any other framework.



How to Use KSCrash
------------------

1. Add the framework to your project (or add the KSCrash project as a
   dependency)

2. Add the flag "-ObjC" to **Other Linker Flags** in your **Build Settings**

3. Add the following to your **[application: didFinishLaunchingWithOptions:]**
   method in your app delegate:

.

    #import <KSCrash/KSCrash.h>
    // Include to use the standard reporter.
    #import <KSCrash/KSCrashInstallationStandard.h>
    // Include to use Quincy or Hockey.
    #import <KSCrash/KSCrashInstallationQuincyHockey.h>
    // Include to use the email reporter.
    #import <KSCrash/KSCrashInstallationEmail.h>
    // Include to use Takanashi.
    #import <KSCrash/KSCrashInstallationTakanashi.h>

	- (BOOL)application:(UIApplication*) application didFinishLaunchingWithOptions:(NSDictionary*) launchOptions
	{
      KSCrashInstallationStandard* installation = [KSCrashInstallationStandard sharedInstance];
      installation.url = [NSURL URLWithString:@"http://put.your.url.here"];

      // OR:

      KSCrashInstallationQuincy* installation = [KSCrashInstallationQuincy sharedInstance];
      installation.url = [NSURL URLWithString:@"http://put.your.url.here"];

      // OR:

      KSCrashInstallationHockey* installation = [KSCrashInstallationHockey sharedInstance];
      installation.appIdentifier = @"PUT_YOUR_HOCKEY_APP_ID_HERE";

      // OR:

      KSCrashInstallationEmail* installation = [KSCrashInstallationEmail sharedInstance];
      installation.recipients = @[@"some@email.address"];

      // Optional (Email): Send Apple-style reports instead of JSON
      [installation setReportStyle:KSCrashEmailReportStyleApple useDefaultFilenameFormat:YES]; 

      // Optional: Add an alert confirmation (recommended for email installation)
      [installation addConditionalAlertWithTitle:@"Crash Detected"
                                         message:@"The app crashed last time it was launched. Send a crash report?"
                                       yesAnswer:@"Sure!"
                                        noAnswer:@"No thanks"];

      // OR:

      KSCrashInstallationTakanashi* installation = [KSCrashInstallationTakanashi sharedInstance];
      installation.url = [NSURL URLWithString:@"https://put.your.url.here/api/v1/crash/<application key>"];

      [installation install];
	    …
	}

This will install the crash sentry system (which intercepts crashes and stores
reports to disk). Note that there are other properties you can and probably
will want to set for the various installations.

Once you're ready to send any outstanding crash reports, call the following:

    [installation sendAllReportsWithCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error)
     {
         // Stuff to do when report sending is complete
     }];



Recommended Reading
-------------------

If possible, you should read the following header files to fully understand
what features KSCrash has, and how to use them:

* KSCrash.h
* KSCrashAdvanced.h
* KSCrashInstallation.h
* KSCrashInstallation(SPECIFIC TYPE).h
* Architecture.md



Advanced Usage
--------------

### Enabling on-device symbolication

On-device symbolication requires basic symbols to be present in the final
build. To enable this, go to your app's build settings and set **Strip Style**
to **Debugging Symbols**. Doing so increases your final binary size by about
5%, but you get on-device symbolication.


### Enabling advanced functionality:

KSCrash has advanced functionality that can be very useful when examining crash
reports in the wild. Some involve minor trade-offs, so most of them are
disabled by default.


#### Custom User Data (userInfo in KSCrash.h)

You can store custom user data to the next crash report by setting the
**userInfo** property in KSCrash.h.


#### Zombie Tracking (zombieCacheSize in KSCrash.h)

KSCrash has the ability to detect zombie instances (dangling pointers to
deallocated objects). It does this by recording the address and class of any
object that gets deallocated. It stores these values in a cache, keyed off the
deallocated object's address. This means that the smaller you set the cache
size, the greater the chance that a hash collision occurs and you lose
information about a previously deallocated object.

With zombie tracking enabled, KSCrash will also detect a lost NSException and
print its contents. Certain kinds of memory corruption or stack corruption
crashes can cause the exception to deallocate early, further twarting efforts
to debug your app, so this feature can be quite handy at times.

Each cache entry takes up 8 bytes on a 32-bit architecture, and 16 bytes on a
64-bit architecture. The recommended minimum is 16384, which translates to
128k of RAM used for zombie tracking on a 32-bit machine. Generally, the more
objects you tend to have in your app, the larger you'll want to make the cache.

Trade off: Zombie tracking at the cost of adding very slight overhead to object
           deallocation, and having some memory reserved.


#### Deadlock Detection (deadlockWatchdogInterval in KSCrash.h)

If your main thread deadlocks, your user interface will become unresponsive,
and the user will have to manually shut down the app (for which there will be
no crash report). With deadlock detection enabled, a watchdog timer is set up.
If anything holds the main thread for longer than the watchdog timer duration,
KSCrash will shut down the app and give you a stack trace showing what the
main thread was doing at the time.

This is wonderful, but you must be careful: App initialization generally
occurs on the main thread. If your initialization code takes longer than the
watchdog timer, your app will be forcibly shut down during start up! If you
enable this feature, you MUST ensure that NONE of your normally running code
holds the main thread for longer than the watchdog value! At the same time,
you'll want to set the timer to a low enough value that the user doesn't
become impatient and shut down the app manually before the watchdog triggers!

Trade off: Deadlock detection, but you must be a lot more careful about what
           runs on the main thread!


#### Memory Introspection (introspectMemory in KSCrash.h)

When an app crashes, there are usually objects and strings in memory that are
being referenced by the stack, registers, or even exception messages. When
enabled, KSCrash will introspect these memory regions and store their contents
in the crash report.

You can also specify a list of classes that should not be introspected by
setting the **doNotIntrospectClasses** property in KSCrash.


#### Custom crash handling code (onCrash in KSCrash.h)

If you want to do some extra processing after a crash occurs (perhaps to add
more contextual data to the report), you can do so.

However, you must ensure that you only use async-safe code, and above all else
never call Objective-C code from that method! There are many cases where you
can get away with doing so anyway, but there are certain classes of crashes
where handler code that disregards this warning will cause the crash handler
to crash! Note that if this happens, KSCrash will detect it and write a full
report anyway, though your custom handler code may not fully run.

Trade off: Custom crash handling code, but you must be careful what you put
           in it!


#### KSCrash log redirection (KSCrashAdvanced.h)

This takes whatever KSCrash would have printed to the console, and writes it
to a file instead. I mostly use this for debugging KSCrash itself, but it could
be useful for other purposes, so I've exposed an API for it.



KSCrashLite
-----------

KSCrashLite is intended for use in custom crash frameworks that have special
needs. It doesn't include any sinks (except for console); it is expected that
the user will supply their own. Unlike the regular KSCrash framework,
KSCrashLite has no dependencies on MessageUI.framework or zlib (it still
requires SystemConfiguration.framework).



Examples
--------

The workspace includes some example apps, which demonstrate common KSCrash
usage. Please look at the top of AppDelegate.m in each app for a description
of what it does.



License
-------

Copyright (c) 2012 Karl Stenerud

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
the documentation of any redistributions of the template files themselves
(but not in projects built using the templates).

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
