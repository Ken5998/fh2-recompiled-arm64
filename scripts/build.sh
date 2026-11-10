#!/usr/bin/env bash
# Builds Forza Horizon 2 (FH2 Recompiled) for linux-arm64 from your own
# Forza Horizon 2 (Xbox 360, USA, title 4D530AA4) disc image, start to
# finish: the toolchain, FH2 Recompiled with this repository's patches, the
# recompiler, the recompiled code, the game, and a ready folder to play from,
# added to Steam. Made for the handheld itself (ArmadaOS on the Retroid
# Pocket 6, or any aarch64 Linux). FS_ADD_TO_STEAM=0 leaves Steam alone.
#
#   scripts/build.sh ISO [DIR]
#
# ISO  your Forza Horizon 2 (Xbox 360) disc image, or - to keep the one an
#      earlier build used (to update)
# DIR  where everything goes (default ~/.local/share/FH2Recompiled-arm64);
#      about 25 GB free is needed while building
#
# The game reads the disc image in place: DIR/disc.iso links to it, so keep
# the file where it is (or build again with its new place). Run it again
# after updating this repository: finished steps are skipped when nothing
# they depend on changed, and the game build recompiles only the files a
# change touches. Nothing made here may be published (it is built from your
# copy of the game).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 1 ] && { [ "$1" = - ] || [ -f "$1" ]; } || { echo "usage: $0 ISO|- [DIR]" >&2; exit 2; }
case "$(uname -m)" in
    aarch64|arm64) ;;
    *) echo "error: build on the handheld (aarch64 Linux)" >&2; exit 1 ;;
esac
dir="${2:-$HOME/.local/share/FH2Recompiled-arm64}"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
if [ "$1" != - ]; then
    ln -sfn "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" "$dir/disc.iso"
fi
[ -e "$dir/disc.iso" ] || { echo "error: no disc image yet: give your Forza Horizon 2 ISO instead of -" >&2; exit 1; }
iso="$(readlink -f "$dir/disc.iso")"
tc="$dir/toolchain"
fh2="$dir/fh2-recompiled"
game="$dir/game"
stamps="$dir/.stamps"
mkdir -p "$stamps"

