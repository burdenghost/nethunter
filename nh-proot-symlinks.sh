#!/data/data/com.termux/files/usr/bin/bash
# NetHunter proot symlink audit/repair launcher.
# Runs in Termux, but inspects the installed Kali filesystem via NetHunter's proot.
set -u

VERSION="0.2.0"
MODE="${1:-check}"
case "$MODE" in
  check|repair|help|-h|--help) ;;
  *) echo "Usage: $0 [check|repair]"; exit 2 ;;
esac
if [ "$MODE" = help ] || [ "$MODE" = -h ] || [ "$MODE" = --help ]; then
  echo "NetHunter Proot Symlink Auditor v$VERSION"
  echo "Usage: $0 [check|repair]"
  echo "  check  Report broken symlinks in Kali library paths (default; read-only)"
  echo "  repair Interactively repair only links with a verified in-root candidate"
  exit 0
fi

if [ -n "${PREFIX:-}" ] && [ -x "$PREFIX/bin/nethunter" ]; then
  NH="$PREFIX/bin/nethunter"
elif command -v nethunter >/dev/null 2>&1; then
  NH="$(command -v nethunter)"
elif command -v nh >/dev/null 2>&1; then
  NH="$(command -v nh)"
else
  echo "[ERROR] NetHunter launcher not found. Install Rootless NetHunter first."
  exit 127
fi

echo "NetHunter Proot Symlink Auditor v$VERSION"
echo "Termux launcher: $NH"
echo "Mode: $MODE"
echo "Target: Kali NetHunter proot (not Termux's own libraries)"
echo

"$NH" -r bash -s -- "$MODE" <<'KALI_SCRIPT'
set -u
MODE="${1:-check}"
export LC_ALL=C

section() { printf '\n== %s ==\n' "$1"; }
section "Kali/proot environment"
if [ -r /etc/os-release ]; then . /etc/os-release; printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"; fi
printf 'Root: '; id
printf 'Architecture: '; dpkg --print-architecture 2>/dev/null || uname -m
printf 'Root filesystem: '; readlink -f / 2>/dev/null || echo /

section "Standard library directory links"
for path in /lib /lib64 /usr/lib /usr/local/lib; do
  if [ -L "$path" ]; then
    target="$(readlink "$path")"
    if [ -e "$path" ]; then printf '[ OK ] %s -> %s\n' "$path" "$target"
    else printf '[BROKEN] %s -> %s\n' "$path" "$target"; fi
  elif [ -d "$path" ]; then
    printf '[ OK ] %s is a directory\n' "$path"
  elif [ -e "$path" ]; then
    printf '[INFO] %s exists but is not a directory/symlink\n' "$path"
  else
    printf '[MISSING] %s\n' "$path"
  fi
done

section "Broken symlinks in common library paths"
roots=(/lib /lib64 /usr/lib /usr/local/lib)
broken_file="$(mktemp)"
trap 'rm -f "$broken_file"' EXIT
for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  find "$root" -xdev -type l ! -exec test -e {} \; -print 2>/dev/null >> "$broken_file"
done
sort -u "$broken_file" -o "$broken_file"
count="$(wc -l < "$broken_file" | tr -d ' ')"
if [ "$count" = 0 ]; then
  echo "[ OK ] No broken symlinks found in scanned library paths."
else
  echo "[WARN] Found $count broken symlink(s):"
  cat "$broken_file"
fi

if [ "$MODE" = "repair" ]; then
  section "Interactive repair"
  echo "No library links will be changed automatically."
  echo "For each broken link, a replacement is offered only when a file with the same basename"
  echo "exists in a standard library directory. This is a heuristic, not proof of ABI compatibility."
  if [ ! -t 0 ]; then
    echo "[ERROR] Interactive terminal required; no changes made."
    exit 1
  fi
  fixed=0
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    name="${link##*/}"
    candidate=""
    for root in /lib /lib64 /usr/lib /usr/local/lib; do
      [ -d "$root" ] || continue
      # Avoid finding the broken link itself; accept only a real file or valid symlink.
      found="$(find "$root" -xdev -name "$name" ! -path "$link" -exec test -e {} \; -print -quit 2>/dev/null)"
      if [ -n "$found" ]; then candidate="$found"; break; fi
    done
    if [ -z "$candidate" ]; then
      echo "[SKIP] $link — no verified same-name candidate found."
      continue
    fi
    echo
    echo "Broken: $link -> $(readlink "$link")"
    echo "Candidate: $candidate"
    printf 'Replace this broken symlink with the candidate above? Type YES: '
    IFS= read -r answer || answer=""
    if [ "$answer" = "YES" ]; then
      # Keep the original link's path; replace only that broken symlink.
      rm -- "$link" && ln -s "$candidate" "$link"
      if [ -e "$link" ]; then echo "[FIXED] $link -> $candidate"; fixed=$((fixed+1))
      else echo "[ERROR] Could not validate replacement for $link"; fi
    else
      echo "[SKIP] Left unchanged."
    fi
  done < "$broken_file"
  echo
  echo "Interactive repairs applied: $fixed"
  echo "Re-run '$0 check' to verify. A same-name candidate may still be ABI-incompatible;"
  echo "review package ownership and reinstall the correct Kali package if errors persist."
fi

section "Next steps"
echo "If a program still reports a missing shared library, run:"
echo "  apt-get update"
echo "  apt-get install --reinstall <package-that-owns-the-library>"
echo "Use 'dpkg -S /path/to/library' to identify the owning package when possible."
echo "This tool does not alter Termux libraries, run full-upgrade, or delete databases."
KALI_SCRIPT
