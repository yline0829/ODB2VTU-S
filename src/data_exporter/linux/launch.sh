#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# ODB2VTU-S v1.0.0 Linux target:
# CentOS 7 + SingularityCE + Abaqus 2024
# Verified Abaqus launcher:
#   singularity exec /home/soft/abaqus2024.sif /opt/run_abaqus.sh
#
# Users may override this without editing the program:
#   ABAQUS_CMD='...' ./launch.sh
export ABAQUS_CMD="${ABAQUS_CMD:-singularity exec /home/soft/abaqus2024.sif /opt/run_abaqus.sh}"

exec "${PYTHON_BIN:-python3}" "$HERE/abaqus_data_exporter_gui.py"
