#!/usr/bin/env bash
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$HOME/.local/share/odb2vtu-s/workbench"
APPS="$HOME/.local/share/applications"
ICON_THEME="$HOME/.local/share/icons/hicolor"
ICON_DIR="$ICON_THEME/256x256/apps"
ICON_DIR_128="$ICON_THEME/128x128/apps"
ICON_NAME="odb2vtu-s-exporter"
ICON_FILE="$ICON_NAME.png"
DESKTOP_FILE="$APPS/odb2vtu-s-workbench.desktop"

mkdir -p "$PREFIX" "$APPS" "$ICON_DIR" "$ICON_DIR_128"

# The release ZIP contains launch.sh + all runtime files in one directory.
# A source checkout contains the same modules in their repository locations.
if [ -f "$SRC/launch.sh" ]; then
  cp -a "$SRC"/. "$PREFIX"/
else
  REPO="$(cd "$SRC/../.." && pwd)"
  cp -a "$REPO/src/data_exporter/linux"/. "$PREFIX"/
  cp -a "$REPO/src/data_exporter/backend"/. "$PREFIX"/
  cp -a "$REPO/src/postprocess/backend"/. "$PREFIX"/
  cp -a "$REPO/scripts/diagnose_output_readonly.py" "$PREFIX/"
  mkdir -p "$PREFIX/icons"
  cp -a "$REPO/assets/icons"/. "$PREFIX/icons"/
fi

chmod +x "$PREFIX/launch.sh"

# The supplied ODB2VTU-S artwork is the single source of truth.
ICON_SRC="$PREFIX/icons/$ICON_FILE"
if [ ! -s "$ICON_SRC" ]; then
  echo "ERROR: required icon is missing: $ICON_SRC" >&2
  exit 2
fi

# Validate PNG magic bytes before installing it.
PNG_MAGIC="$(od -An -tx1 -N8 "$ICON_SRC" 2>/dev/null | tr -d ' \n' || true)"
if [ "$PNG_MAGIC" != "89504e470d0a1a0a" ]; then
  echo "ERROR: icon is not a valid PNG: $ICON_SRC" >&2
  exit 3
fi

# Install the icon through the standard per-user hicolor theme.
# Do not pin a hard-coded checksum: the packaged artwork itself is authoritative.
cp -f "$ICON_SRC" "$ICON_DIR/$ICON_FILE"
cp -f "$ICON_SRC" "$ICON_DIR_128/$ICON_FILE"
chmod 0644 "$ICON_SRC" "$ICON_DIR/$ICON_FILE" "$ICON_DIR_128/$ICON_FILE"

# Some older CentOS 7 installations do not have a user hicolor index.
# Create a minimal one only when it is absent; never overwrite a user's theme.
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
Categories=Science;Engineering;
EOF
chmod 0755 "$DESKTOP_FILE"

# Find the actual desktop directory (Chinese CentOS installations commonly
# use ~/桌面 rather than ~/Desktop).
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

DESKTOP_SHORTCUT="$DESKTOP_DIR/ODB2VTU-S Workbench.desktop"
rm -f "$DESKTOP_SHORTCUT"
cp -f "$DESKTOP_FILE" "$DESKTOP_SHORTCUT"
chmod 0755 "$DESKTOP_SHORTCUT"

# CentOS 7 GNOME/Nautilus can cache desktop launcher icons. In addition to the
# standard Icon= name, set GIO custom-icon metadata on the actual desktop file.
ICON_URI="file://$ICON_SRC"
if command -v gio >/dev/null 2>&1; then
  if command -v dbus-launch >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    dbus-launch --exit-with-session gio set "$DESKTOP_SHORTCUT" metadata::trusted true 2>/dev/null || true
    dbus-launch --exit-with-session gio set -t string "$DESKTOP_SHORTCUT" metadata::custom-icon "$ICON_URI" 2>/dev/null || true
  fi
  gio set "$DESKTOP_SHORTCUT" metadata::trusted true 2>/dev/null || true
  gio set -t string "$DESKTOP_SHORTCUT" metadata::custom-icon "$ICON_URI" 2>/dev/null || true
elif command -v gvfs-set-attribute >/dev/null 2>&1; then
  gvfs-set-attribute -t string "$DESKTOP_SHORTCUT" metadata::trusted true 2>/dev/null || true
  gvfs-set-attribute -t string "$DESKTOP_SHORTCUT" metadata::custom-icon "$ICON_URI" 2>/dev/null || true
fi
touch "$DESKTOP_SHORTCUT"

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$DESKTOP_FILE" >/dev/null 2>&1 || {
    echo "ERROR: generated desktop entry failed validation: $DESKTOP_FILE" >&2
    exit 4
  }
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$ICON_THEME" >/dev/null 2>&1 || true
fi

# Remove obsolete standalone launchers only; never touch user ODB/VTU/PVD/INP data.
rm -f "$APPS/odb2vtu-s-exporter.desktop" "$APPS/odb2vtu-s-cpfem-postprocessor.desktop"
rm -f "$DESKTOP_DIR/ODB2VTU-S Exporter.desktop" "$DESKTOP_DIR/ODB2VTU-S CPFEM Postprocessor.desktop"

echo "Installed unified ODB2VTU-S Workbench v0.2.2"
echo "Install root : $PREFIX"
echo "Desktop icon  : $DESKTOP_SHORTCUT"
echo "Menu entry    : $DESKTOP_FILE"
echo "Icon          : $ICON_SRC"
echo "Abaqus command: ${ABAQUS_CMD:-singularity exec /home/soft/abaqus2024.sif /opt/run_abaqus.sh}"