step() { printf '\n==> [%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
key() { cat "$@" | sha256sum | cut -d' ' -f1; }  # key FILE...: a hash of their contents
done_with() { [ -f "$stamps/$1" ] && [ "$(cat "$stamps/$1")" = "$2" ]; }
mark() { echo "$2" > "$stamps/$1"; }

step "Toolchain"
"$repo/scripts/fetch-toolchain.sh" "$tc"
export PATH="$tc/bin:$PATH"

prepare_key="$(key "$repo/upstream.json" "$repo/scripts/prepare.sh" "$repo"/patches/*.patch)"
if done_with prepare "$prepare_key" && [ -d "$fh2/.git" ]; then
    echo "FH2 Recompiled already prepared - skipping."
else
    step "FH2 Recompiled and the ReXGlue SDK sources"
    "$repo/scripts/prepare.sh" "$dir"
    mark prepare "$prepare_key"
fi

# Codegen reads the executable and the two facade modules from the disc; the
# rest of the game stays in the image.
game_root="$fh2/assets/game_root"
iso_key="$iso $(stat -c '%s %Y' "$iso")"
if done_with extract "$iso_key" && [ -f "$game_root/default.xex" ]; then
    echo "Executables already taken from the disc - skipping."
else
    step "Taking the executables from $iso"
    rm -rf "$game_root"
    python3 -I "$fh2/tools/fase1_extraer.py" "$iso" -o "$game_root" --solo-xex | tee "$dir/disc-info.txt"
    for f in default.xex XMediaFacade_default.xex SpeechFacade_default.xex; do
        [ -f "$game_root/$f" ] || { echo "error: $f is not on the disc: is this Forza Horizon 2 for Xbox 360?" >&2; exit 1; }
    done
    grep -q '4D530AA4' "$dir/disc-info.txt" ||
        echo "Warning: this is not the USA disc (title 4D530AA4) FH2 Recompiled is made for; trying anyway."
    mark extract "$iso_key"
fi

rexglue_key="$prepare_key $(key "$repo/toolchain.json" "$repo/scripts/build-rexglue.sh" "$repo/scripts/common.sh")"
if done_with rexglue "$rexglue_key" && [ -x "$fh2/sdk/out/linux-arm64/rexglue" ]; then
    echo "Recompiler already built - skipping."
else
    step "Building the recompiler"
    "$repo/scripts/build-rexglue.sh" "$fh2" "$tc"
    mark rexglue "$rexglue_key"
fi

codegen_key="$rexglue_key $(key "$game_root"/*.xex "$fh2"/app/*.toml "$fh2/tools/codegen.sh")"
if done_with codegen "$codegen_key" && [ -f "$fh2/app/generated/default/sources.cmake" ]; then
    echo "Recompiled code already generated - skipping."
else
    step "Recompiling the game (PowerPC to C++)"
    REXGLUE="$fh2/sdk/out/linux-arm64/rexglue" PYTHON=python3 "$fh2/tools/codegen.sh" app
    mark codegen "$codegen_key"
fi

step "Building Forza Horizon 2 (an hour or more on a handheld)"
"$repo/scripts/build-game.sh" "$fh2" "$tc"

# The native renderer's shader library, made from the disc (upstream's
# tools/xenos/biblioteca.sh): about twice the frame rate of the emulated GPU.
# Without it the game runs on the emulated GPU, so a failure here only warns.
shaders_key="$prepare_key $iso_key $(key "$repo/toolchain.json" "$repo/scripts/build-shaders.sh" "$repo/scripts/extract-shader-data.py")"
if [ ! -x "$tc/shader-tools/bin/dxc" ]; then
    echo "No shader compiler in this toolchain yet: the game uses the emulated GPU."
elif done_with shaders "$shaders_key" && [ -f "$dir/fh2_shaders.nfsp" ]; then
    echo "Shader library already made - skipping."
else
    step "Making the shader library for the native renderer"
    if "$repo/scripts/build-shaders.sh" "$fh2" "$tc" "$iso" "$dir/fh2_shaders.nfsp"; then
        mark shaders "$shaders_key"
    else
        echo "Warning: the shader library could not be made; the game uses the emulated GPU."
    fi
fi

step "Copying the game to $game"
build="$fh2/app/out/linux-arm64"
mkdir -p "$game"
cp -f "$build/fh2" "$build"/libfh2_*.so \
    "$fh2/sdk/out/linux-arm64/librexruntime.so" "$fh2/sdk/out/linux-arm64/librexgpu-xenos.so" "$game/"
[ -f "$dir/fh2_shaders.nfsp" ] && cp -f "$dir/fh2_shaders.nfsp" "$game/"
install -m 755 "$repo/config/fh2.sh" "$game/fh2.sh"
# Your settings stay; the RP6 defaults go in only the first time.
[ -f "$game/fh2.toml" ] || cp "$repo/config/fh2.toml" "$game/fh2.toml"

steam=no
if [ "${FS_ADD_TO_STEAM:-1}" = 1 ]; then
    step "Adding Forza Horizon 2 to Steam"
    if python3 -I "$repo/scripts/add-to-steam.py" "$game"; then
        steam=yes
    else
        echo "Warning: Forza Horizon 2 was not added to Steam; scripts/add-to-steam.py tries again."
    fi
fi

echo
echo "Done at $(date +%H:%M:%S)! Forza Horizon 2 is in $game."
if [ "$steam" = yes ]; then
    echo "Play it from Steam (\"Forza Horizon 2\" in the library): the handheld's controls reach it only from there."
else
    echo "Play it from Steam (scripts/add-to-steam.py adds it) so the controls work,"
    echo "or run $game/fh2.sh from a terminal."
fi
