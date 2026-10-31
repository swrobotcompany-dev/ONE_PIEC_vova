#!/usr/bin/env bash
set -euo pipefail
cd /game
mkdir -p /dist/windows /dist/linux
godot --headless --editor --path /game --import
# Validate procedural islands, generated meshes and HUD without a window.
godot --headless --path /game --script res://tools/smoke.gd
# Boot a real headless server briefly to check the multiplayer scene.
godot --headless --path /game --quit-after 5 -- --server
godot --headless --path /game --export-release "Linux/X11" /dist/linux/GrandSea.x86_64
godot --headless --path /game --export-release "Windows Desktop" /dist/windows/GrandSea.exe
chmod +x /dist/linux/GrandSea.x86_64
echo "Native clients are in dist/linux and dist/windows."
