#!/usr/bin/env python3
#
# perfcomp.py
#
# Compares benchmark metrics between PR and main branch runs.
# Uses Welch's t-test for statistical significance.
# Posts results as a PR comment via GitHub API.
#
# Environment variables:
#   PERF_PR: JSON metrics from PR run
#   PERF_MAIN: JSON metrics from main branch run
#   THRESHOLD_PCT: Regression threshold percentage (default: 5)
#   ALPHA: Statistical significance level (default: 0.05)
#   TITLE: Comment title
#   GITHUB_TOKEN: GitHub token for posting comments
#   REPO: Repository in owner/repo format
#   PR_NUMBER: Pull request number
#

import json
import os
import sys
from datetime import datetime

try:
    from scipy import stats
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False

try:
    from github import Github
    HAS_GITHUB = True
except ImportError:
    HAS_GITHUB = False


def parse_metrics(metrics_json):
    """Parse metrics JSON into a dictionary keyed by test name."""
    if not metrics_json:
        return {}

    try:
        data = json.loads(metrics_json)
    except json.JSONDecodeError:
        print(f"Warning: Could not parse metrics JSON", file=sys.stderr)
        return {}

    results = {}

    # Handle xcresulttool format
    if isinstance(data, list):
        for test in data:
            test_id = test.get("testIdentifier", "")
            if "/testBenchmark" not in test_id:
                continue

            test_name = test_id.split("/testBenchmark")[1].rstrip("()")
            test_runs = test.get("testRuns", [])
            if not test_runs:
                continue

            for metric in test_runs[0].get("metrics", []):
                metric_id = metric.get("identifier", "")
                if metric_id in (
                    "com.apple.XCTPerformanceMetric_WallClockTime",
                    "com.apple.XCTPerformanceMetric_ClockMonotonicTime",
                    "com.apple.dt.XCTMetric_Time",
                    "com.apple.dt.XCTMetric_Clock.time.monotonic",
                ):
                    measurements = metric.get("measurements", [])
                    if measurements:
                        results[test_name] = {
                            "measurements": measurements,
                            "unit": metric.get("unitOfMeasurement", "s")
                        }

    # Handle BrowserStack API format
    elif isinstance(data, dict) and "tests" in data:
        for test in data["tests"]:
            name = test.get("name", "")
            duration = test.get("duration")
            if name and duration is not None:
                # Convert to measurement format
                results[name] = {
                    "measurements": [duration],
                    "unit": "s"
                }

    return results


def welch_t_test(measurements1, measurements2):
    """Perform Welch's t-test and return p-value."""
    if not HAS_SCIPY:
        # Fallback: simple comparison without statistical test
        return 0.5

    if len(measurements1) < 2 or len(measurements2) < 2:
        return 1.0

    try:
        _, p_value = stats.ttest_ind(measurements1, measurements2, equal_var=False)
        return p_value if not (p_value != p_value) else 1.0  # Check for NaN
    except Exception:
        return 1.0


def calculate_stats(measurements):
    """Calculate mean and standard deviation."""
    if not measurements:
        return 0, 0
    mean = sum(measurements) / len(measurements)
    if len(measurements) < 2:
        return mean, 0
    variance = sum((x - mean) ** 2 for x in measurements) / (len(measurements) - 1)
    return mean, variance ** 0.5


def format_time(seconds):
    """Format time in human-readable units."""
    us = seconds * 1_000_000
    if us < 1:
        return "<1 us"
    elif us < 1000:
        return f"{us:.1f} us"
    else:
        return f"{us/1000:.2f} ms"


def format_change(base_mean, pr_mean):
    """Format the percentage change."""
    if base_mean == 0:
        return "N/A"
    pct = ((pr_mean - base_mean) / base_mean) * 100
    return f"{pct:+.1f}%"


