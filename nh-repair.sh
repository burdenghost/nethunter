#!/data/data/com.termux/files/usr/bin/bash
# NetHunter Termux Repair & Diagnostics
# Runs from Termux and invokes the installed NetHunter launcher.
set -u

VERSION="0.1.0"
MODE="${1:-diagnose}"

usage() {
  cat <<'EOF'
NetHunter Repair & Diagnostics (Termux)
Usage: ./nh-repair.sh [diagnose|repair|db-check|help]

  diagnose  Read-only package, library, PostgreSQL and Metasploit checks (default)
  db-check  Focused PostgreSQL/Metasploit checks
  repair    Ask before running safe APT recovery commands
  help      Show this help

The script does not delete databases, purge packages, or reset PostgreSQL data.
EOF
}

case "$MODE" in
  help|-h|--help) usage; exit 0 ;;
  diagnose|repair|db-check) ;;
  *) echo "Unknown mode: $MODE"; usage; exit 2 ;;
esac

if [ -n "${PREFIX:-}" ] && [ -x "$PREFIX/bin/nethunter" ]; then
  NH="$PREFIX/bin/nethunter"
elif command -v nethunter >/dev/null 2>&1; then
  NH="$(command -v nethunter)"
elif command -v nh >/dev/null 2>&1; then
  NH="$(command -v nh)"
else
  echo "[ERROR] NetHunter launcher not found in Termux."
  echo "Install/configure NetHunter first, then rerun this script."
  exit 127
fi

echo "NetHunter Repair & Diagnostics v$VERSION"
echo "Launcher: $NH"
echo "Mode: $MODE"
echo "Note: Termux is the control layer; package checks run inside Kali."
echo

# Run a self-contained diagnostic in the NetHunter root environment.
# The heredoc is fed to bash inside Kali; no script is copied into the rootfs.
"$NH" -r bash -s -- "$MODE" <<'KALI_SCRIPT'
set +e
MODE="${1:-diagnose}"
export DEBIAN_FRONTEND=noninteractive

section() { printf '\n\033[1;36m== %s ==\033[0m\n' "$1"; }
ok()      { printf '[ OK ] %s\n' "$1"; }
warn()    { printf '[WARN] %s\n' "$1"; }
fail()    { printf '[FAIL] %s\n' "$1"; }

section "Environment"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"
fi
printf 'Architecture: '; dpkg --print-architecture 2>/dev/null || uname -m
printf 'Identity: '; id
printf 'Root filesystem: '; df -h / 2>/dev/null | tail -n 1
printf 'APT lists: '
if [ -d /var/lib/apt/lists ] && find /var/lib/apt/lists -type f -name '*Packages*' -print -quit 2>/dev/null | grep -q .; then
  ok "package index files present"
else
  warn "package indexes missing or empty; apt update may be needed"
fi

section "APT / dpkg health"
if command -v dpkg >/dev/null 2>&1; then
  dpkg --audit 2>&1
  audit_rc=$?
  if [ "$audit_rc" -eq 0 ]; then ok "dpkg audit completed"; else warn "dpkg audit returned $audit_rc"; fi
  printf 'Packages not fully installed/configured: '
  dpkg -l 2>/dev/null | awk '$1 ~ /^(iU|iF|iH|un|pn)$/ {n++} END {print n+0}'
else
  fail "dpkg not found"
fi
if command -v apt-get >/dev/null 2>&1; then
  apt-get check 2>&1
  check_rc=$?
  if [ "$check_rc" -eq 0 ]; then ok "APT dependency check passed"; else warn "APT dependency check failed (exit $check_rc)"; fi
else
  fail "apt-get not found"
fi

section "Library / linker checks"
for tool in ldd ldconfig; do
  if command -v "$tool" >/dev/null 2>&1; then ok "$tool available"; else warn "$tool missing"; fi
done
if command -v ldd >/dev/null 2>&1; then
  for bin in /usr/bin/msfconsole /usr/bin/psql /usr/lib/postgresql/*/bin/postgres; do
    [ -e "$bin" ] || continue
    echo "-- $bin"
    ldd "$bin" 2>&1 | grep -E 'not found|statically linked|=> ' | head -n 25
  done
fi

section "PostgreSQL"
if command -v psql >/dev/null 2>&1; then
  psql --version 2>&1
  ok "psql client installed"
else
  warn "psql client not found"
fi
if command -v pg_lsclusters >/dev/null 2>&1; then
  pg_lsclusters 2>&1
else
  warn "pg_lsclusters unavailable (postgresql-common may be missing)"
fi
if command -v pg_ctlcluster >/dev/null 2>&1; then
  ok "pg_ctlcluster available"
fi
if command -v pg_isready >/dev/null 2>&1; then
  pg_isready 2>&1
  pg_ready_rc=$?
  if [ "$pg_ready_rc" -eq 0 ]; then ok "PostgreSQL accepts local connections"; else warn "PostgreSQL is not accepting connections (this may be expected if not started)"; fi
else
  warn "pg_isready unavailable"
fi
if command -v service >/dev/null 2>&1; then
  service postgresql status 2>&1 || true
fi

section "Metasploit"
if command -v msfconsole >/dev/null 2>&1; then
  msfconsole --version 2>&1 | head -n 3
  if command -v msfdb >/dev/null 2>&1; then
    msfdb status 2>&1 || true
  else
    warn "msfdb helper not found"
  fi
  if [ -f /usr/share/metasploit-framework/config/database.yml ]; then
    ok "Metasploit database config template exists"
  else
    warn "Metasploit database config template not found"
  fi
else
  warn "msfconsole not installed"
fi
echo "Important: Kali documents Metasploit database support as unavailable in NetHunter Rootless."
echo "A healthy PostgreSQL install alone does not guarantee supported Metasploit DB integration."

if [ "$MODE" = "repair" ]; then
  section "Safe APT repair"
  echo "This mode runs apt-get update, dpkg --configure -a, and apt-get -f install."
  echo "It does not purge packages or delete PostgreSQL data."
  printf 'Proceed with package-manager repair? Type YES to continue: '
  read -r answer
  if [ "$answer" != "YES" ]; then
    echo "Cancelled; no repair commands were run."
    exit 0
  fi

  echo "-- apt-get update"
  apt-get update
  update_rc=$?
  if [ "$update_rc" -ne 0 ]; then warn "apt-get update returned $update_rc; continuing to collect repair results"; fi

  echo "-- dpkg --configure -a"
  dpkg --configure -a
  configure_rc=$?
  if [ "$configure_rc" -ne 0 ]; then warn "dpkg configuration returned $configure_rc"; fi

  echo "-- apt-get -f install"
  apt-get -f install
  fix_rc=$?
  if [ "$fix_rc" -ne 0 ]; then warn "apt dependency repair returned $fix_rc"; fi

  echo "-- final apt-get check"
  apt-get check
  final_rc=$?
  if [ "$final_rc" -eq 0 ]; then ok "APT dependency check passes after repair"; else fail "APT dependency issues remain (exit $final_rc)"; fi
  echo "Repair finished. Review all warnings above; no data directory was reset."
fi

section "Summary"
echo "Diagnostics complete. Save the output when asking for help."
KALI_SCRIPT
