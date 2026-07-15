# Repository Agent Notes

## Session detail log decisions

These decisions are settled. Read them before reviewing or modifying session-detail logging and do not reopen them without new, concrete evidence.

- Session events must remain durable synchronously on every recording call.
- The event history is intentionally unbounded. Do not cap, sample, or drop session or user events.
- Startup persistence must remain synchronous and extremely fast. It must not fully parse the session log, materialize the complete log as Foundation objects, or allocate a second log-sized output buffer.
- Preserve the append-only on-disk grammar and newline commit boundary. Do not replace the format or introduce a migration merely to simplify splicing.
- Report/session correlation remains sidecar-based. Do not capture `session_id` into crash context at report time or replace the established stitching behavior with that approach.
- A source-break concern for this work was reviewed and dismissed. Do not raise it again as a review finding.

The accepted hardening approach is:

- Validate committed mmap-backed bytes once with the specialized allocation-free grammar scanner.
- Treat invalid committed data as an empty session list while retaining newline-based recovery of an incomplete tail.
- Decode materialized session objects with strict JSON types and signed 64-bit bounds.
- Persist lazy run-summary JSON synchronously with mapped bytes and vectored writes.
- Perform optional session object materialization outside the sessions lock.

Current verification expectations are the focused session/run-summary/lifecycle tests, formatting checks, namespace generation checks, diff checks, and the existing startup benchmarks. The large synthetic benchmark contains 500 sessions and 4,000 user changes; exact validation plus persistence has measured below 0.7 ms.

## Agent process boundaries

- Do not create, amend, squash, or otherwise rewrite commits unless the user explicitly requests it.
- When the user requests delegated review, let the reviewers finish and consolidate their results instead of stopping them without instruction.
- Keep durable notes concise: record constraints, rejected alternatives, accepted decisions, and verification evidence so a context reset does not restart settled debates.
