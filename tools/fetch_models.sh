#!/usr/bin/env bash
set -euo pipefail
# Only two CC0 rigged models, 7.23 MB total. No asset-store bundles.
REV=672074b73ba276876a19e8816ecdc5241817ab47
BASE="https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/$REV/addons/kaykit_character_pack_adventures/Characters/gltf"
mkdir -p assets/characters
get_model() {
  local source="$1" dest="$2" min_size="$3"
  if [ ! -f "assets/characters/$dest" ]; then
    echo "Fetching CC0 character: $source"
    curl -fL --retry 3 --connect-timeout 20 "$BASE/$source" -o "assets/characters/$dest.tmp"
    mv "assets/characters/$dest.tmp" "assets/characters/$dest"
  fi
  local actual
  actual="$(wc -c < "assets/characters/$dest")"
  if [ "$actual" -ne "$min_size" ]; then
    echo "ERROR: unexpected asset size for $dest ($actual bytes, expected $min_size)" >&2
    exit 1
  fi
}
get_model Rogue.glb rogue.glb 3616284
get_model Barbarian.glb barbarian.glb 3613268
echo "Character assets ready: 7.23 MB total; KayKit CC0."
