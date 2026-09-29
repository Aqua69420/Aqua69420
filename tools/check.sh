#!/usr/bin/env bash
# Compile every exported script exactly like Roblox Studio does (-O0), using the
# official Luau compiler. Catches errors Lune's luau.compile does not, e.g.
# "Out of local registers ... exceeded limit 200".
# usage: tools/check.sh [file ...]
set -u
here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/.bin/luau-compile"
if [ ! -x "$bin" ]; then
	mkdir -p "$here/.bin"
	ver=$(git ls-remote --tags https://github.com/luau-lang/luau | awk -F/ '{print $3}' | grep -E '^[0-9]+\.[0-9]+$' | sort -V | tail -1)
	curl -sSL -o "$here/.bin/luau.zip" "https://github.com/luau-lang/luau/releases/download/$ver/luau-ubuntu.zip"
	unzip -o -q "$here/.bin/luau.zip" -d "$here/.bin" && rm "$here/.bin/luau.zip"
fi
if [ $# -gt 0 ]; then files=("$@"); else mapfile -t files < <(find "$here/../place/scripts" -name '*.lua'); fi
fail=0
for f in "${files[@]}"; do
	out=$("$bin" --null -O0 "$f" 2>&1) || { echo "FAIL $f"; echo "$out" | grep -v '^Compiled'; fail=$((fail+1)); }
done
if [ $fail -eq 0 ]; then echo "all ${#files[@]} scripts compile (-O0)"; else echo "$fail failed"; exit 1; fi
