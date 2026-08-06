#!/bin/sh
# Xcode Cloud runs this automatically after cloning the repo, before building.
#
# Xcode Cloud's macOS images ship Xcode and CocoaPods but NOT Flutter, so the
# SDK has to be installed on every run.
#
# The version is pinned deliberately: 3.44.8 is the toolchain that produced the
# working iOS archive (build 1.0.0(1)), including the Swift Package Manager and
# CocoaPods integration committed in ios/. Bump it as a conscious decision, not
# by drifting with `stable`.
set -e

FLUTTER_VERSION=3.44.8

echo "=== Installing Flutter $FLUTTER_VERSION ==="
git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$HOME/flutter"
git config --global --add safe.directory "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

flutter --version
flutter precache --ios

echo "=== Resolving Dart packages ==="
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

echo "=== CocoaPods ==="
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
pod install

echo "=== ci_post_clone.sh complete ==="
