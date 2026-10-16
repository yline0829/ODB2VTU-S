#!/usr/bin/env bash
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$HOME/.local/share/odb2vtu-s/workbench"
APPS="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_NAME="odb2vtu-s-exporter.png"
DESKTOP_FILE="$APPS/odb2vtu-s-workbench.desktop"

mkdir -p "$PREFIX" "$APPS" "$ICON_DIR"

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
  cp -a "$REPO/assets/icons"/. "$PREFIX/icons/"
fi

chmod +x "$PREFIX/launch.sh"

# Pin the desktop icon to the the supplied ODB2VTU-S Exporter icon (uploaded artwork).
# PNG is the supplied ODB2VTU-S Exporter artwork, normalized to 128x128 for the repository icon slot.
# SHA-256 of the PNG: 1bce724fe4371f70d9c5fd1fa8587096421dda055c64cc543857a9e4059435d8
ICON_SRC="$PREFIX/icons/$ICON_NAME"
if [ ! -s "$ICON_SRC" ]; then
  echo "ERROR: required icon is missing: $ICON_SRC" >&2
  exit 2
fi

# Validate PNG magic bytes before installing it. This catches incomplete
# package copies instead of silently producing a generic document icon.
PNG_MAGIC="$(od -An -tx1 -N8 "$ICON_SRC" 2>/dev/null | tr -d ' \n' || true)"
if [ "$PNG_MAGIC" != "89504e470d0a1a0a" ]; then
  echo "ERROR: icon is not a valid PNG: $ICON_SRC" >&2
  exit 3
fi

EXPECTED_ICON_SHA256="1bce724fe4371f70d9c5fd1fa8587096421dda055c64cc543857a9e4059435d8"
ACTUAL_ICON_SHA256="$(sha256sum "$ICON_SRC" | awk '{print $1}')"
if [ "$ACTUAL_ICON_SHA256" != "$EXPECTED_ICON_SHA256" ]; then
  echo "ERROR: desktop icon does not match the supplied ODB2VTU-S Exporter artwork." >&2
  echo "Expected: $EXPECTED_ICON_SHA256" >&2
  echo "Actual  : $ACTUAL_ICON_SHA256" >&2
  exit 5
fi

# Keep a theme copy for menus, but the desktop launcher deliberately points
# to the absolute program-local icon path. This avoids hicolor cache/name
# resolution differences on CentOS 7 GNOME.
cp -f "$ICON_SRC" "$ICON_DIR/$ICON_NAME"
chmod 0644 "$ICON_SRC" "$ICON_DIR/$ICON_NAME"

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
Icon=$ICON_SRC
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

# On GNOME/Nautilus, the desktop launcher must be trusted before its real
# Name/Icon is displayed. Prefer a session DBus when this installer is run
# from a graphical terminal; fall back to plain gio where available.
if command -v gio >/dev/null 2>&1; then
  if command -v dbus-launch >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    dbus-launch --exit-with-session gio set "$DESKTOP_SHORTCUT" metadata::trusted true 2>/dev/null || true
  fi
  gio set "$DESKTOP_SHORTCUT" metadata::trusted true 2>/dev/null || true
fi
touch "$DESKTOP_SHORTCUT"

# Validate the generated desktop entry when desktop-file-utils is present.
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$DESKTOP_FILE" >/dev/null 2>&1 || {
    echo "ERROR: generated desktop entry failed validation: $DESKTOP_FILE" >&2
    exit 4
  }
fi

# Refresh per-user desktop metadata. The icon itself does not depend on this
# cache because Icon= uses the absolute PNG path above.
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

# Refresh the GTK hicolor cache when a usable user theme exists.
if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -f "$HOME/.local/share/icons/hicolor/index.theme" ]; then
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
fi

# Remove obsolete standalone launchers only; never touch user ODB/VTU/PVD/INP data.
rm -f "$APPS/odb2vtu-s-exporter.desktop" "$APPS/odb2vtu-s-cpfem-postprocessor.desktop"
rm -f "$DESKTOP_DIR/ODB2VTU-S Exporter.desktop" "$DESKTOP_DIR/ODB2VTU-S CPFEM Postprocessor.desktop"

echo "Installed unified ODB2VTU-S Workbench v0.2.1"
echo "Install root : $PREFIX"
echo "Desktop icon  : $DESKTOP_SHORTCUT"
echo "Menu entry    : $DESKTOP_FILE"
echo "Icon          : $ICON_SRC"
echo "Abaqus command: ${ABAQUS_CMD:-singularity exec /home/soft/abaqus2024.sif /opt/run_abaqus.sh}"
