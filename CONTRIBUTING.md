# Contributing to KSCrash

Thank you for your interest in contributing to KSCrash! This document provides guidelines and information for developers working on the project.

## Development Setup

### Quick Start

Run the development setup script to enable strict warnings and prepare your environment:

```bash
./setup-dev.sh
```

This script will:
- Enable development mode with strict warnings as errors
- Clean and resolve package dependencies
- Prepare your environment for development

### Development Mode

KSCrash uses a file-based system to control development warnings:

- **Enable development mode**: `touch .kscrash_development`
- **Disable development mode**: `rm .kscrash_development`

When development mode is enabled:
- All warnings become errors (`-Werror`)
- Comprehensive warning flags are active
- Code quality is strictly enforced

After toggling development mode, you must clear caches:
```bash
swift package purge-cache
```

### Xcode Integration

If working with Package.swift in Xcode:
1. Clean project: **Cmd+K**
2. Reset package caches: **File → Packages → Reset Package Caches**
