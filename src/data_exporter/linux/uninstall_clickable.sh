#!/usr/bin/env bash
set -euo pipefail

PREFIX="$HOME/.local/share/odb2vtu-s/workbench"
APPS="$HOME/.local/share/applications"
ICON_THEME="$HOME/.local/share/icons/hicolor"
ICON_256="$ICON_THEME/256x256/apps/odb2vtu-s-exporter.png"
ICON_128="$ICON_THEME/128x128/apps/odb2vtu-s-exporter.png"

# Remove only ODB2VTU-S application files and launcher metadata.
# User ODB/VTU/PVD/Manifest/INP files are never touched.
rm -rf "$PREFIX"
rm -f "$APPS/odb2vtu-s-workbench.desktop"
rm -f "$ICON_256" "$ICON_128"

DESKTOP_DIR=""
if command -v xdg-user-dir >/dev/null 2>&1; then
  DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
fi
if [ -z "$DESKTOP_DIR" ] || [ "$DESKTOP_DIR" = "$HOME" ]; then
  if [ -d "$HOME/桌面" ]; then
    DESKTOP_DIR="$HOME/桌面"
  else
    DESKTOP_DIR="$HOME/Desktop"
  fi
fi

SHORTCUT="$DESKTOP_DIR/ODB2VTU-S Workbench.desktop"
rm -f "$SHORTCUT"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -d "$ICON_THEME" ]; then
  gtk-update-icon-cache -f -t "$ICON_THEME" >/dev/null 2>&1 || true
fi

echo "Unified ODB2VTU-S Workbench removed. User ODB/VTU/PVD/Manifest/INP files untouched."
