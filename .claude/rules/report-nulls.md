---
paths:
  - "Sources/KSCrashRecording/KSCrashReportC.c"
  - "Sources/KSCrashRecording/KSCrashReportStoreC.m"
  - "Sources/KSCrashRecording/KSCrashReportStore.m"
  - "Sources/KSCrashRecording/KSCrashReportRunId.m"
  - "Sources/KSCrashMonitorPlugins/ReportSectionWriter.swift"
---

# A Report Holds No Nulls

Absence is a report's only "no value". A key that is present has a value under
it, and an array index means the same thing to every reader. This is the same
rule the metadata bag already follows (see `metadata-store.md`), applied to the
whole report.

Two reasons it is a contract and not a preference. A consumer that walks a
report would otherwise need a null check at every single access to be safe, and
the filters alone index the report in far more places than anyone will keep
guarded. And a reader that resolves a null by dropping it re-indexes the array
holding it, so an array carrying nulls means something different depending on
who read it.

## The write side omits

A value the producer does not have adds no element. `addStringElement`,
`addUUIDElement` and `addFloatingPointElement` in `KSCrashReportC.c` return
early rather than write one, which is the enforcement point for every caller
present and future: fixing it there rather than at each callsite is what keeps
the next unguarded call from reopening the hole. The codec keeps
`ksjson_addNullElement`, since the codec writes whatever JSON its caller asks
for; the report writer is the layer that refuses.

A non-finite double is refused for the same reason, not a different one. JSON
has no NaN and no infinity, so the number formatter spells them `null` and
`1e999`, and the second is worse than the first: a strict reader rejects the
document, so one unwritable number strands the whole report.

In an array this means the element is not added at all, so an array is only as
long as the values that existed. Nothing KSCrash writes puts a scalar it might
not have into an array (the report's arrays hold objects, and the profiler's
`samples[].frames` holds indexes it always has), so this costs nothing today.
Do not introduce an array whose elements can be missing, since a shorter array
and a null-holding one are equally unreadable to a consumer counting positions.

## The read side drops

Reports written before this contract, and reports from a foreign writer, can
still hold nulls. Every path that decodes a report passes
`KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject`,
so those nulls resolve to absence before anything sees them:
`readReportAtPath` and `kscrs_finalizeReport` in `KSCrashReportStoreC.m`,
`extractRunIdWithFullDecode` in `KSCrashReportRunId.m`, and the report load in
`KSCrashReportStore.m`. Adding a report decode means passing them too.

## The doors nulls can still come through

JSON handed to the writer whole is never inspected on the way in, and lands on
disk as given:

- the app's `user` section, copied verbatim from the JSON it set
  (`addJSONElement` in `KSCrashReportC.c`)
- `customStackTrace` on the user-reported-exception path
- `ReportSectionWriter.encode` from a Swift monitor

The read side above is what resolves those. A Swift monitor's payload should
not emit nulls in the first place: a nil member is an omitted member, which is
what `JSONEncoder` does with a synthesized `Codable` already.
