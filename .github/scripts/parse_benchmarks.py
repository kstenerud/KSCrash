#!/usr/bin/env python3
#
# parse_benchmarks.py
#
# Parses xcresult benchmark files and generates a markdown report.
#
# Usage:
#   python3 parse_benchmarks.py --pr-results <path> [--base-results <path>] --config <path>
#

import argparse
import json
import math
import os
import statistics
import subprocess
import sys
from datetime import datetime


def get_system_info():
    """Gather system information for the report header."""
    try:
        chip = subprocess.check_output(
            ["sysctl", "-n", "machdep.cpu.brand_string"], stderr=subprocess.DEVNULL
        ).decode().strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        try:
            chip = subprocess.check_output(["uname", "-m"]).decode().strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            chip = "Unknown"

    try:
        mem_bytes = int(
            subprocess.check_output(
                ["sysctl", "-n", "hw.memsize"], stderr=subprocess.DEVNULL
            ).decode().strip()
        )
        mem_gb = mem_bytes / (1024**3)
    except (subprocess.CalledProcessError, FileNotFoundError, ValueError):
        mem_gb = 0

    try:
        macos_ver = subprocess.check_output(
            ["sw_vers", "-productVersion"], stderr=subprocess.DEVNULL
        ).decode().strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        macos_ver = "Unknown"

    try:
        xcode_ver = subprocess.check_output(
            ["xcodebuild", "-version"], stderr=subprocess.DEVNULL
        ).decode().split("\n")[0]
    except (subprocess.CalledProcessError, FileNotFoundError):
        xcode_ver = "Unknown"

    return f"{chip}, {mem_gb:.0f}GB RAM, macOS {macos_ver}, {xcode_ver}"


def get_device_info(xcresult_path):
    """Get detailed device info from xcresult using test-results tests command."""
    try:
        output = subprocess.check_output([
            "xcrun", "xcresulttool", "get", "test-results", "tests",
            "--path", xcresult_path
        ]).decode()
        data = json.loads(output)

        devices = data.get("devices", [])
        if devices:
            device = devices[0]
            device_name = device.get("deviceName", "Unknown")
            model_name = device.get("modelName", "")
            platform = device.get("platform", "")
            os_version = device.get("osVersion", "")

            # Determine if it's a simulator based on platform
            is_simulator = "simulator" in platform.lower()

            return {
                "name": device_name,
                "model": model_name,
                "platform": platform,
                "os_version": os_version,
                "is_simulator": is_simulator
            }
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        pass

    return None


def parse_xcresult(xcresult_path):
    """Parse xcresult bundle and return dict of benchmark results with stats, plus device info."""
    if not os.path.exists(xcresult_path):
        return None, None

    results = {}
    device_info = get_device_info(xcresult_path)

    try:
        output = subprocess.check_output([
            "xcrun", "xcresulttool", "get", "test-results", "metrics",
            "--path", xcresult_path
        ]).decode()
        data = json.loads(output)

        for test in data:
            test_id = test.get("testIdentifier", "")
            if "/testBenchmark" not in test_id:
                continue

            test_name = test_id.split("/testBenchmark")[1].rstrip("()")
            test_runs = test.get("testRuns", [])
            if not test_runs:
                continue

            # Fallback to basic device name from metrics if we don't have full info
            if not device_info:
                device = test_runs[0].get("device", {})
                device_name = device.get("deviceName")
                if device_name:
                    device_info = {
                        "name": device_name,
                        "model": "",
                        "platform": "",
                        "os_version": "",
                        "is_simulator": None  # Unknown
                    }

            for metric in test_runs[0].get("metrics", []):
                metric_id = metric.get("identifier", "")
                # Accept WallClockTime, ClockMonotonicTime, or Time metrics
                if metric_id in (
                    "com.apple.XCTPerformanceMetric_WallClockTime",
                    "com.apple.XCTPerformanceMetric_ClockMonotonicTime",
                    "com.apple.dt.XCTMetric_Time",
                    "com.apple.dt.XCTMetric_Clock.time.monotonic",
                ):
                    measurements = metric.get("measurements", [])
                    if measurements:
                        results[test_name] = {
                            "avg": statistics.mean(measurements),
                            "stddev": statistics.stdev(measurements) if len(measurements) > 1 else 0.0,
                            "n": len(measurements)
                        }

    except subprocess.CalledProcessError as e:
        print(f"Error running xcresulttool: {e}", file=sys.stderr)
        return None, None
    except json.JSONDecodeError as e:
        print(f"Error parsing xcresult JSON: {e}", file=sys.stderr)
        return None, None

    return (results if results else None), device_info


