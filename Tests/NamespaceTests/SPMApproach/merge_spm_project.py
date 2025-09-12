#!/usr/bin/env python3

# Copyright (c) 2025 Karl Stenerud. All rights reserved.
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

"""
Script to merge multiple SPM targets into a single target.
"""

# NOTE: Requires Python 3.9 or later

import os
import sys
import shutil
import argparse
import xml.etree.ElementTree as ET
from typing import Dict, List, Any
from pathlib import Path


def get_all_targets(source_project_path: Path) -> List[str]:
    """Get all target directories from the source project's Sources directory."""
    sources_dir = Path(source_project_path) / "Sources"
    if not sources_dir.exists():
        raise ValueError(f"Sources directory not found in {source_project_path}")

    targets = []
    for item in sources_dir.iterdir():
        if item.is_dir():
            targets.append(item.name)

    return targets

def xcprivacy_element_to_python(element: ET.Element) -> Any:
    """Parse an xcprivacy XML element into a Python data structure."""
    if element.tag == 'true':
        return True
    elif element.tag == 'false':
        return False
    elif element.tag == 'string':
        return element.text or ''
    elif element.tag == 'array':
        items = []
        for child in element:
            items.append(xcprivacy_element_to_python(child))
        return items
    elif element.tag == 'dict':
        result = {}
        key = None
        for child in element:
            if child.tag == 'key':
                key = child.text
            else:
                if key is not None:
                    result[key] = xcprivacy_element_to_python(child)
                    key = None
        return result
    else:
        raise ValueError(f"Unknown element type: {element.tag}")


def python_to_xcprivacy_element(data: Any) -> ET.Element:
    """Create an xcprivacy XML element from a Python data structure."""
    if isinstance(data, bool):
        return ET.Element('true' if data else 'false')
    elif isinstance(data, str):
        elem = ET.Element('string')
        elem.text = data
        return elem
    elif isinstance(data, list):
        elem = ET.Element('array')
        for item in data:
            elem.append(python_to_xcprivacy_element(item))
        return elem
    elif isinstance(data, dict):
        elem = ET.Element('dict')
        for key, value in data.items():
            key_elem = ET.Element('key')
            key_elem.text = key
            elem.append(key_elem)
            elem.append(python_to_xcprivacy_element(value))
        return elem
    else:
        raise ValueError(f"Unknown data type: {type(data)}")


def get_xcprivacy_dict_identifier(d: Dict[str, Any]) -> str:
    """Get the identifier for an xcprivacy dictionary (the only string value)."""
    for _, value in d.items():
        if isinstance(value, str):
            return value
    raise ValueError(f"Dictionary contains no identifier")


def merge_xcprivacy_booleans(a: bool, b: bool) -> bool:
    """Merge two xcprivacy booleans - true always overrides false."""
    return a or b


def merge_xcprivacy_arrays(a: List[Any], b: List[Any]) -> List[Any]:
    """Merge two arrays as sets."""
    is_array_of_dicts = any(isinstance(item, dict) for item in a + b)

    if not is_array_of_dicts:
        return list(set(a + b))

    dicts_by_identifier = {}

    for item in a:
        if not isinstance(item, dict):
            raise ValueError(f"Array of dictionaries contains non-dictionary item: {item}")
        identifier = get_xcprivacy_dict_identifier(item)
        dicts_by_identifier[identifier] = item

    for item in b:
        if not isinstance(item, dict):
            raise ValueError(f"Array of dictionaries contains non-dictionary item: {item}")
        identifier = get_xcprivacy_dict_identifier(item)
        if identifier in dicts_by_identifier:
            dicts_by_identifier[identifier] = merge_xcprivacy_dicts(dicts_by_identifier[identifier], item)
        else:
            dicts_by_identifier[identifier] = item

    return list(dicts_by_identifier.values())

