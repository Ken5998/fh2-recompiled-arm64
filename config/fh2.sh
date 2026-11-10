#!/usr/bin/env bash
# Starts Forza Horizon 2 (FH2 Recompiled, linux-arm64) on the emulated Xenos
# GPU, with the disc image read in place. Installed beside the game as fh2.sh
# by scripts/build.sh; Steam starts this.
#
# Settings you may want to change are in fh2.toml beside it (resolution,
# frame limit, world detail...). The arguments below are what the game needs
# on the handheld's Vulkan driver, the same ones FH2 Recompiled's Android
# launcher always passes; arguments win over fh2.toml.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
mkdir -p Logs user

# The disc image build.sh linked here (your own copy, never copied).
disc="$here/../disc.iso"
[ -e "$disc" ] || { echo "error: $disc is missing: run the launcher's Build again with your disc image" >&2; exit 1; }

export LD_LIBRARY_PATH="$here${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$here/fh2" \
    --game_data_root="$disc" --user_data_root="$here/user" --log_file="$here/Logs/fh2.log" \
    --gpu_plugin=xenos --render_target_path_vulkan=fbo \
    --gpu_allow_invalid_fetch_constants=true \
    --mnk_mode=true --mnk_preset=race --mnk_mouse=true \
    "$@"
