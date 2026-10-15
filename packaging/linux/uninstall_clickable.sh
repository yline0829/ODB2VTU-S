#!/usr/bin/env bash
set -euo pipefail
PREFIX="$HOME/.local/share/odb2vtu-s/workbench"
rm -rf "$PREFIX"
rm -f "$HOME/.local/share/applications/odb2vtu-s-workbench.desktop"
echo "Unified ODB2VTU-S workbench removed. User ODB/VTU/PVD/Manifest/INP untouched."
