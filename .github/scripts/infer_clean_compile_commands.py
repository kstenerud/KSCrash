#!/usr/bin/env python3
#
#  infer_clean_compile_commands.py
#
#  Created by Alexander Cohen on 2025-01-29.
#
#  Copyright (c) 2012 Karl Stenerud. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall remain in place
# in this source code.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

"""
Post-processes an xcodebuild-generated compile_commands.json for use with Infer.

Performs:
1. Fixes escaped equals signs (\\= -> =)
2. Removes unsupported compiler flags
3. Removes @response-file references
4. Removes -include references pointing to DerivedData
5. Filters to C/C++/Objective-C files only (.c, .cpp, .m, .mm)
"""

import json
import sys
import os


# Flags that take no argument and should be removed entirely
REMOVE_FLAGS_NO_ARG = {
    "-fmodules-validate-once-per-build-session",
}

# Flags that take the next token as an argument (remove flag + argument)
REMOVE_FLAGS_WITH_ARG = {
    "-ivfsstatcache",
    "-index-store-path",
    "-index-unit-output-path",
    "-fbuild-session-file",
}

# Flags where the argument is joined (e.g., --serialize-diagnostics /path)
REMOVE_FLAGS_WITH_ARG_ALSO = {
    "--serialize-diagnostics",
}

# Extensions to keep
ALLOWED_EXTENSIONS = {".c", ".cpp", ".m", ".mm"}


def clean_command(command: str) -> str:
    """Clean a single compile command string."""
    # Fix escaped equals signs
    command = command.replace("\\=", "=")

    # Split into tokens for flag-level processing
    tokens = command.split()
    cleaned = []
    skip_next = False

    for i, token in enumerate(tokens):
        if skip_next:
            skip_next = False
            continue

        # Remove @response-file references
        if token.startswith("@") and token.endswith(".resp"):
            continue

        # Remove flags with no argument
        if token in REMOVE_FLAGS_NO_ARG:
            continue

        # Remove flags that consume the next argument
        if token in REMOVE_FLAGS_WITH_ARG or token in REMOVE_FLAGS_WITH_ARG_ALSO:
            skip_next = True
            continue

        # Remove -include pointing to DerivedData
        if token == "-include" and i + 1 < len(tokens):
            next_token = tokens[i + 1]
            if "DerivedData" in next_token:
                skip_next = True
                continue

        cleaned.append(token)

    return " ".join(cleaned)


def get_source_file(entry: dict) -> str:
    """Extract the source file path from a compilation database entry."""
    return entry.get("file") or ""


def is_c_or_cpp(filepath: str) -> bool:
    """Check if the file has a C, C++, or Objective-C extension."""
    _, ext = os.path.splitext(filepath)
    return ext.lower() in ALLOWED_EXTENSIONS


def clean_compile_commands(input_path: str, output_path: str) -> None:
    """Clean and filter a compilation database."""
    with open(input_path, "r") as f:
        entries = json.load(f)

    cleaned = []
    for entry in entries:
        source_file = get_source_file(entry)

        # Filter to C/C++ files only
        if not is_c_or_cpp(source_file):
            continue

        new_entry = dict(entry)
        if "command" in new_entry:
            new_entry["command"] = clean_command(new_entry["command"])
        if "arguments" in new_entry:
            # Re-join arguments, clean as a single command, then re-split
            joined = " ".join(new_entry["arguments"])
            cleaned_cmd = clean_command(joined)
            new_entry["arguments"] = cleaned_cmd.split()

        cleaned.append(new_entry)

    with open(output_path, "w") as f:
        json.dump(cleaned, f, indent=2)

    print(f"Cleaned {len(entries)} -> {len(cleaned)} entries (C/C++/ObjC only)")
    print(f"Output written to {output_path}")


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.json> <output.json>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    if not os.path.exists(input_path):
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    clean_compile_commands(input_path, output_path)


if __name__ == "__main__":
    main()
