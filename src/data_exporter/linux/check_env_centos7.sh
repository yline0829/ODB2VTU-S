#!/usr/bin/env bash
# =============================================================================
# ODB2VTU-S Workbench v1.0.0 - CentOS 7 preflight check
#
# Verifies that this machine can run the Tk GUI and the Abaqus/ODB backends.
# Read-only: nothing is installed and no existing file is modified.
#
#   ./check_env_centos7.sh          fast checks (does not start Abaqus)
#   ./check_env_centos7.sh --deep   additionally runs abaqus_env_check.py
#                                   through $ABAQUS_CMD (starts the container)
#
# Environment overrides:
#   PYTHON_BIN=/usr/bin/python3.6     GUI interpreter to validate
#   ABAQUS_CMD='singularity exec ...' Abaqus launcher to validate
#
# Exit code: 0 = no blocking problem (warnings allowed), 1 = blocking problem.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PYTHON_BIN:-python3}"
ABAQUS_CMD_DEFAULT='singularity exec /home/soft/abaqus2024.sif /opt/run_abaqus.sh'
ABAQUS_CMD="${ABAQUS_CMD:-$ABAQUS_CMD_DEFAULT}"

DEEP=0
[ "${1:-}" = "--deep" ] && DEEP=1

FAIL=0
WARN=0
ok()      { printf '  [ OK ] %s\n' "$*"; }
info()    { printf '  [info] %s\n' "$*"; }
warn()    { printf '  [WARN] %s\n' "$*"; WARN=$((WARN + 1)); }
bad()     { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }
section() { printf '\n== %s ==\n' "$*"; }

section 'Operating system'
if [ -r /etc/redhat-release ]; then
  info "$(cat /etc/redhat-release)"
else
  warn 'no /etc/redhat-release: this does not look like RHEL/CentOS (continuing anyway)'
fi
info "kernel $(uname -r) on $(uname -m)"

section 'GUI interpreter (python3 + Tkinter)'
if ! command -v "$PY" >/dev/null 2>&1; then
  bad "$PY not found. Install it:  sudo yum install -y python3 python3-tkinter"
else
  ok "$PY -> $("$PY" -c 'import sys; print(sys.executable)')"
  if "$PY" -c 'import sys; sys.exit(0 if sys.version_info[:2] >= (3, 6) else 1)'; then
    ok "version $("$PY" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
  else
    bad "python3 is older than 3.6 ($("$PY" -c 'import sys; print(sys.version.split()[0])')). Install python3.6 from the base repo or EPEL."
  fi
  if "$PY" -c 'import tkinter, tkinter.ttk' >/dev/null 2>&1; then
    ok "tkinter available (Tk $("$PY" -c 'import tkinter; print(tkinter.TkVersion)'))"
  else
    bad "tkinter missing. Install it:  sudo yum install -y python3-tkinter   (older EPEL name: python36-tkinter)"
  fi
fi

section 'X display'
if [ -n "${DISPLAY:-}" ]; then
  ok "DISPLAY=$DISPLAY"
  if command -v "$PY" >/dev/null 2>&1 \
     && "$PY" -c 'import tkinter; w = tkinter.Tk(); w.destroy()' >/dev/null 2>&1; then
    ok 'a Tk window can really be created on this display'
  else
    warn 'Tk could not open a window on DISPLAY (X11 authorisation or driver problem?)'
  fi
else
  warn 'DISPLAY is empty: the GUI needs an X session. Use the machine console or "ssh -X".'
fi

section 'Chinese font and locale'
if command -v fc-list >/dev/null 2>&1; then
  if [ -n "$(fc-list :lang=zh 2>/dev/null)" ]; then
    ok "CJK fonts installed ($(fc-list :lang=zh 2>/dev/null | wc -l) entries)"
  else
    warn 'no CJK font found: Chinese labels will render as empty boxes. sudo yum install -y wqy-microhei-fonts wqy-zenhei-fonts'
  fi
else
  warn 'fc-list not available (install fontconfig) - cannot check CJK fonts'
fi
case "${LANG:-}:${LC_ALL:-}" in
  *[Uu][Tt][Ff]*8*) ok "UTF-8 locale: LANG=${LANG:-unset}" ;;
  *) warn "LANG=${LANG:-unset} is not UTF-8; add 'export LANG=zh_CN.UTF-8' (or en_US.UTF-8) to ~/.bashrc" ;;
esac

section 'Abaqus launcher'
info "ABAQUS_CMD=$ABAQUS_CMD"
# Word splitting is intentional: ABAQUS_CMD is a command line.
# shellcheck disable=SC2086
set -- $ABAQUS_CMD
LAUNCHER="${1:-}"
if [ -z "$LAUNCHER" ]; then
  bad 'ABAQUS_CMD is empty'
