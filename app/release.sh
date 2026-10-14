#!/usr/bin/env bash
set -euo pipefail

# Build DeXBar.app and package it into a distributable .zip.
# Usage: ./release.sh [version]  -> produces build/DeXBar-macos.zip + a SHA-256
#   version defaults to `git describe --tags` (leading "v" stripped).
#
# To cut a GitHub release, tag and push — CI builds and attaches the .zip:
#   git tag v1.0.0 && git push origin v1.0.0

HERE="$(cd "$(dirname "$0")" && pwd)"

"$HERE/build.sh" "" "${1:-}"

cd "$HERE/build"
rm -f DeXBar-macos.zip
# ditto preserves macOS bundle metadata (and the code signature) better than zip.
ditto -c -k --keepParent DeXBar.app DeXBar-macos.zip

echo ""
echo "Packaged: $HERE/build/DeXBar-macos.zip"
shasum -a 256 DeXBar-macos.zip
