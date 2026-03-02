---
paths:
  - "Sources/KSCrashRecording/KSCrashThreadcrumb.m"
  - "Sources/KSCrashRecording/include/KSCrashThreadcrumb.h"
  - "Sources/Monitors/MetricKit/**"
---

## Threadcrumb

Threadcrumb is a technique for encoding short messages into a thread's call stack so they can be recovered from crash reports via symbolication. Each allowed character (A-Z, a-z, 0-9, _) maps to a unique function symbol (e.g., `__kscrash__A__`, `__kscrash__B__`). When `log:` is called, these functions are chained recursively to build a stack that mirrors the message. The thread then parks, preserving the shaped stack until the next message or deallocation.

### How It Works

1. Call `[threadcrumb log:@"ABC123"]`
2. The implementation chains function calls: `__kscrash__A__` → `__kscrash__B__` → `__kscrash__C__` → ...
3. The thread parks with this stack intact
4. If a crash occurs, the stack is captured in the crash report
5. During symbolication (locally or on a backend), the frames resolve to their character symbols
6. The original message can be reconstructed by parsing the symbol names

### Resource Considerations

Threadcrumb should be used sparingly or not at all if not needed. Each instance consumes a thread — even though it's parked and idle, it's still a limited system resource. The best approach is to encode a short identifier (like a run ID) that points to more data stored elsewhere, rather than trying to encode large amounts of information directly.

There's a tradeoff between sending a full report as-is without extra on-device work versus having enough embedded data to use the payload effectively. A single identifier that can be used to look up additional context strikes the right balance.

### Use Cases

- **Run ID encoding**: We use threadcrumb to encode the KSCrash run ID into a parked thread for MetricKit correlation
- **Breadcrumbs**: Encode the current application state or user action
- **Feature flags**: Encode active feature flags or A/B test variants
- **Any data that needs to survive a crash**: Since the data lives in the stack, it's captured by any crash reporter

### Backend Symbolication

When a crash report is symbolicated server-side, the threadcrumb frames resolve to their character symbols. The backend can parse these symbol names to reconstruct the encoded message without any special client-side coordination — just symbolicate the stack and read the function names.

### Alternatives Considered

**MetricKit signposts**: We initially tried using `mxSignpost` to log the run ID, but signposts are flaky and often dropped for various reasons, making them unreliable for correlation.

**Payload timestamps**: MetricKit payload timestamps are imprecise — they often represent a time range or the delivery date rather than the actual crash time, making it impossible to reliably match to a specific run.

The threadcrumb approach works because all crash reporters capture call stacks with instruction addresses. By shaping a thread's stack to encode data, we get that data back through standard symbolication.

### Key Files

- `KSCrashThreadcrumb.h/.m`: The threadcrumb implementation
- `MetricKitRunIdHandler.swift`: Uses threadcrumb to encode/decode run IDs for MetricKit correlation
