#!/usr/bin/env bash
set -euo pipefail

# Repair only the ODB2VTU-S desktop launcher/icon.
# User ODB/VTU/PVD/Manifest/INP files are never touched.

PREFIX="$HOME/.local/share/odb2vtu-s/workbench"
APPS="$HOME/.local/share/applications"
ICON_THEME="$HOME/.local/share/icons/hicolor"
ICON_DIR="$ICON_THEME/256x256/apps"
ICON_DIR_128="$ICON_THEME/128x128/apps"
ICON_NAME="odb2vtu-s-exporter"
ICON_FILE="$ICON_NAME.png"
ICON_FILE_256="$ICON_NAME-256.png"
ICON="$PREFIX/icons/$ICON_FILE"
DESKTOP_FILE="$APPS/odb2vtu-s-workbench.desktop"

if [ ! -s "$ICON" ]; then
  echo "ERROR: installed ODB2VTU-S icon not found: $ICON" >&2
  echo "Please run install_clickable.sh from the v1.0.0 package first." >&2
  exit 2
fi

ICON_256="$PREFIX/icons/$ICON_FILE_256"
[ -s "$ICON_256" ] || ICON_256="$ICON"
for ICON_IN in "$ICON" "$ICON_256"; do
  MAGIC="$(od -An -tx1 -N8 "$ICON_IN" 2>/dev/null | tr -d ' \n' || true)"
  if [ "$MAGIC" != "89504e470d0a1a0a" ]; then
    echo "ERROR: installed icon is not a valid PNG: $ICON_IN" >&2
    exit 3
  fi
done

mkdir -p "$APPS" "$ICON_DIR" "$ICON_DIR_128"
cp -f "$ICON_256" "$ICON_DIR/$ICON_FILE"
cp -f "$ICON" "$ICON_DIR_128/$ICON_FILE"
chmod 0644 "$ICON" "$ICON_256" "$ICON_DIR/$ICON_FILE" "$ICON_DIR_128/$ICON_FILE"

if [ ! -f "$ICON_THEME/index.theme" ]; then
  cat > "$ICON_THEME/index.theme" <<'EOF'
[Icon Theme]
Name=Hicolor
Comment=Fallback icon theme
Directories=256x256/apps,128x128/apps

[256x256/apps]
Size=256
Context=Applications
Type=Fixed

[128x128/apps]
Size=128
Context=Applications
Type=Fixed
EOF
fi

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=ODB2VTU-S Workbench
Name[zh_CN]=ODB2VTU-S 工作台
Comment=ODB export, field analysis, friction CPFEM and safe recovery
Comment[zh_CN]=ODB 导出、场变量分析、摩擦 CPFEM 与安全恢复
Exec=$PREFIX/launch.sh
TryExec=$PREFIX/launch.sh
Icon=$ICON_NAME
Path=$PREFIX
Terminal=false
StartupNotify=true
StartupWMClass=odb2vtu-s-workbench
Categories=Science;Engineering;
EOF
chmod 0755 "$DESKTOP_FILE"

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
mkdir -p "$DESKTOP_DIR"

SHORTCUT="$DESKTOP_DIR/ODB2VTU-S Workbench.desktop"
rm -f "$SHORTCUT"
cp -f "$DESKTOP_FILE" "$SHORTCUT"
chmod 0755 "$SHORTCUT"

ICON_URI="file://$ICON"
if command -v gio >/dev/null 2>&1; then
  if command -v dbus-launch >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    dbus-launch --exit-with-session gio set "$SHORTCUT" metadata::trusted true 2>/dev/null || true
    dbus-launch --exit-with-session gio set -t string "$SHORTCUT" metadata::custom-icon "$ICON_URI" 2>/dev/null || true
  fi
  gio set "$SHORTCUT" metadata::trusted true 2>/dev/null || true
  gio set -t string "$SHORTCUT" metadata::custom-icon "$ICON_URI" 2>/dev/null || true
elif command -v gvfs-set-attribute >/dev/null 2>&1; then
  gvfs-set-attribute -t string "$SHORTCUT" metadata::trusted true 2>/dev/null || true
  gvfs-set-attribute -t string "$SHORTCUT" metadata::custom-icon "$ICON_URI" 2>/dev/null || true
fi
touch "$SHORTCUT"

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$DESKTOP_FILE" >/dev/null 2>&1 || {
    echo "ERROR: desktop entry validation failed: $DESKTOP_FILE" >&2
    exit 4
  }
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$ICON_THEME" >/dev/null 2>&1 || true
fi

echo "ODB2VTU-S desktop icon repaired for v1.0.0."
echo "Desktop : $SHORTCUT"
echo "Icon    : $ICON"
