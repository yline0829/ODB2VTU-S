#!/usr/bin/env bash
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$HOME/.local/share/odb2vtu-s/workbench"
APPS="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_NAME="odb2vtu-s-exporter.png"
ICON_SRC="$PREFIX/icons/$ICON_NAME"
ICON_DST="$ICON_DIR/$ICON_NAME"
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

# The unified v0.2.1 Workbench uses the original ODB2VTU-S Exporter icon.
# Install it both beside the program and into the standard per-user hicolor
# theme so GNOME/CentOS can resolve it by name.
if [ ! -s "$ICON_SRC" ]; then
  echo "ERROR: required icon is missing: $ICON_SRC" >&2
  exit 2
fi
cp -f "$ICON_SRC" "$ICON_DST"
chmod 0644 "$ICON_DST"

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
Icon=$ICON_DST
Path=$PREFIX
Terminal=false
StartupNotify=true
Categories=Science;Engineering;
EOF
chmod +x "$DESKTOP_FILE"

# Also put the same launcher on the user's actual Desktop. xdg-user-dirs
# handles localized desktop directory names; Desktop is the fallback.
DESKTOP_DIR=""
if command -v xdg-user-dir >/dev/null 2>&1; then
  DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
fi
if [ -z "$DESKTOP_DIR" ]; then
  DESKTOP_DIR="$HOME/Desktop"
fi
mkdir -p "$DESKTOP_DIR"
DESKTOP_SHORTCUT="$DESKTOP_DIR/ODB2VTU-S Workbench.desktop"
cp -f "$DESKTOP_FILE" "$DESKTOP_SHORTCUT"
chmod +x "$DESKTOP_SHORTCUT"

# GNOME/CentOS 7 may retain launcher metadata. Mark the new desktop file as
# trusted when GIO is available; otherwise leave the valid executable .desktop
# file in place.
if command -v gio >/dev/null 2>&1; then
  gio set "$DESKTOP_SHORTCUT" metadata::trusted true 2>/dev/null || true
fi

# Refresh the per-user application database when the utility is available.
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

# Remove obsolete standalone launchers only; never touch user ODB/VTU/PVD/INP data.
rm -f "$APPS/odb2vtu-s-exporter.desktop" "$APPS/odb2vtu-s-cpfem-postprocessor.desktop"
rm -f "$DESKTOP_DIR/ODB2VTU-S Exporter.desktop" "$DESKTOP_DIR/ODB2VTU-S CPFEM Postprocessor.desktop"

echo "Installed unified ODB2VTU-S Workbench v0.2.1"
echo "Install root : $PREFIX"
echo "Desktop icon  : $DESKTOP_SHORTCUT"
echo "Menu entry    : $DESKTOP_FILE"
echo "Icon          : $ICON_DST"
echo "Abaqus command: singularity exec /home/soft/abaqus2024.sif /opt/run_abaqus.sh"