elif command -v "$LAUNCHER" >/dev/null 2>&1; then
  ok "launcher found: $(command -v "$LAUNCHER")"
else
  bad "launcher '$LAUNCHER' is not on PATH (fix PATH or set ABAQUS_CMD)"
fi
# shellcheck disable=SC2086
for word in $ABAQUS_CMD; do
  case "$word" in
    *.sif|*.simg)
      if [ -r "$word" ]; then ok "container image readable: $word"; else bad "container image not readable: $word"; fi
      ;;
    /*)
      if [ -e "$word" ]; then info "host path exists: $word"
      else info "not on the host (expected inside the container): $word"; fi
      ;;
  esac
done
if command -v singularity >/dev/null 2>&1; then
  info "singularity: $(singularity --version 2>&1 | head -n 1)"
elif command -v apptainer >/dev/null 2>&1; then
  info "apptainer: $(apptainer --version 2>&1 | head -n 1)"
else
  warn 'neither singularity nor apptainer is on PATH'
fi

section 'Package contents'
pkg_missing=0
for f in \
  abaqus_data_exporter_gui.py ui_i18n.py \
  odb_metadata.py odb_list_fields.py odb_export_vtu.py odb_export_series.py \
  odb_curve_history_meta.py odb_curve_history_export.py odb_field_analysis.py \
  abaqus_postprocess_master.py diagnose_output_readonly.py \
  odb_recovery_safe.py odb_legacy_migration.py odb_export_state.py \
  odb_export_inventory.py odb_vtu_incremental.py odb_export_legacy.py \
  odb_manifest_adoption.py odb_inplace_transaction.py odb_legacy_inplace.py \
  odb_legacy_baseline.py abaqus_env_check.py \
  launch.sh install_clickable.sh uninstall_clickable.sh fix_desktop_icon.sh \
  icons/odb2vtu-s-exporter.png ; do
  if [ ! -s "$HERE/$f" ]; then bad "missing or empty: $f"; pkg_missing=1; fi
done
[ "$pkg_missing" = "0" ] && ok 'all runtime modules, scripts and icons present'

section 'Line endings (must be LF on Linux)'
crlf=0
for f in "$HERE"/*.sh "$HERE"/*.py; do
  [ -e "$f" ] || continue
  if grep -qU $'\r' "$f" 2>/dev/null; then
    bad "CRLF line endings in $(basename "$f") (unpack with tar, or: sed -i 's/\\r$//' $(basename "$f"))"
    crlf=1
  fi
done
[ "$crlf" = "0" ] && ok 'all .sh/.py files are LF-only'

section 'Executable bits'
for f in launch.sh install_clickable.sh uninstall_clickable.sh fix_desktop_icon.sh check_env_centos7.sh; do
  if [ -x "$HERE/$f" ]; then ok "$f is executable"
  else warn "$f is not executable  (fix: chmod +x \"$HERE\"/*.sh)"; fi
done

section 'Desktop integration (optional)'
info "desktop=${XDG_CURRENT_DESKTOP:-unknown}  session=${XDG_SESSION_TYPE:-unknown}"
for c in xdg-user-dir gio update-desktop-database gtk-update-icon-cache desktop-file-validate; do
  if command -v "$c" >/dev/null 2>&1; then
    info "$c: present"
  else
    info "$c: missing (only affects desktop icon/menu integration)"
  fi
done

section 'Disk space'
avail_gib="$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { printf "%d", $4 / 1048576 }')"
if [ -n "$avail_gib" ] && [ "$avail_gib" -ge 20 ]; then
  ok "~${avail_gib} GiB free on \$HOME"
else
  warn "only ~${avail_gib:-?} GiB free on \$HOME; large ODB exports need far more"
fi

if [ "$DEEP" = "1" ]; then
  section 'Deep check (starts the Abaqus container, may take a minute)'
  # shellcheck disable=SC2086
  if timeout 600 $ABAQUS_CMD python "$HERE/abaqus_env_check.py"; then
    ok 'odbAccess works through ABAQUS_CMD'
  else
    bad 'abaqus_env_check.py failed through ABAQUS_CMD (see its output above)'
  fi
fi

section 'Summary'
printf '  failures: %d   warnings: %d\n' "$FAIL" "$WARN"
if [ "$FAIL" -gt 0 ]; then
  printf '  NOT ready: fix the [FAIL] items above, then run this check again.\n'
  exit 1
fi
printf '  Ready. Start the workbench with:  %s/launch.sh\n' "$HERE"
if [ "$DEEP" = "0" ]; then
  printf '  Optional end-to-end check:        %s/check_env_centos7.sh --deep\n' "$HERE"
fi
exit 0
