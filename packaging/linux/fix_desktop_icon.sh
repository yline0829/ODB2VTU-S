#!/usr/bin/env bash
set -euo pipefail

# Repair only the ODB2VTU-S desktop launcher/icon.
# The installed icon is pinned to the the supplied ODB2VTU-S Exporter icon (uploaded artwork).
# User ODB/VTU/PVD/Manifest/INP files are never touched.

PREFIX="$HOME/.local/share/odb2vtu-s/workbench"
APPS="$HOME/.local/share/applications"
ICON="$PREFIX/icons/odb2vtu-s-exporter.png"
DESKTOP_FILE="$APPS/odb2vtu-s-workbench.desktop"

if [ ! -s "$ICON" ]; then
  echo "ERROR: installed ODB2VTU-S icon not found: $ICON" >&2
  echo "Please run install_clickable.sh from the v0.2.1 package first." >&2
  exit 2
fi

MAGIC="$(od -An -tx1 -N8 "$ICON" 2>/dev/null | tr -d ' \n' || true)"
if [ "$MAGIC" != "89504e470d0a1a0a" ]; then
  echo "ERROR: installed icon is not a valid PNG: $ICON" >&2
  exit 3
fi

EXPECTED_ICON_SHA256="1bce724fe4371f70d9c5fd1fa8587096421dda055c64cc543857a9e4059435d8"
ACTUAL_ICON_SHA256="$(sha256sum "$ICON" | awk '{print $1}')"
if [ "$ACTUAL_ICON_SHA256" != "$EXPECTED_ICON_SHA256" ]; then
  echo "ERROR: installed icon does not match the supplied ODB2VTU-S Exporter artwork." >&2
  exit 5
fi

mkdir -p "$APPS"
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
Icon=$ICON
Path=$PREFIX
Terminal=false
StartupNotify=true
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

if command -v gio >/dev/null 2>&1; then
  if command -v dbus-launch >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    dbus-launch --exit-with-session gio set "$SHORTCUT" metadata::trusted true 2>/dev/null || true
  fi
  gio set "$SHORTCUT" metadata::trusted true 2>/dev/null || true
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

echo "ODB2VTU-S desktop icon repaired."
echo "Desktop : $SHORTCUT"
echo "Icon    : $ICON"
echo "If GNOME still shows the old paper icon, log out and back in once."
