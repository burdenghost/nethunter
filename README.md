# NetHunter Repair & Diagnostics

A Bash maintenance helper designed to be launched **from Termux** for an existing Kali NetHunter Rootless installation. Termux is the control layer; package and service diagnostics run inside the Kali environment through the installed `nethunter` / `nh` launcher.

## Features

- Read-only checks for APT/dpkg health and incomplete package configuration
- Basic dynamic-library checks for installed Metasploit/PostgreSQL binaries
- PostgreSQL client, cluster, and readiness checks
- Metasploit installation and database-helper checks
- Optional, interactive APT repair using `apt-get update`, `dpkg --configure -a`, and `apt-get -f install`
- No automatic package purges, database deletion, cluster recreation, or PostgreSQL data resets

## Requirements

- Termux
- Kali NetHunter Rootless already installed and launchable as `nethunter` or `nh`
- Internet connection for the optional repair mode

No extra Termux packages are required by the script itself. It uses Bash and the existing NetHunter launcher.

## Usage

From the repository directory in Termux:

```bash
chmod +x nh-repair.sh

# Read-only diagnostics (default)
./nh-repair.sh

# Focused database and Metasploit diagnostics
./nh-repair.sh db-check

# Interactive package-manager repair
./nh-repair.sh repair
```

The repair mode asks you to type `YES` before changing package state. Read the output and warnings; do not interrupt package configuration unless necessary.

## Important limitation

This script can diagnose general APT/dpkg dependency problems and attempt safe package-manager recovery. It cannot make unsupported features supported: Kali's official Rootless documentation lists Metasploit with database support as unavailable in NetHunter Rootless. PostgreSQL may be installed and running while Metasploit database integration remains unsupported in this edition.

- [Official NetHunter Rootless documentation](https://www.kali.org/docs/nethunter/nethunter-rootless/)
- [Kali NetHunter overview and edition comparison](https://www.kali.org/docs/nethunter/)

## Safety notes

- Run diagnostics first and keep the output.
- The repair mode can install/configure packages and therefore may change the Kali root filesystem.
- The script does not remove PostgreSQL clusters, delete database files, purge packages, or run `full-upgrade` automatically.
- It has not yet been executed against your live NetHunter installation; run diagnostics first and share the output if any errors remain.

## Version

0.1.0 — initial Termux-focused diagnostics and conservative APT repair.
