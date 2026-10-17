# NetHunter One-Stop Installer & Repair Toolkit

A single Bash script for **Termux** that installs official Kali NetHunter Rootless when it is not already installed, then provides a menu to diagnose and repair common problems **inside the Kali proot environment**.

## One-line install and launch

Paste this into Termux:

```bash
pkg install -y git && git clone https://github.com/burdenghost/nethunter.git && cd nethunter && chmod +x nethunter-toolkit.sh && ./nethunter-toolkit.sh
```

If you already cloned the repository, update and launch it with:

```bash
cd nethunter && git pull && chmod +x nethunter-toolkit.sh && ./nethunter-toolkit.sh
```

## What the script does

1. Detects whether the `nethunter` / `nh` launcher already exists.
2. If it is missing, installs minimal Termux prerequisites and downloads/runs the **official Kali NetHunter Rootless installer** from `https://offs.ec/2MceZWr`. The official installer remains interactive.
3. Once NetHunter exists, opens a menu that runs checks and repair commands inside Kali via `nethunter -r`—not against Termux's own libraries.

### Menu features

- **Diagnostics:** APT/dpkg state, free space, broken symlinks in common library directories, dynamic linker errors for installed Metasploit/PostgreSQL binaries, and PostgreSQL/Metasploit availability.
- **APT/dpkg repair:** after you type `YES`, runs `apt-get update`, `dpkg --configure -a`, `apt-get -f install`, and an APT dependency check inside Kali.
- **Database checks:** PostgreSQL cluster/readiness checks and Metasploit database-helper status.
- **Library repair guidance:** helps identify the owning package so the correct library can be reinstalled rather than guessing a symlink target.
- **NetHunter shell:** opens the installed Kali environment.

## Command-line modes

```bash
./nethunter-toolkit.sh              # install if missing, then open menu
./nethunter-toolkit.sh install      # install if missing, then open menu
./nethunter-toolkit.sh diagnose     # read-only checks (installs first if missing)
./nethunter-toolkit.sh repair       # interactive APT/dpkg repair
./nethunter-toolkit.sh db-check     # PostgreSQL/Metasploit checks
./nethunter-toolkit.sh --help
```

## Safety and limitations

- The script skips installation if a NetHunter launcher is already present; it does not overwrite an existing root filesystem.
- The repair mode requires explicit `YES` confirmation.
- It does not run `full-upgrade`, purge packages, delete PostgreSQL data, recreate clusters, or create speculative library symlinks.
- A same-named shared library is not necessarily ABI-compatible. Prefer identifying the package owner with `dpkg -S /path/to/library` and reinstalling that package.
- **Rootless limitation:** Kali's official documentation lists Metasploit without database support for NetHunter Rootless. The toolkit can diagnose PostgreSQL and package state, but cannot enable a feature that the Rootless edition does not support.

## Official references

- [Kali NetHunter Rootless installation and usage](https://www.kali.org/docs/nethunter/nethunter-rootless/)
- [NetHunter edition comparison](https://www.kali.org/docs/nethunter/)

## Other scripts

The repository retains `nh-repair.sh` and `nh-proot-symlinks.sh` as standalone legacy utilities. For the combined install-and-maintenance workflow, use `nethunter-toolkit.sh`.

## Version

1.0.0 — unified Termux installer and Kali proot diagnostics/repair menu.
