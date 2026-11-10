#!/usr/bin/env bash
# Makes the native renderer's shader library (fh2_shaders.nfsp) from your
# Forza Horizon 2 disc on the handheld, the way upstream's
# tools/xenos/biblioteca.sh does on a PC:
#   1. takes media/shaders and the track archives' shader files from the disc
#      (scripts/extract-shader-data.py, a few hundred MB);
#   2. writes the executables' loaded images (the recompiler loads each one
#      with --xex_despejar_imagem: no need to start the game);
#   3. finds the shader containers and translates them to HLSL (XenosRecomp
#      as changed upstream, built here with the pinned clang);
#   4. compiles them to SPIR-V with DXC, strips and validates them (the
#      shader-tools release this repository builds for linux-arm64);
#   5. packs the library.
# The D3D library's own shaders (upstream's --fh2_nativo_volcar_sueltos
# step) are added when FH2_SHADER_DUMP points at such a dump.
#
#   scripts/build-shaders.sh FH2_RECOMPILED TOOLCHAIN ISO OUT_FILE
#   FH2_SHADERS_CHECK=1 scripts/build-shaders.sh FH2_RECOMPILED TOOLCHAIN - -   (tools only)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
fh2="$(cd "$1" && pwd)"
tc="$(cd "$2" && pwd)"
iso="$3"
outfile="$4"
. "$repo/scripts/common.sh"

work="$fh2/app/out/shaders_fh2"
bin="$fh2/app/out/xenos_bin"
data="$fh2/app/out/shader_data"
rec="$fh2/tools/xenos/recomp"
tp="$fh2/sdk/thirdparty"
mspack="$tp/libmspack/libmspack/mspack"
rexglue="$fh2/sdk/out/linux-arm64/rexglue"
dxc="$tc/shader-tools/bin/dxc"
opt="$tc/shader-tools/bin/spirv-opt"
val="$tc/shader-tools/bin/spirv-val"
for tool in "$dxc" "$opt" "$val" "$rexglue"; do
    [ -x "$tool" ] || { echo "error: $tool is missing" >&2; exit 1; }
done
cc=("$tc/llvm/bin/clang" --sysroot="$tc/sysroot" --ld-path="$tc/bin/ld.lld" $FS_ARCH_FLAGS)
cxx=("$tc/llvm/bin/clang++" --sysroot="$tc/sysroot" --ld-path="$tc/bin/ld.lld" -static-libstdc++ $FS_ARCH_FLAGS)

rm -rf "$work" "$data"
mkdir -p "$work/spirv" "$bin" "$data/images"

echo "Shader tools"
"${cc[@]}" -O1 -I"$mspack" "$fh2/tools/xenos/lzx_xmem.c" "$mspack/lzxd.c" "$mspack/system.c" -o "$bin/lzx_xmem"
"${cxx[@]}" -std=c++23 -O1 -I"$rec" -I"$rec/XenosRecomp" -I"$tp/fmt/include" -I"$tp/xxHash" \
    -include "$rec/pch_min.h" -DFMT_HEADER_ONLY -DXXH_INLINE_ALL -DNFSMW_RECOMP -DFH2_RECOMP \
    "$rec/nfsmw_hlsl.cpp" "$rec/XenosRecomp/shader_recompiler.cpp" -o "$bin/xenos_hlsl"
"${cxx[@]}" -std=c++23 -O1 -DFH2_RECOMP -I"$fh2/app/src/nativo" -I"$tp/xxHash" -I"$tp/fmt/include" \
    -DFMT_HEADER_ONLY "$fh2/tools/xenos/empaquetar.cpp" "$fh2/app/src/nativo/nfsmw_shader_library.cpp" \
    -o "$bin/empaquetar"

if [ "${FH2_SHADERS_CHECK:-0}" = 1 ]; then  # CI: the tools only, no disc
    printf 'float4 main(float4 p : SV_Position) : SV_Target { return p; }\n' > "$bin/check.hlsl"
    "$dxc" -spirv -T ps_6_6 -E main -HV 2021 -fspv-target-env=vulkan1.2 -Fo "$bin/check.spv" "$bin/check.hlsl"
    "$opt" --strip-debug "$bin/check.spv" -o "$bin/check.spv"
    "$val" --target-env vulkan1.2 "$bin/check.spv"
    "$rexglue" init achievements /nonexistent.xex "$bin" --xex_despejar_imagem="$bin/image" 2>&1 |
        tee "$bin/check.log" || true
    grep -q "XEX not found" "$bin/check.log"
    echo "Shader tools OK"
    exit 0
