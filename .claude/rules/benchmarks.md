# Benchmarks

Benchmark sources live in `Tests/KSCrashBenchmarks` (Swift),
`Tests/KSCrashBenchmarksObjC` (ObjC), and `Tests/KSCrashBenchmarksCold`.
They run on real devices through BrowserStack; the PR gets a results comment
comparing against the base branch. Adding a benchmark takes FOUR registration
steps; missing any of them makes the benchmark silently absent somewhere:

1. **The test itself.** Subclass `KSBenchmarkTestCase` (Swift) or
   `KSBenchmarkTestCaseObjC` (ObjC); the base class reduces device iteration
   counts and skips under sanitizers. Method names MUST start with
   `testBenchmark`; the results parser keys on the suffix after that prefix,
   without the class name, so the suffix must be unique across ALL benchmark
   classes.
2. **Both build systems.** The same sources compile under SPM
   (`Package.swift` test targets) and Tuist
   (`Benchmarks/Project.swift`, targets `BenchmarkTests` AND
   `BenchmarkUITests`). A new module dependency goes in both places, and only
   shipping products are allowed (the Tuist build cannot see internal or
   test-support targets, nor `package`-visibility symbols).
3. **The device shards.** `.github/workflows/browserstack.yml` runs shards by
   explicit class name (`only-testing` values in the shard mapping). A new
   benchmark CLASS must be added to one shard's list or it never runs on
   device.
4. **The PR comment.** `.github/data/benchmark-tests.json` drives
   `.github/scripts/parse_benchmarks.py`: one entry per test (name, category,
   description, notes), plus the category definition with its rating
   thresholds. A test that runs but is not listed here does not appear in the
   PR comment.

Run benchmarks on device via the PR (the `benchmarks.yml` workflow), not
locally; local numbers are debug-build smoke checks only. In ObjC benchmark
files avoid nested dictionary literals (clang-format mangles them); build JSON
fixtures as strings instead.
