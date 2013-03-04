KSCrash
=======

#### The Ultimate iOS Crash Reporter


### Another crash reporter? Why?

Because while the existing crash reporters do report crashes, there's a heck
of a lot more that they COULD do. Here are some key features of KSCrash

* On-device symbolication in a way that supports re-symbolication offline
  (necessary for iOS versions where many functions have been redacted).
* Generates full Apple reports, with every field filled in.
* Handles errors that can only be caught at the mach level, such as stack
  overflow.
* Handles a crash in the crash handler itself (or in the user crash handler
  callback).
* Detects deadlocks in the main loop.
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

[Click here for some examples of the reports it can generate.](https://github.com/kstenerud/KSCrash/tree/master/ExampleReports)



### Beta Note

Although it's now being shipped in production apps, KSCrash is still
officially considered "beta" software because there are a few more
things to do before releasing version 1.0.

The following feature has been causing problems. Please don't use it until
I've found a more robust solution.

- Deadlock detection

The following features are newer and not as tested as the rest:

- Objective-C introspection.

These features are being used in deployed systems, but have not had as much
exposure as the rest of the library.

Also, the backend side is not done yet, though Hockey and Quincy integration
is fully implemented and working (more on the way as time allows).

And finally, the documentation sucks :P



### How to build it

1. Select the **KSCrash** scheme.
2. Choose **iOS Device**.
3. Select **Archive** from the **Products** menu.

When it has finished building, it will show you the framework in Finder. You
can use it like you would any other framework.


### How to use it

1. Add the framework to your project (or add the KSCrash project as a
   dependency)

2. Add the following to your **[application: didFinishLaunchingWithOptions:]**
   method in your app delegate:

.

    #import <KSCrash/KSCrash.h>
    // Include to use the standard reporter.
    #import <KSCrash/KSCrashReportSinkStandard.h>
    // Include to use Quincy or Hockey.
    #import <KSCrash/KSCrashReportSinkQuincy.h>

	- (BOOL)application:(UIApplication*) application didFinishLaunchingWithOptions:(NSDictionary*) launchOptions
	{
    	id<KSCrashReportFilter> sink = [KSCrashReportSinkStandard sinkWithURL:myAPIURL onSuccess:nil];
	    // OR:
    	id<KSCrashReportFilter> sink = [KSCrashReportSinkHockey sinkWithAppIdentifier:hockeyAppID onSuccess:nil];
	    // OR:
    	id<KSCrashReportFilter> sink = [KSCrashReportSinkQuincy sinkWithURL:myQuincyURL onSuccess:nil];

	    [KSCrash installWithCrashReportSink:sink];
	    …
	}

And you're done! If a crash occurs, it will store a report. Upon relaunch, it
will automatically contact the server and upload the report whenever the device has internet access.


Advanced Usage
--------------

### Enabling on-device symbolication

On-device symbolication requires basic symbols to be present in the final
build. To enable this, go to your app's build settings and set **Strip Style**
to **Debugging Symbols**. Doing so increases your final binary size by about
5%, but you get on-device symbolication.


### Passing extra information to the crash reporter

You can pass a dictionary to KSCrash, which will get stored to the "user_data"
portion of a crash report:

    [KSCrash installWithCrashReportSink:sink
                               userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                         @"username", someUsername,
                                         nil]
                        zombieCacheSize:16384
               deadlockWatchdogInterval:5.0f
                     printTraceToStdout:NO
                                onCrash:nil];


### Passing extra info to the crash reporter during a crash

If you have extra information at crash time that would be useful on a crash
report, you can provide an **onCrash** function:

    static void onCrash(const KSReportWriter* writer)
    {
        writer->addStringElement(writer, "sprocketID", g_sprocketID);
    }
    
    - (void) installCrashHandler
    {
        [KSCrash installWithCrashReportSink:sink
                                   userInfo:nil
                         printTraceToStdout:YES
                                    onCrash:onCrash];
    }

**Warning**: onCrash will be called in a **crashed** context. This is a
**VERY DANGEROUS** state since for all we know the memory has been trampled
over and nothing's valid anymore. As well, calling any functions that create
locks could potentially deadlock, so you must
[only call async-safe functions](https://www.securecoding.cert.org/confluence/display/seccode/SIG30-C.+Call+only+asynchronous-safe+functions+within+signal+handlers).
**DO NOT CALL OBJECTIVE-C METHODS FROM THIS FUNCTION!!!**

It's generally best to avoid using this feature unless absolutely necessary.


### Deferring server reporting

If you don't want it to report to the server right away, you can pass nil as
the sink parameter:

    [KSCrash installWithCrashReportSink:nil];

It will still install the crash reporter, and will still record crashes, but it
won't attempt to report to an external API until you assign it a sink:

    #import <KSCrash/KSCrashAdvanced.h>

	[KSCrash instance].sink = [KSCrashReportSinkStandard sinkWithURL:myAPIURL onSuccess:nil];
	
You'll then need to manually trigger the start of crash report uploading:

	[[KSCrash instance] sendAllReportsWithCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error) {
        	// All reports uploaded.
	}];


KSCrashLite
-----------

KSCrashLite is intended for use in custom crash frameworks that have special needs. It doesn't
include any sinks (except for console); it is expected that the user will supply their own.
Unlike the regular KSCrash framework, KSCrashLite has no dependencies on MessageUI.framework or
zlib (it still requires SystemConfiguration.framework).


Examples
--------

The workspace includes two example apps, which demonstrate using KSCrash and
KSCrashLite.


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