def welch_t_test(mean1, std1, n1, mean2, std2, n2):
    """Perform Welch's t-test and return p-value approximation."""
    if std1 == 0 and std2 == 0:
        return 1.0 if mean1 == mean2 else 0.0

    se1 = (std1 ** 2) / n1
    se2 = (std2 ** 2) / n2
    se_diff = math.sqrt(se1 + se2)

    if se_diff == 0:
        return 1.0 if mean1 == mean2 else 0.0

    t_stat = abs(mean1 - mean2) / se_diff

    if se1 + se2 == 0:
        df = n1 + n2 - 2
    else:
        df = ((se1 + se2) ** 2) / ((se1 ** 2) / (n1 - 1) + (se2 ** 2) / (n2 - 1))

    if t_stat == 0:
        return 1.0

    if df > 30:
        p = 2 * (1 - 0.5 * (1 + math.erf(t_stat / math.sqrt(2))))
    else:
        p = 2 * (1 - 0.5 * (1 + math.erf(t_stat / math.sqrt(2)))) * (1 + 0.5 / df)

    return max(0, min(1, p))


def format_time(seconds):
    """Format time in human-readable units."""
    us = seconds * 1_000_000
    if us < 1:
        return "<1 μs"
    elif us < 1000:
        return f"{us:.1f} μs"
    else:
        return f"{us/1000:.2f} ms"


def format_stddev(avg, stddev):
    """Format standard deviation as percentage."""
    if avg == 0:
        return "N/A"
    return f"±{(stddev / avg) * 100:.1f}%"


def get_status(seconds, thresholds):
    """Get status emoji based on thresholds."""
    if seconds < thresholds["excellent"]:
        return "✅ Excellent"
    elif seconds < thresholds["good"]:
        return "✅ Good"
    elif seconds < thresholds["ok"]:
        return "⚠️ OK"
    else:
        return "❌ Review"


def get_change(base_stats, pr_stats):
    """Calculate change between base and PR stats."""
    base_avg, pr_avg = base_stats["avg"], pr_stats["avg"]
    if base_avg == 0:
        return "N/A", 1.0

    pct = ((pr_avg - base_avg) / base_avg) * 100
    p_value = welch_t_test(
        base_avg, base_stats["stddev"], base_stats["n"],
        pr_avg, pr_stats["stddev"], pr_stats["n"]
    )

    if p_value < 0.05:
        if pct > 15:
            return f"⚠️ +{pct:.1f}%", p_value
        elif pct < -15:
            return f"✅ {pct:.1f}%", p_value
    return f"{pct:+.1f}%", p_value


def format_device_info(device_info):
    """Format device info for display in the report."""
    if not device_info:
        return ""

    parts = []

    # Device name/model
    name = device_info.get("name", "")
    model = device_info.get("model", "")
    if model and model != name:
        parts.append(f"{model} ({name})")
    elif name:
        parts.append(name)

    # OS version
    os_version = device_info.get("os_version", "")
    if os_version:
        parts.append(f"iOS {os_version}")

    # Device type (Simulator vs Real Device)
    is_simulator = device_info.get("is_simulator")
    if is_simulator is True:
        parts.append("Simulator")
    elif is_simulator is False:
        parts.append("Device")
    # If None, we don't know, so we don't add anything

    return " | ".join(parts) if parts else ""


