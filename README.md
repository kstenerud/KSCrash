KSCrash
=======

#### The Ultimate iOS Crash Reporter

### Beta Note

KSCrash is "beta" software for two reasons:

1. Though it has received months of testing, I have not yet deployed it into
   one of my live apps. Until then, I cannot in good faith call it "production"
   code.

2. I haven't written a decent server-side API for it yet (I have a really
   crappy API server + webapp that I wrote using Django and Cappuccino that I'd
   be embarrassed to show anyone. If you can help with this effort, let me
   know!). It does work with Hockey and Quincy, and I'll be adding support for
   other services soon.


### Another crash reporter? Why?

Because all existing solutions fall short. PLCrashReporter comes very close,
but not quite:

* It can't handle stack overflow crashes.
* It doesn't fill in all fields for its Apple crash reports.
* It can't symbolicate on the device.
* It only records enough information for an Apple crash report, though there is
  plenty of extra useful information to be gathered!

As well, each crash reporter service, though most of them use PLCrashReporter
at the core, has its own format and API.

#### KSCrash is superior for the following reasons:

* It catches ALL crashes.
* Its pluggable server reporting architecture makes it easy to adapt to any API
  service (it already supports Hockey and Quincy and sending via email, with
  more to come!).
* It supports symbolicating on the device.
* It records more information about the system and crash than any other crash
  reporter.
* It is the only crash reporter capable of creating a 100% complete Apple crash
  report (including thread/queue names).
* It can be compiled with or without ARC.

[Click here for some examples of the reports it can generate.](https://github.com/kstenerud/KSCrash/tree/master/ExampleReports)


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


### Using the low level crash reporting API

KSCrash is written in two layers: The part that records crashes, and the part
that sends crashes to a server. If you want to do your own high level
implementation, you can use **KSCrashLite.framework** (basically everything
inside the "Reporting" source tree) as your base and build upon that.


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