fi

echo "Shader files from the disc"
python3 -I "$repo/scripts/extract-shader-data.py" "$fh2" "$iso" "$data/game_root"

echo "Executable images"
for xex in "$fh2/assets/game_root"/*.xex; do
    "$rexglue" init achievements "$xex" "$data/achievements" \
        --xex_despejar_imagem="$data/images/$(basename "$xex" .xex)" >> "$data/images.log" 2>&1 || true
done
images=("$data/images"/*.*)
[ -e "${images[0]}" ] || { echo "error: no executable image was written (see $data/images.log)" >&2; exit 1; }
ls "$data/images"

echo "Shader containers"
python3 -I "$fh2/tools/xenos/extrair_fxobj_pistas.py" "$data/game_root" "$work/fxobj_pistas" "$bin/lzx_xmem"
python3 -I "$fh2/tools/xenos/extrair_contenedores.py" "$data/game_root" "$work/contenedores" \
    "$work/fxobj_pistas" "${images[@]}"
if [ -n "${FH2_SHADER_DUMP:-}" ] && [ -d "$FH2_SHADER_DUMP" ]; then
    python3 -I "$fh2/tools/xenos/d3d_internos.py" "$FH2_SHADER_DUMP" "$work/contenedores"
fi

echo "Translating to HLSL"
rc=0
"$bin/xenos_hlsl" "$work/contenedores" "$work/hlsl" "$rec/XenosRecomp/shader_common.h" \
    > "$work/traduccion.log" 2>&1 || rc=$?
tail -1 "$work/traduccion.log"
# 2 means some shaders were skipped, which is normal.
[ $rc -eq 0 ] || [ $rc -eq 2 ] || { echo "error: translation failed (see $work/traduccion.log)" >&2; exit 1; }

echo "Compiling to SPIR-V ($(ls "$work/hlsl" | wc -l) shaders)"
export DXC="$dxc" OPT="$opt" VAL="$val" SPV="$work/spirv"
compile_one() {
    local f="$1" b t e=()
    b="$(basename "$f" .hlsl)"
    if [[ $b == p_* ]]; then t=ps_6_6; else t=vs_6_6; e=(-fvk-invert-y); fi
    if "$DXC" -spirv -T "$t" -E main -HV 2021 -fspv-target-env=vulkan1.2 -fvk-use-dx-layout "${e[@]}" \
           -Fo "$SPV/$b.spv" "$f" > "$SPV/$b.log" 2>&1 &&
       "$OPT" --strip-debug --strip-nonsemantic "$SPV/$b.spv" -o "$SPV/$b.spv" >> "$SPV/$b.log" 2>&1 &&
       "$VAL" --target-env vulkan1.2 --scalar-block-layout "$SPV/$b.spv" >> "$SPV/$b.log" 2>&1; then
        rm -f "$SPV/$b.log"
    else
        rm -f "$SPV/$b.spv"
    fi
}
export -f compile_one
find "$work/hlsl" -name '*.hlsl' -print0 | xargs -0 -n 16 -P "$(nproc)" bash -c 'for f; do compile_one "$f"; done' _
ok="$(find "$work/spirv" -name '*.spv' | wc -l)"
failed="$(find "$work/spirv" -name '*.log' | wc -l)"
cat "$work/spirv"/*.log > "$work/dxc.log" 2>/dev/null || true
rm -f "$work/spirv"/*.log
echo "SPIR-V: $ok compiled, $failed failed"
[ "$ok" -gt 0 ] || { echo "error: no shader compiled (see $work/dxc.log)" >&2; exit 1; }

echo "Packing the library"
"$bin/empaquetar" "$work/contenedores" "$work/spirv" "$work/fh2_shaders.nfsp"
mkdir -p "$(dirname "$outfile")"
cp -f "$work/fh2_shaders.nfsp" "$outfile"
ls -l "$outfile"
# The disc's shader files are only needed while building.
rm -rf "$data/game_root" "$work/fxobj_pistas"
