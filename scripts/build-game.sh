#!/usr/bin/env bash
# Builds FH2 Recompiled for linux-arm64 (the fh2 program, its two recompiled
# guest modules and the SDK libraries next to it), with the SDK as part of the
# same build as upstream does: natively on aarch64, or cross-compiled on
# x86-64.
#
#   scripts/build-game.sh FH2 TOOLCHAIN [BUILD]
#
# FH2        the tree prepare.sh made, with FH2/app/generated holding what
#            codegen.sh made from the game (or placeholder-codegen.py's
#            stand-in, to check the build without the game)
# TOOLCHAIN  fetch-toolchain.sh's folder
# BUILD      build folder (default FH2/app/out/linux-arm64)
#
# The SDK puts its libraries (librexruntime.so, librexgpu-xenos.so) in
# FH2/sdk/out/linux-arm64, the program and the guest modules go to BUILD.
#
# Parallel jobs: FS_JOBS, else one per logical CPU but at most one per 2 GB of
# memory (the recompiled files are huge).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
fh2="$(cd "$1" && pwd)"
export FS_ARM64_TOOLCHAIN="$(cd "$2" && pwd)"
build="${3:-$fh2/app/out/linux-arm64}"
llvm="$FS_ARM64_TOOLCHAIN/llvm/bin"
export PATH="$FS_ARM64_TOOLCHAIN/bin:$PATH"
. "$repo/scripts/common.sh"
jobs="$(build_jobs)"
echo "Building with $jobs parallel jobs ($(nproc) CPU threads)"

[ -f "$fh2/app/generated/rexglue.cmake" ] || { echo "error: no generated code in $fh2/app/generated" >&2; exit 1; }
SOURCE_DATE_EPOCH="$(git -C "$fh2" log -1 --format=%ct 2>/dev/null || echo 0)"
export SOURCE_DATE_EPOCH
cmake -S "$fh2/app" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_TOOLCHAIN_FILE=$repo/cmake/toolchains/linux-arm64.cmake" \
    "-DCMAKE_C_COMPILER=$llvm/clang" "-DCMAKE_CXX_COMPILER=$llvm/clang++" \
    "-DCMAKE_C_FLAGS=$FS_ARCH_FLAGS" "-DCMAKE_CXX_FLAGS=$FS_ARCH_FLAGS" \
    "-DREXSDK_DIR=$fh2/sdk" -DREXGLUE_EXTERNAL_CODEGEN=ON -DREXGLUE_RECOMP_DEBUG_INFO=none \
    -DREXGLUE_USE_VULKAN=ON -DREXGLUE_ENABLE_TRACY=OFF -DSDL_HIDAPI_LIBUSB=OFF
cmake --build "$build" --parallel "$jobs"

for f in "$build/fh2" "$build/libfh2_xmediafacade_default.so" "$build/libfh2_speechfacade_default.so" \
         "$fh2/sdk/out/linux-arm64/librexruntime.so" "$fh2/sdk/out/linux-arm64/librexgpu-xenos.so"; do
    check_aarch64 "$f"
done
