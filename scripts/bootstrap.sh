#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(tr -d '\r\n' < .xcodegen-version)"
binary="$PWD/.tools/XcodeGen/.build/release/xcodegen"
if [ ! -x "$binary" ]; then
  mkdir -p .tools
  git clone --depth 1 --branch "$version" https://github.com/yonaskolb/XcodeGen.git .tools/XcodeGen
  swift build --package-path .tools/XcodeGen --configuration release --product xcodegen
fi
"$binary" generate --spec project.yml

