#!/data/data/com.termux/files/usr/bin/bash
# NetHunter One-Stop Installer & Repair Toolkit
# Installs official Kali NetHunter Rootless from Termux, then provides
# diagnostics and conservative repair actions inside the Kali proot.
set -u

VERSION="1.0.0"
OFFICIAL_INSTALLER_URL="https://offs.ec/2MceZWr"
INSTALLER_PATH="${TMPDIR:-$HOME}/install-nethunter-termux"

banner() {
  printf '\n\033[1;36mNetHunter One-Stop Toolkit v%s\033[0m\n' "$VERSION"
  printf '%s\n' 'Install Kali NetHunter Rootless, diagnose it, and repair common Kali package issues.'
}
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

find_nh() {
  if [ -n "${PREFIX:-}" ] && [ -x "$PREFIX/bin/nethunter" ]; then
    printf '%s\n' "$PREFIX/bin/nethunter"
  elif have nethunter; then
    command -v nethunter
  elif have nh; then
    command -v nh
  else
    return 1
  fi
}

termux_check() {
  [ -n "${PREFIX:-}" ] || die "Run this script in Termux, not inside Kali or another shell."
  [ -x "$PREFIX/bin/bash" ] || die "Termux environment not detected."
}

install_nethunter() {
  banner
  printf '\n== Install NetHunter Rootless ==\n'
  if find_nh >/dev/null 2>&1; then
    echo "[OK] NetHunter launcher already exists. Skipping installation to protect the existing rootfs."
    return 0
  fi

  echo "Installing the small Termux-side prerequisites (curl, wget, proot, tar)."
  pkg install -y curl wget proot tar || die "Termux prerequisite installation failed."
  echo
  echo "Downloading the official Kali NetHunter Rootless installer:"
  echo "$OFFICIAL_INSTALLER_URL"
  curl -fL --retry 3 --connect-timeout 20 "$OFFICIAL_INSTALLER_URL" -o "$INSTALLER_PATH" ||
    die "Could not download the official installer."
  [ -s "$INSTALLER_PATH" ] || die "Downloaded installer is empty."
  chmod 700 "$INSTALLER_PATH" || die "Could not mark installer executable."
  echo
  echo "The official installer will now run interactively. Follow its prompts and keep Termux open."
  echo "No existing NetHunter installation will be overwritten by this toolkit."
  bash "$INSTALLER_PATH" || die "Official NetHunter installer exited with an error. Read its output before retrying."
  if find_nh >/dev/null 2>&1; then
    echo "[OK] NetHunter launcher detected after installation."
  else
    echo "[WARN] Installer finished but the launcher was not found. Reopen Termux and check the official install output."
    exit 1
  fi
}

run_kali() {
  local nh
  nh="$(find_nh)" || die "NetHunter is not installed. Choose Install first."
  "$nh" -r bash -s
}

