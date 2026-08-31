#!/bin/zsh
set -euo pipefail

if [[ -z ${ANDROID_NDK_HOME:-} ]]; then
  print -u2 "ANDROID_NDK_HOME must point to an installed Android NDK."
  exit 1
fi

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
CORE_ROOT="$PROJECT_ROOT/core"
GENERATED_ROOT="$PROJECT_ROOT/Generated/HerdieCoreKotlin"
PREBUILT_ROOT="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt"
prebuilt_directories=("$PREBUILT_ROOT"/*(N/))

if (( ${#prebuilt_directories} == 0 )); then
  print -u2 "No LLVM toolchain was found under $PREBUILT_ROOT."
  exit 1
fi

ANDROID_CLANG="${prebuilt_directories[1]}/bin/aarch64-linux-android26-clang"
if [[ ! -x "$ANDROID_CLANG" ]]; then
  print -u2 "Android ARM64 API 26 compiler was not found at $ANDROID_CLANG."
  exit 1
fi

export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$ANDROID_CLANG"
export CC_aarch64_linux_android="$ANDROID_CLANG"
export AR_aarch64_linux_android="${prebuilt_directories[1]}/bin/llvm-ar"

mkdir -p "$GENERATED_ROOT"
cargo build --manifest-path "$CORE_ROOT/Cargo.toml" -p herdie-core --features ssh --release --target aarch64-linux-android
cargo build --manifest-path "$CORE_ROOT/Cargo.toml" -p herdie-core --bin uniffi-bindgen

(
  cd "$CORE_ROOT"
  target/debug/uniffi-bindgen generate \
    --library target/aarch64-linux-android/release/libherdie_core.so \
    --language kotlin \
    --out-dir "$GENERATED_ROOT"
)
