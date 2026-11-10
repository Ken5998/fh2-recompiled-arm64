#!/usr/bin/env bash
# Checks out FH2 Recompiled at the commit in upstream.json (or REF), fills its
# sdk/thirdparty the way its tools/fetch_thirdparty.py does (the ReXGlue SDK
# release it is based on, with submodules; files FH2 Recompiled changed are
# kept), then applies this repository's patches/*.patch.
#
#   scripts/prepare.sh WORKDIR [REF]
#
# WORKDIR/fh2-recompiled   the patched tree; app/generated, app/out,
#                          sdk/out and assets/ are left alone
# WORKDIR/rexglue-sdk      the pristine SDK release (source of thirdparty)
#
# Run again, it checks out and patches again; files that end up the same keep
# their times (scripts/keep-times.py), so a later build recompiles only what
# changed. No game files are involved.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mkdir -p "$1" && cd "$1" && pwd)"

field() {
    python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
        "$repo/upstream.json" "$1"
}
ref="${2:-$(field commit)}"
fh2="$work/fh2-recompiled"
sdk="$work/rexglue-sdk"
times="$work/.prepare-times.json"
python3 "$repo/scripts/keep-times.py" save "$times" "$fh2"

if [ ! -d "$fh2/.git" ]; then
    git clone -q -c core.autocrlf=false "$(field repository)" "$fh2"
fi
git -C "$fh2" fetch -q origin "$ref" 2>/dev/null || git -C "$fh2" fetch -q origin
git -C "$fh2" -c advice.detachedHead=false checkout -q --force "$ref"
# Files an earlier patch added; checkout --force leaves them. Generated code,
# build folders, thirdparty and the game files stay.
git -C "$fh2" clean -fdq -e generated -e out -e thirdparty -e assets -e codegen.log
echo "FH2 Recompiled $(git -C "$fh2" rev-parse --short HEAD)"

sdk_commit="$(sed -n "s/^COMMIT = '\([0-9a-f]\{40\}\)'.*/\1/p" "$fh2/tools/fetch_thirdparty.py")"
if [ "${#sdk_commit}" -ne 40 ]; then
    sdk_commit="$(field sdk_commit)"
    echo "note: no SDK commit in tools/fetch_thirdparty.py; using upstream.json's"
elif [ "$sdk_commit" != "$(field sdk_commit)" ]; then
    echo "note: FH2 Recompiled now pins SDK $sdk_commit (upstream.json: $(field sdk_commit))"
fi
if [ ! -d "$sdk/.git" ]; then
    git init -q "$sdk"
    git -C "$sdk" remote add origin "$(field sdk_repository)"
fi
if [ "$(git -C "$sdk" rev-parse -q --verify HEAD 2>/dev/null)" != "$sdk_commit" ]; then
    git -C "$sdk" fetch -q --depth 1 origin "$sdk_commit"
    git -C "$sdk" -c advice.detachedHead=false checkout -q --force FETCH_HEAD
    git -C "$sdk" submodule update --init --recursive --force --depth 1 -q ||
        git -C "$sdk" submodule update --init --recursive --force -q
fi
echo "ReXGlue SDK $(git -C "$sdk" rev-parse --short HEAD) (thirdparty)"
# Like fetch_thirdparty.py: copy what sdk/thirdparty does not have yet.
tar -C "$sdk/thirdparty" --exclude=.git -cf - . | tar -C "$fh2/sdk/thirdparty" --skip-old-files -xf -

for patch in "$repo"/patches/*.patch; do
    [ -e "$patch" ] || continue
    git -C "$fh2" apply --whitespace=nowarn "$patch"
    echo "Applied ${patch#"$repo"/}"
done

python3 "$repo/scripts/keep-times.py" restore "$times"
