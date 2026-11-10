#!/usr/bin/env bash
# Starts Forza Horizon 2 (FH2 Recompiled, linux-arm64) with the disc image
# read in place. Installed beside the game as fh2.sh by scripts/build.sh;
# Steam starts this.
#
# With the shader library build.sh makes from the disc (fh2_shaders.nfsp
# beside this) the game draws with the native renderer, as FH2 Recompiled's
# Android launcher does by default; without it, or with FH2_RENDERER=emulated
# in Steam's launch options, on the emulated Xenos GPU (slower, the faithful
# one).
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

renderer=()
if [ -f "$here/fh2_shaders.nfsp" ] && [ "${FH2_RENDERER:-native}" != emulated ]; then
    # The Android launcher's native renderer defaults.
    # Shaders the library lacks (the D3D library's own, loose in the
    # executable) are written to ../shader-dump as you play; the next
    # build.sh adds them to the library.
    mkdir -p "$here/../shader-dump"
    renderer=(--nfsmw_renderizador=nativo
        --fh2_nativo_vertices_sin_espera=true --fh2_nativo_destinos_exactos=true
        --fh2_nativo_volcar_sueltos="$here/../shader-dump")
fi

export LD_LIBRARY_PATH="$here${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$here/fh2" "${renderer[@]}" \
    --game_data_root="$disc" --user_data_root="$here/user" --log_file="$here/Logs/fh2.log" \
    --gpu_plugin=xenos --render_target_path_vulkan=fbo \
    --gpu_allow_invalid_fetch_constants=true \
    --mnk_mode=true --mnk_preset=race --mnk_mouse=true \
    "$@"
