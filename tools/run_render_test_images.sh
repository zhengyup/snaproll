#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.render-tool"
BINARY_PATH="$BUILD_DIR/render-test-images"

mkdir -p "$BUILD_DIR"

swiftc \
  -o "$BINARY_PATH" \
  "$ROOT_DIR/tools/render_test_images.swift" \
  "$ROOT_DIR/ios/snaproll/snaproll/Models/FilmStock.swift" \
  "$ROOT_DIR/ios/snaproll/snaproll/Utilities/AppConfig.swift" \
  "$ROOT_DIR/ios/snaproll/snaproll/Services/PhotoRenderService.swift"

"$BINARY_PATH"
