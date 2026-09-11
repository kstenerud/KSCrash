# Swift Monitor Layer

A Swifty way to write plugin monitors, so a monitor is a small protocol conformance instead of a
hand-rolled `KSCrashMonitorAPI` table with `@convention(c)` closures, `Unmanaged` context
recovery, strdup'd ids, and manual payload boxing.

**Scope boundary**: plugin monitors only, running in a healthy process (MetricKit, Profiler,
Corpse). Crash-time monitors (Signal, MachException) can never be Swift protocol dispatch; they
stay C. The layer sits on today's C `KSCrashMonitorAPI`; it does not depend on the parked C-side
monitor-base refactor.

**Access level**: the layer lives in its own target, `KSCrashMonitorPlugins` (product
`MonitorPlugins`), and its developer-facing types are Swift `public`. Conformers today: the
corpse monitor and MetricKit (`KSCrashMonitors`) and the profiler's internal `ProfileMonitor`
(`KSCrashProfiler`); third parties conform via the public surface below.

## The developer surface

```swift
final class CrashReportExtensionMonitor: CrashMonitor {
    typealias EventPayload = CorpseSnapshot
    static let id = "Corpse"

    let host: MonitorHost<CorpseSnapshot>
    init(host: MonitorHost<CorpseSnapshot>, configuration: Void) {   // nothing to configure
        self.host = host
    }

    func writeReportSection(payload: CorpseSnapshot, writer: ReportSectionWriter) {
        try? writer.encode("snapshot", payload.forEmbedding())
    }
}
```

Registration hands over the type plus whatever configuration that type declares; the monitor is
instantiated immediately, alongside the bridge, before any registration:

```swift
config.plugins = [CrashReportExtensionMonitor.plugin()]  // Configuration == Void
var metricKit = MetricKitMonitor.Configuration()       // typed configuration
metricKit.dumpsPayloadsToDocuments = true
config.plugins = [MetricKitMonitor.plugin(metricKit)]
```

`.plugin(...)` is sugar over `Monitor(Type.self, configuration)`; the raw form still works and is
what `.plugin` calls under the hood.

## The protocol

```swift
public protocol CrashMonitor: AnyObject {
    associatedtype EventPayload = Void    // typed per-event payload; Void when unused
    associatedtype Configuration = Void   // whatever the monitor needs at creation; Void when nothing
    static var id: String { get }
    static var flags: MonitorFlags { get }        // default .plugin
    static var stitchPriority: Int { get }        // default 0

    init(host: MonitorHost<EventPayload>, configuration: Configuration)

    func enabledDidChange(_ isEnabled: Bool)      // default no-op
    func monitorsDidEnable()                      // default no-op (notifyPostMonitorsEnabled)
    func systemDidEnable()                        // default no-op (notifyPostSystemEnable; never fires in extension mode)
    func writeReportSection(payload: EventPayload, writer: ReportSectionWriter)  // default no-op
    func stitchedReport(_ report: [String: Any], sidecarURL: URL?,
                        scope: SidecarScope) throws -> [String: Any]  // default returns report; throw = stitch error
                                                                      // sidecarURL is nil for .final (the post-sidecar
                                                                      // pass over every monitor, priority order)
}
```

`MonitorFlags`, `SidecarScope` and `EventRequirements` are the C types themselves, imported
under Swift names: `KSCrashMonitorFlag` is a `CF_OPTIONS` (so it lands as an option set),
`KSCrashSidecarScope` a `CF_CLOSED_ENUM` (an exhaustive Swift enum), and
`KSCrash_ExceptionHandlingRequirements` carries a `CF_SWIFT_NAME`, with `.fatalRemoteSubject`
and `.nonFatal` added as presets in an extension. There are no Swift-side copies of them; a
conformer that names one imports `KSCrashRecordingCore`.

Not exposed yet, deliberately: `addContextualInfoToEvent` (the wrapper no-ops it).

The monitor is created in `init`, before any registration; an event raised from inside
`init(host:configuration:)` is written without the monitor's report section (the bridge isn't
registered with the pipeline until installation, so `host.handle` throws `.refused` there).

**Threading**: callbacks arrive on whatever thread the pipeline uses. The bridge's own state
(callbacks, enabled flag) is lock-guarded (the enabled flag lock-free on the read side, see the
bridge section below), but a monitor owns its internal thread safety, exactly as hand-rolled
monitors did.

Design decisions, and why:

- **Constructor injection, no base class.** A monitor never exists without its host, so there is
  no lifecycle ceremony (`didInstall` + stashing) and no inheritance. The one stored `let host`
  is the visible dependency, and tests can inject a fake host with no global state.
- **Configuration is typed data, not a factory closure.** `Monitor(Type.self, configuration)`
  carries the monitor's own `Configuration` associatedtype value and delivers it at
  instantiation, so a monitor's dependencies are all visible in its `init`.
- **The bridge owns the enabled flag.** C-side setEnabled/isEnabled never reach the monitor as
  state, only as the `enabledDidChange` notification; `host.isEnabled` reads it back. This
  removes the locked-boolean boilerplate every hand-rolled monitor duplicated.