def merge_xcprivacy_dicts(a: Dict[str, Any], b: Dict[str, Any]) -> Dict[str, Any]:
    """Merge two dictionaries according to the xcprivacy rules."""
    result = a.copy()

    for key, value in b.items():
        if key not in result:
            result[key] = value
        else:
            existing_value = result[key]
            if type(value) != type(existing_value):
                raise ValueError(f"Mismatched types {existing_value} and {value} for key {key}")
            if isinstance(existing_value, bool):
                result[key] = merge_xcprivacy_booleans(existing_value, value)
            elif isinstance(existing_value, list):
                result[key] = merge_xcprivacy_arrays(existing_value, value)
            elif isinstance(existing_value, dict):
                result[key] = merge_xcprivacy_dicts(existing_value, value)
            elif isinstance(existing_value, str):
                if existing_value != value:
                    raise ValueError(f"Mismatched string values '{existing_value}' and '{value}' for key '{key}'")
            else:
                raise ValueError(f"Unknown type {type(existing_value)} for key {key}")

    return result

def deserialize_xcprivacy_file(filepath: Path) -> Dict[str, Any]:
    """Load and parse an xcprivacy file."""
    tree = ET.parse(filepath)
    root = tree.getroot()

    # We're interested in <plist><dict>...</dict></plist>
    plist_elem = root
    if plist_elem.tag != 'plist':
        raise ValueError(f"Expected plist root element, got {plist_elem.tag}")
    dict_elem = plist_elem.find('dict')
    if dict_elem is None:
        raise ValueError("No dict element found in plist")

    return xcprivacy_element_to_python(dict_elem)

def serialize_xcprivacy_xml(data: Dict[str, Any]) -> str:
    """Create an xcprivacy XML string from parsed data."""
    root = ET.Element('plist')
    root.set('version', '1.0')
    dict_elem = python_to_xcprivacy_element(data)
    root.append(dict_elem)

    ET.indent(root, space='    ', level=0)
    xml_serialized = ET.tostring(root, encoding='unicode', xml_declaration=False)

    header = '<?xml version="1.0" encoding="UTF-8"?>\n'
    header = header + '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'

    return header + xml_serialized

def merge_xcprivacy_files(source_file: Path, dest_file: Path):
    """Merge PrivacyInfo.xcprivacy XML files by merging the dict contents."""
    # Create destination directory if it doesn't exist
    dest_file.parent.mkdir(parents=True, exist_ok=True)

    if not dest_file.exists():
        # If destination doesn't exist, just copy the source
        shutil.copy2(source_file, dest_file)
        return

    src_data = deserialize_xcprivacy_file(source_file)
    dst_data = deserialize_xcprivacy_file(dest_file)
    merged_data = merge_xcprivacy_dicts(dst_data, src_data)
    xml_str = serialize_xcprivacy_xml(merged_data)
    with open(dest_file, "w") as f:
        f.write(xml_str)

def serialize_modulemap(name: str, headers: List[str]) -> str:
    """Create a modulemap string from a list of headers."""
    modulemap = [
        f"module {name} {{\n",
        "  export *\n",
        "}\n"
    ]
    for header in headers:
        if len(header) > 0:
            modulemap.insert(1, f"  header \"{header}\"\n")
    return "".join(modulemap)

def rmpath(path: Path):
    """Remove a file or directory."""
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()

def create_symlink(source_path: Path, dest_path: Path):
    """Create a symlink, handling existing files/links."""
    rmpath(dest_path)

    # Create parent directory if it doesn't exist
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    # Create relative symlink
    relative_source = os.path.relpath(source_path, dest_path.parent)
    dest_path.symlink_to(relative_source)

def copy_path(source_path: Path, dest_path: Path):
    """Copy a file or directory to a new location, handling existing files/links."""
    rmpath(dest_path)

    # Create parent directory if it doesn't exist
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    if source_path.is_dir():
        shutil.copytree(source_path, dest_path)
    else:
        shutil.copy2(source_path, dest_path)

def copy_or_symlink(source_path: Path, dest_path: Path, use_symlinks: bool):
    if use_symlinks:
        create_symlink(source_path, dest_path)
    else:
        copy_path(source_path, dest_path)