diagnose() {
  echo
  echo "== NetHunter environment diagnostics (read-only) =="
  run_kali <<'KALI'
set +e
section(){ printf '\n== %s ==\n' "$1"; }
section "Kali / proot"
if [ -r /etc/os-release ]; then . /etc/os-release; echo "${PRETTY_NAME:-Unknown OS}"; fi
printf 'Architecture: '; dpkg --print-architecture 2>/dev/null || uname -m
printf 'Identity: '; id
printf 'Root filesystem free space: '; df -h / 2>/dev/null | awk 'NR==2 {print $4 " free of " $2}'
section "APT / dpkg"
dpkg --audit 2>&1
apt-get check 2>&1
printf 'Unconfigured package count: '
dpkg -l 2>/dev/null | awk '$1 ~ /^(iU|iF|iH)$/ {n++} END {print n+0}'
section "Broken symlinks in common library paths"
count=0
for root in /lib /lib64 /usr/lib /usr/local/lib; do
  [ -d "$root" ] || continue
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    printf '[BROKEN] %s -> %s\n' "$link" "$(readlink "$link")"
    count=$((count+1))
  done < <(find "$root" -xdev -type l ! -exec test -e {} \; -print 2>/dev/null)
done
[ "$count" -gt 0 ] || echo "[OK] No broken symlinks found in scanned library paths."
section "Dynamic library resolution"
for bin in /usr/bin/msfconsole /usr/bin/psql /usr/lib/postgresql/*/bin/postgres; do
  [ -e "$bin" ] || continue
  if command -v ldd >/dev/null 2>&1; then
    missing="$(ldd "$bin" 2>&1 | grep 'not found' || true)"
    if [ -n "$missing" ]; then printf '[MISSING LIB] %s\n%s\n' "$bin" "$missing"; else printf '[OK] %s\n' "$bin"; fi
  fi
done
section "PostgreSQL / Metasploit"
command -v psql >/dev/null 2>&1 && psql --version || echo "[INFO] psql not installed"
command -v pg_lsclusters >/dev/null 2>&1 && pg_lsclusters || echo "[INFO] pg_lsclusters unavailable"
command -v pg_isready >/dev/null 2>&1 && pg_isready || echo "[INFO] pg_isready unavailable"
command -v msfconsole >/dev/null 2>&1 && msfconsole --version 2>&1 | head -n 2 || echo "[INFO] Metasploit not installed"
echo
echo "Note: Kali documents Metasploit database support as unavailable in NetHunter Rootless."
KALI
}

repair_packages() {
  echo
  echo "This will update Kali package indexes and attempt standard dpkg/APT recovery inside NetHunter."
  echo "It will NOT run full-upgrade, purge packages, recreate clusters, or delete database files."
  printf 'Type YES to continue: '
  IFS= read -r answer || answer=""
  [ "$answer" = "YES" ] || { echo "Cancelled; no repair commands run."; return 0; }
  run_kali <<'KALI'
set +e
export DEBIAN_FRONTEND=noninteractive
echo "== apt-get update =="
apt-get update
update_rc=$?
echo
echo "== dpkg --configure -a =="
dpkg --configure -a
config_rc=$?
echo
echo "== apt-get -f install =="
apt-get -f install
fix_rc=$?
echo
echo "== apt-get check =="
apt-get check
check_rc=$?
printf '\nResults: update=%s configure=%s fix=%s check=%s\n' "$update_rc" "$config_rc" "$fix_rc" "$check_rc"
if [ "$check_rc" -eq 0 ]; then echo "[OK] APT dependency check passed."; else echo "[WARN] APT still reports errors; save this output for troubleshooting."; fi
KALI
}

library_help() {
  echo
  echo "== Library repair guidance =="
  echo "This checks package ownership instead of creating speculative symlinks."
  echo "Run diagnostics first. For a missing library, use the exact path shown by ldd:"
  echo "  dpkg -S /path/to/library"
  echo "Then reinstall the owning package inside Kali:"
  echo "  apt-get install --reinstall PACKAGE_NAME"
  echo
  echo "If dpkg -S cannot find an owner, search Kali packages with:"
  echo "  apt-file search LIBRARY_FILENAME"
  echo "  apt-file must first be installed and updated inside Kali."
  echo
  echo "This toolkit deliberately does not auto-link same-named .so files: matching names"
  echo "do not prove ABI compatibility and a guessed symlink can break more programs."
}

db_check() {
  run_kali <<'KALI'
set +e
echo "== PostgreSQL clusters =="
command -v pg_lsclusters >/dev/null 2>&1 && pg_lsclusters || echo "pg_lsclusters unavailable"
echo
echo "== PostgreSQL readiness =="
command -v pg_isready >/dev/null 2>&1 && pg_isready || echo "pg_isready unavailable"
echo
echo "== Metasploit database helper =="
command -v msfdb >/dev/null 2>&1 && msfdb status || echo "msfdb helper unavailable"
echo
echo "Rootless limitation: Kali documents Metasploit without database support for NetHunter Rootless."
KALI
}

menu() {
  while true; do
    printf '\n'
    echo "1) Run diagnostics (read-only)"
    echo "2) Repair common APT/dpkg problems (asks for YES)"
    echo "3) Check PostgreSQL / Metasploit"
    echo "4) Show library repair guidance"
    echo "5) Open NetHunter shell"
    echo "6) Exit"
    printf 'Choose [1-6]: '
    IFS= read -r choice || choice=6
    case "$choice" in
      1) diagnose ;;
      2) repair_packages ;;
      3) db_check ;;
      4) library_help ;;
      5) nh="$(find_nh)" && "$nh" ;;
      6) exit 0 ;;
      *) echo "Choose a number from 1 to 6." ;;
    esac
  done
}

main() {
  termux_check
  case "${1:-menu}" in
    install) install_nethunter; menu ;;
    diagnose|check) find_nh >/dev/null 2>&1 || install_nethunter; diagnose ;;
    repair) find_nh >/dev/null 2>&1 || install_nethunter; repair_packages ;;
    db-check) find_nh >/dev/null 2>&1 || install_nethunter; db_check ;;
    menu) find_nh >/dev/null 2>&1 || install_nethunter; menu ;;
    help|-h|--help)
      echo "Usage: ./nethunter-toolkit.sh [install|diagnose|repair|db-check|menu]"
      echo "No arguments: install official NetHunter Rootless if missing, then open toolkit menu."
      ;;
    *) echo "Unknown mode: $1"; echo "Use --help for usage."; exit 2 ;;
  esac
}
main "$@"
