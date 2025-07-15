#!/bin/bash
# KSCrash Development Setup Script
# This script sets up the development environment with strict warnings enabled

set -e  # Exit on error

echo "🚀 Setting up KSCrash development environment..."

# Create development flag file
echo "📝 Enabling development mode (strict warnings as errors)..."
touch .kscrash_development

# Clean and prepare Swift package
echo "🧹 Cleaning package cache..."
swift package clean
swift package purge-cache

# Resolve dependencies
echo "📦 Resolving dependencies..."
swift package resolve

echo "✅ Development environment ready!"
echo ""
echo "Development mode features:"
echo "  • All warnings treated as errors (-Werror)"
echo "  • Comprehensive warning flags enabled"
echo "  • Strict code quality enforcement"
echo ""
echo "To disable development mode:"
echo "  rm .kscrash_development && swift package purge-cache"
echo ""
echo "📱 If using Xcode with Package.swift:"
echo "  • Clean project with Cmd+K"
echo "  • File → Packages → Reset Package Caches"