def merge_target(source_project_path: Path, target_name: str, new_project_path: Path, new_target_name: str, use_symlinks: bool):
    """Merge a single target into the new project structure."""
    source_target_dir = Path(source_project_path) / "Sources" / target_name
    dest_target_dir = Path(new_project_path) / "Sources" / new_target_name

    if target_name == "":
        return
    if not source_target_dir.exists():
        print(f"Warning: Source target directory {source_target_dir} does not exist, skipping")
        return

    print(f"Merging target: {target_name}")

    for item in source_target_dir.iterdir():
        if item.name == "include":
            include_dest_dir = dest_target_dir / "include"
            include_dest_dir.mkdir(parents=True, exist_ok=True)

            for include_item in item.iterdir():
                dest_include_path = include_dest_dir / include_item.name
                copy_or_symlink(include_item, dest_include_path, use_symlinks)

        elif item.name == "Resources":
            resources_dest_dir = dest_target_dir / "Resources"

            for resource_item in item.iterdir():
                if resource_item.name == "PrivacyInfo.xcprivacy":
                    dest_privacy_file = resources_dest_dir / "PrivacyInfo.xcprivacy"
                    merge_xcprivacy_files(resource_item, dest_privacy_file)
                else:
                    dest_resource_path = resources_dest_dir / resource_item.name
                    copy_or_symlink(resource_item, dest_resource_path, use_symlinks)
        else:
            dest_item_path = dest_target_dir / item.name
            copy_or_symlink(item, dest_item_path, use_symlinks)


def main():
    """Main function."""
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--clear', action='store_true', help='clear destination target before merging')
    parser.add_argument('-s', '--symlink', action='store_true', help='create symlinks instead of copying files')
    parser.add_argument('-t', '--targets', help='comma separated list of targets to merge')
    parser.add_argument('-m', '--module_headers', help='comma separated list of headers (without paths) to include in the modulemap')
    parser.add_argument('source_project_path', nargs='?', help='source project path')
    parser.add_argument('new_project_path', nargs='?', help='new project path')
    parser.add_argument('new_target_name', nargs='?', help='new target name')

    args = parser.parse_args()

    source_project_path = Path(args.source_project_path).resolve()
    if not source_project_path.exists():
        print(f"Error: Source project path {source_project_path} does not exist")
        sys.exit(1)

    new_target_name = args.new_target_name
    new_project_path = Path(args.new_project_path).resolve()
    sources_dir = new_project_path / "Sources"
    target_dir = sources_dir / new_target_name

    new_project_path.mkdir(parents=True, exist_ok=True)
    sources_dir.mkdir(parents=True, exist_ok=True)

    if args.clear and target_dir.exists():
        shutil.rmtree(target_dir)

    target_dir.mkdir(parents=True, exist_ok=True)
    (target_dir / "include").mkdir(exist_ok=True)
    (target_dir / "Resources").mkdir(exist_ok=True)

    if args.targets:
        targets_to_merge = [t.strip() for t in args.targets.split(',')]
    else:
        targets_to_merge = get_all_targets(source_project_path)
    targets_to_merge.sort()

    module_headers = args.module_headers.split(',') if args.module_headers else []
    module_headers.sort()

    print(f"Merging targets: {', '.join(targets_to_merge)}")
    print(f"Module headers: {', '.join(module_headers)}")
    print(f"Source project: {source_project_path}")
    print(f"New project: {new_project_path}")
    print(f"New target name: {new_target_name}")
    print()

    for target in targets_to_merge:
        merge_target(source_project_path, target, new_project_path, new_target_name, args.symlink)

    if len(module_headers) > 0:
        modulemap = serialize_modulemap(new_target_name, module_headers)
        with open(target_dir / "include/module.modulemap", "w") as f:
            f.write(modulemap)

    with open(target_dir / "GENERATED_CODE_DO_NOT_MODIFY.md", "w") as f:
        f.write("""# GENERATED CODE - DO NOT MODIFY

Everything in this directory tree is generated by merge_spm_project.py. Do not modify anything!

This directory should be added to your `.gitignore` file.
""")

    print(f"\nMerge complete! New project target created at: {target_dir}")


if __name__ == "__main__":
    main()