- **`EventPayload` formalizes the callbackContext pattern.** The Profiler's `BoxedTimeProfile`
  and the corpse monitor's `BoxedSnapshot` were the same idea hand-built twice: per-event data
  boxed through `KSCrash_MonitorContext.callbackContext` to `writeInReportSection`. The host
  boxes on `handle(payload:...)`, the bridge unboxes before `writeReportSection(payload:)`,
  typed end to end.
- **Eager instantiation, no replay window.** The monitor is built in `Monitor<M>.init`, before
  the bridge is registered anywhere, so there is no interval where an enable/notify can arrive
  with no instance to receive it (the earlier install-time instantiation needed an enabled-state
  replay for exactly that window; eager instantiation removes the window and the replay).

## MonitorHost

The typed face of `KSCrash_ExceptionHandlerCallbacks`. Its centerpiece collapses the
notify → fillMonitorContext → field setup → payload boxing → handleWithResult dance:

```swift
public struct MonitorHost<Payload> {
    public var isEnabled: Bool { get }
    public func handle(payload: Payload?, requirements: EventRequirements,
                subjectThread: thread_t = MACH_PORT_NULL, finalize: Bool = false,
                configure: (UnsafeMutablePointer<KSCrash_MonitorContext>) -> Void) throws -> WrittenReport
    public func handle(requirements: EventRequirements, ...) throws -> WrittenReport   // Payload == Void only
    public func reportSidecarURL(reportID: Int64) -> URL?
    public func reportSidecarURL(name: String, extension: String) -> URL?
    public func runSidecarURL() -> URL?

    public struct WrittenReport {
        public let id: Int64?  // the store's ID; nil for caller-supplied reportPath writes
        public let url: URL?   // the report file's location, when the pipeline reported one
    }
}
```

A nil `payload` writes the report WITHOUT the monitor's report section (the corpse monitor uses
this for snapshot-less captures); the payload-less overload is constrained to `Payload == Void`
monitors, whose `writeReportSection` still runs. `handle` refuses (throws `.refused`) when the
bridge isn't installed yet, the pipeline is shutting down, or it returns the shared
exit-immediately bail-out context, matching the hand-rolled monitors' contract. `configure`
receives the raw monitor context on purpose: the low-level per-event fields (mach codes,
provided images, machine context, processName) are genuinely low-level, and wrapping them would
just rename them. `EventRequirements` has two presets, `.fatalRemoteSubject` and `.nonFatal`
(more land with the monitors that need them).

## ReportSectionWriter

Already existed in `KSCrashProfiler/Private` as `UnsafeReportWriter`; it is the wrapper that
handles the C-struct quirks (re-passing the writer pointer to its own function pointers,
`withCString` bridging, nil-name array-element convention, and the naming collision with the C
`ReportWriter` typedef). It is promoted into the monitor layer (renamed to avoid the "unsafe"
prefix reading as a warning about report-section writing specifically, when the whole layer is
equally unsafe under the hood) and gains `encode(_ key:, _ value: some Encodable)` (JSONEncoder
→ `addJSONElement`). The Profiler uses this shared writer; its private copy was deleted with
the port.

## The bridge (the only unsafe code, written once)

`MonitorCore` (public, the implementation base) is an NSObject conforming to
`KSCrashMonitorPlugin` (so `config.plugins` and the C registration path are unchanged); it holds
the api table, the lock-guarded callbacks, the enabled flag (an `AtomicFlag` over the C11 cell
in `KSAtomicFlag.h`, so crash-time readers never take the bridge lock), and type-erased hook
closures. `Monitor<M>: MonitorCore` (public, final) fills those hooks with closures that
may capture `M` where `@convention(c)` trampolines cannot; the trampolines themselves are literal
non-capturing closures that recover the (non-generic) base from the api context pointer.

The monitor is built in `Monitor<M>.init`, right after `super.init()` (which is also where
`api.context` escapes `self` via `Unmanaged.passUnretained`; the C side cannot call back before
registration, which cannot precede this initializer returning, so the escape is sound). `monitor`
is a non-optional computed property over a `private var _monitor: M!` backing, not `let monitor:
M`: building it needs `self` as the host's bridge, and Swift's definite-initialization rules
forbid using `self` before `super.init()` returns, so it can't be a `let` assigned in the same
phase as delegating up. The backing is set before `init` returns, so every external access sees
a non-nil monitor for the object's whole observable lifetime. `isInstalled` (`callbacks != nil`,
lock-guarded) is the separate question of whether the bridge has connected to the pipeline yet;
`host.handle` throws `.refused` and the sidecar accessors return nil before then.

Ids are unique per process, enforced in C by `kscmr_addMonitor`, which refuses an id already
registered (and asserts in debug) for every plugin language, not just Swift. Ids route report
sections, sidecar directories and stitching, so a duplicate would misroute one monitor's data
into another's.

## Port status

| Monitor | Status |
|---|---|
| Corpse (CrashReportExtension) | Born on this layer |
| MetricKit | Ported: `MetricKitMonitor: CrashMonitor`, registered via `MetricKitMonitor.plugin(.init())` (it has a real `Configuration`) |
| Profiler | Ported: internal `ProfileMonitor: CrashMonitor` (id "profile", the report wire format), self-registering `shared` bridge |

**Module placement**: the layer lives in its own target, `KSCrashMonitorPlugins` (product
`MonitorPlugins`), depended on by `KSCrashMonitors` and `KSCrashProfiler`.
