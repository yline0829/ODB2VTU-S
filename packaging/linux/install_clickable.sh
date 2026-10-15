#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$HOME/.local/share/odb2vtu-s/workbench"
APPS="$HOME/.local/share/applications"
mkdir -p "$PREFIX" "$APPS"
if [ -f "$SRC/launch.sh" ]; then
  cp -a "$SRC"/. "$PREFIX"/
else
  # Running installer from a source-code checkout.
  REPO="$(cd "$SRC/../.." && pwd)"
  cp -a "$REPO/src/data_exporter/linux"/. "$PREFIX"/
  cp -a "$REPO/src/data_exporter/backend"/. "$PREFIX"/
  cp -a "$REPO/src/postprocess/backend"/. "$PREFIX"/
  cp -a "$REPO/scripts/diagnose_output_readonly.py" "$PREFIX/"
  mkdir -p "$PREFIX/icons"
  cp -a "$REPO/assets/icons"/. "$PREFIX/icons/"
fi
chmod +x "$PREFIX/launch.sh"
cat > "$APPS/odb2vtu-s-workbench.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=ODB2VTU-S Workbench
Exec=$PREFIX/launch.sh
Icon=$PREFIX/icons/odb2vtu-s-exporter.png
Terminal=false
Categories=Science;Engineering;
StartupNotify=true
EOF
chmod +x "$APPS/odb2vtu-s-workbench.desktop"
# Remove OLD launcher shortcuts only; never touch existing ODB/VTU/PVD/Manifest.
rm -f "$APPS/odb2vtu-s-exporter.desktop" "$APPS/odb2vtu-s-cpfem-postprocessor.desktop"
echo "Installed unified ODB2VTU-S workbench to $PREFIX"
echo "Use Edit -> CPFEM or Tools -> Audit/Recovery inside the same GUI."
