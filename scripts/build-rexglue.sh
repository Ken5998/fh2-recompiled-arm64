#!/usr/bin/env bash
# Builds only the rexglue recompiler from FH2 Recompiled's SDK, for
# linux-arm64, to run codegen on the handheld.
#
#   scripts/build-rexglue.sh FH2 TOOLCHAIN
#
# Prints nothing but the build; the program is FH2/sdk/out/linux-arm64/rexglue
# (the SDK's own output folder).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
fh2="$(cd "$1" && pwd)"
export FS_ARM64_TOOLCHAIN="$(cd "$2" && pwd)"
llvm="$FS_ARM64_TOOLCHAIN/llvm/bin"
export PATH="$FS_ARM64_TOOLCHAIN/bin:$PATH"
. "$repo/scripts/common.sh"

cmake -S "$fh2/sdk" -B "$fh2/sdk/out/build/rexglue" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_TOOLCHAIN_FILE=$repo/cmake/toolchains/linux-arm64.cmake" \
    "-DCMAKE_C_COMPILER=$llvm/clang" "-DCMAKE_CXX_COMPILER=$llvm/clang++" \
    "-DCMAKE_C_FLAGS=$FS_ARCH_FLAGS" "-DCMAKE_CXX_FLAGS=$FS_ARCH_FLAGS" \
    -DREXGLUE_USE_VULKAN=ON -DREXGLUE_ENABLE_TRACY=OFF -DSDL_HIDAPI_LIBUSB=OFF
cmake --build "$fh2/sdk/out/build/rexglue" --target rexglue --parallel "$(build_jobs)"
check_aarch64 "$fh2/sdk/out/linux-arm64/rexglue"