def generate_report(pr_metrics, main_metrics, threshold_pct, alpha, title):
    """Generate markdown comparison report."""
    lines = [f"# {title}\n"]
    lines.append(f"*Generated {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}*\n")

    if not pr_metrics:
        lines.append("No benchmark metrics available from PR run.\n")
        return "\n".join(lines)

    if not main_metrics:
        lines.append("No baseline metrics available for comparison.\n")
        lines.append("\n## PR Results\n")
        lines.append("| Test | Time | Std Dev |")
        lines.append("|------|------|---------|")
        for name, data in sorted(pr_metrics.items()):
            mean, stddev = calculate_stats(data["measurements"])
            stddev_pct = (stddev / mean * 100) if mean > 0 else 0
            lines.append(f"| {name} | {format_time(mean)} | {stddev_pct:.1f}% |")
        return "\n".join(lines)

    # Compare results
    regressions = []
    improvements = []
    no_change = []

    for name in sorted(set(pr_metrics.keys()) | set(main_metrics.keys())):
        if name not in pr_metrics or name not in main_metrics:
            continue

        pr_data = pr_metrics[name]
        main_data = main_metrics[name]

        pr_mean, pr_std = calculate_stats(pr_data["measurements"])
        main_mean, main_std = calculate_stats(main_data["measurements"])

        if main_mean == 0:
            continue

        pct_change = ((pr_mean - main_mean) / main_mean) * 100
        p_value = welch_t_test(main_data["measurements"], pr_data["measurements"])

        result = {
            "name": name,
            "main_mean": main_mean,
            "main_std": main_std,
            "pr_mean": pr_mean,
            "pr_std": pr_std,
            "pct_change": pct_change,
            "p_value": p_value,
            "significant": p_value < alpha
        }

        if result["significant"]:
            if pct_change > threshold_pct:
                regressions.append(result)
            elif pct_change < -threshold_pct:
                improvements.append(result)
            else:
                no_change.append(result)
        else:
            no_change.append(result)

    # Sort by magnitude of change
    regressions.sort(key=lambda x: -x["pct_change"])
    improvements.sort(key=lambda x: x["pct_change"])

    # Summary
    if regressions:
        lines.append(f"**Warning:** {len(regressions)} performance regression(s) detected\n")
    elif improvements:
        lines.append(f"**Good news:** {len(improvements)} performance improvement(s) detected\n")
    else:
        lines.append("No significant performance changes detected.\n")

    # Regressions table
    if regressions:
        lines.append("\n## Regressions\n")
        lines.append("| Test | Main | PR | Change | p-value |")
        lines.append("|------|------|-----|--------|---------|")
        for r in regressions:
            p_str = f"{r['p_value']:.4f}" if r['p_value'] >= 0.0001 else "<0.0001"
            lines.append(
                f"| {r['name']} | {format_time(r['main_mean'])} | "
                f"{format_time(r['pr_mean'])} | {r['pct_change']:+.1f}% | {p_str} |"
            )

    # Improvements table
    if improvements:
        lines.append("\n## Improvements\n")
        lines.append("| Test | Main | PR | Change | p-value |")
        lines.append("|------|------|-----|--------|---------|")
        for r in improvements:
            p_str = f"{r['p_value']:.4f}" if r['p_value'] >= 0.0001 else "<0.0001"
            lines.append(
                f"| {r['name']} | {format_time(r['main_mean'])} | "
                f"{format_time(r['pr_mean'])} | {r['pct_change']:+.1f}% | {p_str} |"
            )

    # Full results (collapsed)
    lines.append("\n<details>")
    lines.append("<summary><b>All Results</b></summary>\n")
    lines.append("| Test | Main | PR | Change | p-value | Significant |")
    lines.append("|------|------|-----|--------|---------|-------------|")

    all_results = regressions + improvements + no_change
    all_results.sort(key=lambda x: x["name"])

    for r in all_results:
        p_str = f"{r['p_value']:.4f}" if r['p_value'] >= 0.0001 else "<0.0001"
        sig = "Yes" if r['significant'] else "No"
        lines.append(
            f"| {r['name']} | {format_time(r['main_mean'])} | "
            f"{format_time(r['pr_mean'])} | {r['pct_change']:+.1f}% | {p_str} | {sig} |"
        )

    lines.append("\n</details>\n")

    # Footer
    lines.append(f"\n---\n*Threshold: {threshold_pct}% | Alpha: {alpha} | "
                 f"Tests compared: {len(all_results)}*")

    return "\n".join(lines)


def post_comment(report, repo, pr_number, token):
    """Post or update PR comment."""
    if not HAS_GITHUB:
        print("Warning: pygithub not available, cannot post comment", file=sys.stderr)
        print(report)
        return

    if not token:
        print("Warning: No GitHub token, cannot post comment", file=sys.stderr)
        print(report)
        return

    try:
        g = Github(token)
        repository = g.get_repo(repo)
        pr = repository.get_pull(int(pr_number))

        # Look for existing comment to update
        comment_marker = "<!-- perfcomp-results -->"
        report_with_marker = f"{comment_marker}\n{report}"

        for comment in pr.get_issue_comments():
            if comment_marker in comment.body:
                comment.edit(report_with_marker)
                print(f"Updated existing comment: {comment.html_url}")
                return

        # Create new comment
        comment = pr.create_issue_comment(report_with_marker)
        print(f"Created new comment: {comment.html_url}")

    except Exception as e:
        print(f"Error posting comment: {e}", file=sys.stderr)
        print(report)


def main():
    # Get environment variables
    perf_pr = os.environ.get("PERF_PR", "")
    perf_main = os.environ.get("PERF_MAIN", "")
    threshold_pct = float(os.environ.get("THRESHOLD_PCT", "5"))
    alpha = float(os.environ.get("ALPHA", "0.05"))
    title = os.environ.get("TITLE", "Performance Comparison")
    token = os.environ.get("GITHUB_TOKEN", "")
    repo = os.environ.get("REPO", "")
    pr_number = os.environ.get("PR_NUMBER", "")

    # Parse metrics
    pr_metrics = parse_metrics(perf_pr)
    main_metrics = parse_metrics(perf_main)

    # Generate report
    report = generate_report(pr_metrics, main_metrics, threshold_pct, alpha, title)

    # Post comment or print
    if repo and pr_number:
        post_comment(report, repo, pr_number, token)
    else:
        print(report)


if __name__ == "__main__":
    main()