def generate_report(pr_results, base_results, config, device_info):
    """Generate the markdown benchmark report."""
    tests = config["tests"]
    system_info = get_system_info()

    output = ["# 🔍 KSCrash Performance Benchmarks\n"]
    output.append("*Crash capture performance metrics - lower times are better*\n")
    device_str = format_device_info(device_info)
    output.append(f"**Host:** {system_info}\n")
    if device_str:
        output.append(f"**Target:** {device_str}\n")
    output.append("<details>")
    output.append("<summary><b>📖 How to interpret results</b></summary>\n")
    output.append("| Std Dev | Interpretation |")
    output.append("|---------|----------------|")
    output.append("| < 5% | Stable, reliable measurement |")
    output.append("| 5-15% | Some variability, typical for most benchmarks |")
    output.append("| > 15% | High variability, interpret with caution |\n")
    output.append("**p-value** (in comparison table): Probability the difference is due to chance. Values < 0.05 indicate statistically significant changes.\n")
    output.append("</details>\n")

    # Comparison section (only when we have base results to compare against)
    if base_results:
        output.append("<details open>")
        output.append("<summary><h2>📊 Changes from Base Branch</h2></summary>\n")
        output.append("*Only showing statistically significant changes (p < 0.05, threshold > 15%)*\n")
        output.append("| Operation | Base | Base σ | PR | PR σ | Change | p-value |")
        output.append("|-----------|------|--------|-----|------|--------|---------|")

        changes = []
        for test in tests:
            name = test["name"]
            if name in pr_results and name in base_results:
                base_stats, pr_stats = base_results[name], pr_results[name]
                change, p_value = get_change(base_stats, pr_stats)
                pct = ((pr_stats["avg"] - base_stats["avg"]) / base_stats["avg"]) * 100 if base_stats["avg"] > 0 else 0
                p_str = f"{p_value:.4f}" if p_value >= 0.0001 else "<0.0001"
                row = f"| {test['description']} | {format_time(base_stats['avg'])} | {format_stddev(base_stats['avg'], base_stats['stddev'])} | {format_time(pr_stats['avg'])} | {format_stddev(pr_stats['avg'], pr_stats['stddev'])} | {change} | {p_str} |"
                changes.append(((p_value, -abs(pct)), row, p_value))

        changes.sort(key=lambda x: x[0])
        shown = 0
        for _, row, p_value in changes:
            if shown >= 15:
                break
            if p_value < 0.05:
                output.append(row)
                shown += 1

        if shown == 0:
            output.append("| *No statistically significant changes detected* | | | | | | |")
        output.append("\n</details>\n")

    # Generate sections by category
    for cat in config["categories"]:
        cat_id = cat["id"]
        cat_tests = [t for t in tests if t["category"] == cat_id]
        if not cat_tests:
            continue

        # Check if any tests in this category have results
        has_results = any(t["name"] in pr_results for t in cat_tests) if pr_results else False
        if not has_results:
            continue

        output.append("<details open>")
        output.append(f"<summary><h3>{cat['name']}</h3></summary>\n")

        # Build header based on category settings
        if cat.get("perCall"):
            output.append("| Operation | Time | Std Dev | Per-Call | Status |")
            output.append("|-----------|------|---------|----------|--------|")
        elif cat.get("hideStdDev"):
            output.append("| Operation | Time | Status | Notes |")
            output.append("|-----------|------|--------|-------|")
        else:
            output.append("| Operation | Time | Std Dev | Status | Notes |")
            output.append("|-----------|------|---------|--------|-------|")

        for test in cat_tests:
            name = test["name"]
            if not pr_results or name not in pr_results:
                continue

            t = pr_results[name]["avg"]
            stddev = pr_results[name]["stddev"]
            thresholds = cat["thresholds"]

            if cat.get("perCall"):
                iterations = test.get("iterations", 1)
                per_call = t / iterations
                status = get_status(per_call, thresholds)
                output.append(f"| {test['description']} | {format_time(t)} | {format_stddev(t, stddev)} | {format_time(per_call)} | {status} |")
            elif cat.get("hideStdDev"):
                status = get_status(t, thresholds)
                notes = test.get("notes", "")
                output.append(f"| {test['description']} | {format_time(t)} | {status} | {notes} |")
            else:
                status = get_status(t, thresholds)
                notes = test.get("notes", "")
                output.append(f"| {test['description']} | {format_time(t)} | {format_stddev(t, stddev)} | {status} | {notes} |")

        output.append("\n</details>")

    # Summary
    total_tests = len(pr_results) if pr_results else 0
    output.append(f"\n---\n**{total_tests} benchmarks** | _Generated {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}_")

    return "\n".join(output)


def main():
    parser = argparse.ArgumentParser(description="Parse benchmark xcresult files and generate report")
    parser.add_argument("--pr-results", required=True, help="Path to PR xcresult bundle")
    parser.add_argument("--base-results", help="Path to base branch xcresult bundle")
    parser.add_argument("--config", required=True, help="Path to benchmark-tests.json config")
    parser.add_argument("--output", default="benchmark_results.md", help="Output markdown file")
    args = parser.parse_args()

    # Load config
    with open(args.config) as f:
        config = json.load(f)

    # Parse results
    pr_results, device_info = parse_xcresult(args.pr_results)
    base_results = None
    if args.base_results:
        base_results, _ = parse_xcresult(args.base_results)

    # Generate report
    report = generate_report(pr_results, base_results, config, device_info)

    # Write output
    with open(args.output, "w") as f:
        f.write(report)

    print(report)


if __name__ == "__main__":
    main()
