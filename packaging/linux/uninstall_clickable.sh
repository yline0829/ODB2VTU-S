#!/usr/bin/env bash
set -euo pipefail
PREFIX="$HOME/.local/share/odb2vtu-s/workbench"
APPS="$HOME/.local/share/applications"
ICON_DST="$HOME/.local/share/icons/hicolor/256x256/apps/odb2vtu-s-exporter.png"

rm -rf "$PREFIX"
rm -f "$APPS/odb2vtu-s-workbench.desktop"
rm -f "$ICON_DST"

DESKTOP_DIR=""
if command -v xdg-user-dir >/dev/null 2>&1; then
  DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
fi
if [ -z "$DESKTOP_DIR" ]; then
  DESKTOP_DIR="$HOME/Desktop"
fi
rm -f "$DESKTOP_DIR/ODB2VTU-S Workbench.desktop"
echo "Unified ODB2VTU-S Workbench removed. User ODB/VTU/PVD/Manifest/INP untouched."
