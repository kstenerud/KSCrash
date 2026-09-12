# Monitor Layer Restack Plan

> Restructures the 3.0 branch stack so the #867 Swift monitor layer becomes its
> foundation. Held until the current `ac/install` feedback rounds finish.

**Goal:** Land the Swift monitor layer (`CrashMonitor` / `Monitor<M>` /
`MonitorHost`) at the bottom of the stack so every branch above it can use it,
\#867 shrinks to pure extension work, and the layer can merge to `develop`
first.

**Why the bottom:** the layer commit (`72e83e29f`, "Add a Swift monitor
protocol and bridge", 24 files, +1524/−20) is self-contained against a
develop-era base, down to its C prerequisites (`KSAtomicFlag`, the API's
stitch-priority slot, the registry duplicate-id trap, `ReportSectionWriter`,
its own test targets). At that base its `WrittenReport.id: Int64?` is correct;
the `Report.ID` adaptation belongs to the branch that introduced typed ids.

## Target stack

| Position | Branch | Content |
| --- | --- | --- |
| 1/N | new, off `develop` | `72e83e29f` picked near-verbatim |
| 2/N | new, off 1/N | conformance ports: MetricKit (`837936732`), profiler (`6b23c3127`) |
| 3/N | `ac/sessions` | rebased over 2/N |
| 4/N | `ac/reports` | rebased over 3/N |
| 5/N | `ac/install` | rebased over 4/N |
| N/N | #867 remainder | iOS 27 CrashReportExtension host + corpse monitor, rebased onto 5/N |

## Steps

1. **1/N:** branch off `develop`, cherry-pick `72e83e29f`, full gate. Nothing
   pushed is touched.
2. **2/N:** branch off 1/N, pick the two conformance ports at their native
   base (develop-era MetricKit and profiler, the code they were written for),
   full gate.
3. **Rebase the stack bottom-up**, gating each branch:
   - `ac/sessions`, `ac/reports`: expected to be quiet; neither touches the
     layer's surface.
   - `ac/install`: the real adaptation point. Both sides created the
     `KSCrashMonitorPlugins` target, so `Package.swift`, the scheme, and the
     target's files collide here and resolve by adopting the layer's files;
     the branch's hand-rolled monitor tables (`SidecarMetadataMonitorPlugin`,
     the DiskMonitor plugin, MetricKit's trampolines, the install test's
     plugin) port to
     `CrashMonitor` conformances; `WrittenReport.id` becomes `Report.ID`; the
     stack's MetricKit changes (typed ids, `plugin()` instances, availability
     sweep) land on top of the ported conformance.
4. **N/N:** rebase what remains of #867 onto `ac/install`, adapting its
   install-path integration to the Swift surface (`InstallConfiguration`,
   namespace layout, typed ids) exactly once.

## Constraints

- Rebasing rewrites the pushed `#882` / `#898` branches and shifts their PR
  bases: every force-push and base change is separately approved, branch by
  branch. No push without approval.
- The extension remainder stays last on purpose: placing it below `ac/install`
  would force the install branch to rebase over extension install machinery
  and still leave the extension needing re-adaptation afterward.
- One PR per branch, based on its parent, with the synced Stack footer on all.
