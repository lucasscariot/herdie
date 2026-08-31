#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
CORE_ROOT="$PROJECT_ROOT/core"
GENERATED_ROOT="$PROJECT_ROOT/Generated/HerdieCore"
FRAMEWORK_ROOT="$PROJECT_ROOT/Frameworks"
XCFRAMEWORK="$FRAMEWORK_ROOT/HerdieCore.xcframework"
HEADER_STAGING="$PROJECT_ROOT/build/HerdieCoreHeaders"
SIMULATOR_STAGING="$PROJECT_ROOT/build/HerdieCoreSimulator"
export IPHONEOS_DEPLOYMENT_TARGET=18.0

mkdir -p "$GENERATED_ROOT" "$FRAMEWORK_ROOT" "$HEADER_STAGING/device" "$HEADER_STAGING/simulator" "$SIMULATOR_STAGING"

cargo build --manifest-path "$CORE_ROOT/Cargo.toml" -p herdie-core --features ssh --release --target aarch64-apple-ios
cargo build --manifest-path "$CORE_ROOT/Cargo.toml" -p herdie-core --features ssh --release --target aarch64-apple-ios-sim
cargo build --manifest-path "$CORE_ROOT/Cargo.toml" -p herdie-core --features ssh --release --target x86_64-apple-ios
cargo build --manifest-path "$CORE_ROOT/Cargo.toml" -p herdie-core --features ssh

lipo -create \
  "$CORE_ROOT/target/aarch64-apple-ios-sim/release/libherdie_core.a" \
  "$CORE_ROOT/target/x86_64-apple-ios/release/libherdie_core.a" \
  -output "$SIMULATOR_STAGING/libherdie_core.a"

(
  cd "$CORE_ROOT"
  target/debug/uniffi-bindgen generate \
    --library target/debug/libherdie_core.dylib \
    --language swift \
    --out-dir "$GENERATED_ROOT"
)

cp "$GENERATED_ROOT/herdie_coreFFI.h" "$HEADER_STAGING/device/"
cp "$GENERATED_ROOT/herdie_coreFFI.modulemap" "$HEADER_STAGING/device/module.modulemap"
cp "$GENERATED_ROOT/herdie_coreFFI.h" "$HEADER_STAGING/simulator/"
cp "$GENERATED_ROOT/herdie_coreFFI.modulemap" "$HEADER_STAGING/simulator/module.modulemap"

if [[ -e "$XCFRAMEWORK" ]]; then
  rm -rf "$XCFRAMEWORK"
fi

xcodebuild -create-xcframework \
  -library "$CORE_ROOT/target/aarch64-apple-ios/release/libherdie_core.a" \
  -headers "$HEADER_STAGING/device" \
  -library "$SIMULATOR_STAGING/libherdie_core.a" \
  -headers "$HEADER_STAGING/simulator" \
  -output "$XCFRAMEWORK"
