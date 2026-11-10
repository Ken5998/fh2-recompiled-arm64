# Shared by the build scripts (sourced).

# The SDK presets build for plain armv8-a; ARMv8.2 adds the LSE atomics and
# RCpc loads its locks and the GPU emulation lean on (every handheld this is
# for has them), tuned for the RP6's Cortex-A715 class cores.
FS_ARCH_FLAGS="-march=armv8.2-a+rcpc -mtune=cortex-a715"

build_jobs() {  # FS_JOBS, else one per CPU thread, at most one per 2 GB of memory
    if [ -n "${FS_JOBS:-}" ]; then echo "$FS_JOBS"; return; fi
    local mem_gb jobs
    mem_gb=$(( $(sed -n 's/^MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo) / 1048576 ))
    jobs=$(( mem_gb / 2 ))
    [ "$jobs" -le "$(nproc)" ] || jobs="$(nproc)"
    [ "$jobs" -ge 1 ] || jobs=1
    echo "$jobs"
}

check_aarch64() {  # ELF machine 183 (0xb7) is AArch64
    [ -f "$1" ] || { echo "error: $1 was not built" >&2; exit 1; }
    [ "$(od -An -tx1 -j18 -N2 "$1" | tr -d ' \n')" = b700 ] || { echo "error: $1 is not aarch64" >&2; exit 1; }
    echo "OK $1 (aarch64)"
}
