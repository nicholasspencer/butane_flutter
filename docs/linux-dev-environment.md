# Linux Development Environment

Guide for developing and testing `butane_flutter` on a remote Linux machine from the Mac Studio.

## Architecture

```
┌─────────────────────┐         SSH          ┌─────────────────────┐
│     Mac Studio      │ ──────────────────── │   Linux Laptop      │
│                     │                      │                     │
│  • Agent (Chad)     │   git push / pull    │  • Flutter SDK      │
│  • Source of truth  │ ──────────────────── │  • Build target     │
│  • GitHub origin    │                      │  • BLE hardware     │
│                     │   ssh build/test     │  • BlueZ 5.72       │
│                     │ ──────────────────── │                     │
└─────────────────────┘                      └─────────────────────┘
```

All development happens on the Mac Studio. The Linux laptop is a **build and test target only** — no agent, no GitHub access, no independent development.

## Hardware

| Component | Detail |
|-----------|--------|
| Machine | Lenovo Yoga 7 14ITL5 |
| OS | Ubuntu 24.04.4 LTS (Noble) |
| Kernel | 6.8.0-107-generic |
| BlueZ | 5.72 |
| Bluetooth | Built-in radio |
| Flutter | 3.24.4 (stable) |

## Network

- **Laptop SSH:** `nico@nico-yoga-7-14itl5.local` (mDNS — resolves via avahi, survives DHCP drift)
- **Mac Studio:** `192.168.4.179` (en1, WiFi)
- **Auth:** ED25519 key from Mac Studio (passwordless)

> **Note:** Always prefer the `.local` mDNS hostname over raw IPs — the laptop's DHCP lease drifts (observed `.44` → `.167` → `.168` in a single week). mDNS Just Works as long as both machines are on the same LAN and `avahi-daemon` is running on the laptop (enabled by default on Ubuntu).

## Setup Checklist

### Completed (2026-04-03)
- [x] Ubuntu 24.04 LTS installed (upgraded from 20.04)
- [x] `openssh-server` installed and enabled
- [x] SSH key auth from Mac Studio → laptop
- [x] Flutter SDK installed (`~/flutter`, in PATH)
- [x] Linux build toolchain: clang 18, cmake 3.28, ninja 1.11, pkg-config
- [x] BLE dev headers: `libdbus-1-dev`, `libbluetooth-dev`
- [x] Git configured

### Completed (2026-04-03, evening session)
- [x] Mac Studio LAN IP: 192.168.4.179 (en1, WiFi)
- [x] Bare repo on laptop: `~/butane_flutter.git`
- [x] Working copy on laptop: `~/butane_flutter` (cloned from bare)
- [x] Git remote `linux` added on Mac Studio → `nico@nico-yoga-7-14itl5.local:~/butane_flutter.git`
- [x] Pushed `main` to laptop
- [x] Flutter upgraded to 3.41.6 (stable)
- [x] Linux platform enabled on `butane_harness` (`flutter create --platforms=linux .`)
- [x] **First `flutter build linux` succeeded** → `build/linux/x64/release/bundle/butane_harness`

### Remaining
- [ ] Scaffold `butane_linux` platform package (BlueZ/D-Bus implementation)
- [x] IP drift worked around via mDNS (`nico-yoga-7-14itl5.local`). DHCP reservation no longer urgent — file a bead if we ever need a stable IP for a service that can't do mDNS.
- [ ] Cross-platform BLE test harness (macOS Central ↔ Linux Peripheral)

## Git Topology

```
GitHub (origin)
    ↑
Mac Studio repo: ~/development/com.nicospencer/butane_flutter
    ↓ (SSH remote)
Linux laptop repo: ~/butane_flutter (or similar)
```

- **Mac** is the source of truth and pushes to both GitHub and the laptop
- **Laptop** is a read-only build target (from git's perspective)
- No GitHub credentials needed on the laptop

### Setting Up the Remote (once IPs are confirmed)

From Mac Studio:
```bash
# Add laptop as a remote
cd ~/development/com.nicospencer/butane_flutter
git remote add linux nico@nico-yoga-7-14itl5.local:~/butane_flutter.git

# Push a branch to the laptop
git push linux main
```

From laptop (initial bare repo setup):
```bash
git init --bare ~/butane_flutter
# Or clone from Mac:
git clone nico@<mac-ip>:~/development/com.nicospencer/butane_flutter
```

## Build Workflow

```bash
# From Mac Studio — push latest code and build
git push linux main
ssh nico@nico-yoga-7-14itl5.local "cd ~/butane_flutter && export PATH=\$HOME/flutter/bin:\$PATH && flutter build linux"
```

## Dependencies Installed

```bash
# Flutter Linux build deps
clang cmake ninja-build libgtk-3-dev pkg-config liblzma-dev libstdc++-12-dev

# BlueZ / D-Bus
libdbus-1-dev libbluetooth-dev

# Utilities
git curl unzip xz-utils zip screen
```
