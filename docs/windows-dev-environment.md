# Windows Development Environment

Guide for developing and testing `butane_flutter` on the Windows half of the
dual-booted Lenovo from the Mac Studio. Sibling to
[`linux-dev-environment.md`](linux-dev-environment.md) — same topology, same
machine, different OS.

> **Read this first if you live in POSIX.** Windows OpenSSH has a handful of
> traps that fail *silently* — wrong key file, unstripped quotes, firewall
> rules that are present but inert. All seven are in
> [Gotchas](#gotchas-the-things-that-fail-silently) below. Skim that section
> before debugging anything; the box is fully set up, so most of what you hit
> from here will be one of them.

## Architecture

```
┌─────────────────────┐         SSH          ┌─────────────────────┐
│     Mac Studio      │ ──────────────────── │   Lenovo (Windows)  │
│                     │                      │                     │
│  • Agent            │   git push / pull    │  • Flutter SDK      │
│  • Source of truth  │ ──────────────────── │  • VS 2022 + MSVC   │
│  • GitHub origin    │                      │  • BLE hardware     │
│                     │   ssh build/test     │  • WinRT / C++      │
└─────────────────────┘                      └─────────────────────┘
```

All development happens on the Mac Studio. The Lenovo is a **build and test
target only** — no agent, no GitHub access, no independent development.

## ⚠️ Dual-boot: one machine, two mutually exclusive states

This is the **same physical laptop** as the Linux target. Ubuntu and Windows
are never up at the same time, so:

- The `linux` and `windows` git remotes address one box in mutually exclusive
  states. Whichever OS is not booted is simply unreachable.
- A Linux burn and a Windows validation **cannot run in the same session**.
- Any automated validation must **preflight which OS is booted** and fail with
  an explicit message, never a confusing MSVC or SSH error. Tracked in the
  Windows epic's validation child.

The box answers ARP while in Windows even when ICMP and TCP are filtered, so
"pings but nothing listens" is not proof it is off — see [Gotchas](#4-icmp-is-dropped-by-default).

## Hardware

| Component | Detail |
|-----------|--------|
| Machine | Lenovo Yoga 7 14ITL5 (model `82BH`) |
| OS | Windows 11 Home, build 22635 (Insider Beta), 64-bit |
| RAM | 11.8 GB |
| Bluetooth | Intel(R) Wireless Bluetooth + Microsoft Bluetooth LE Enumerator |
| Computer name | `nicospencer` |
| Account | `nicospencer\nicks` (local admin) |

Verified 2026-07-25 over SSH.

## Network

- **Address:** `192.168.4.44/22` on `Wi-Fi`
- **Mac Studio:** `192.168.7.223` on `en1`
- **Same subnet:** the mask is a `/22` (`192.168.4.0`–`192.168.7.255`), so
  `.4.44` and `.7.223` are on one L2 network despite the different third octet.
  Do not "fix" this — nothing is misrouted.
- **Gateway / DHCP server:** `192.168.4.1`
- **NIC MAC:** `6c:94:66:ae:49:26`
- **Network profile:** `Private` (required — see [Gotchas](#3-the-network-profile-silently-voids-firewall-rules))

**There is no mDNS.** Windows does not run avahi, and Bonjour only arrives
bundled with Apple software. The Linux half's `nico-yoga-7-14itl5.local` will
**not** resolve while the box is in Windows. Use a pinned address instead.

`~/.ssh/config` on the Mac:

```
Host yoga-win
    HostName 192.168.4.44
    User nicospencer/nicks
```

Then `ssh yoga-win` from the Mac.

> The DHCP lease drifts (`.44` → `.167` → `.168` observed in one week on the
> Linux side). Pin it with a **router-side DHCP reservation** on MAC
> `6c:94:66:ae:49:26` — that is configured on the router at `192.168.4.1`, not
> on Windows. A static IP set on Windows also works, but only if the address
> sits *outside* the router's DHCP pool, or the router will eventually lease it
> to something else and cause an address conflict.

## Setup Checklist

### Completed (2026-07-25)

**Access**
- [x] OpenSSH Server capability installed; `sshd` **Running / Automatic**
- [x] Firewall rule `OpenSSH-Server-In-TCP` — enabled, profile `Any`
- [x] Network profile `Private`; power/sleep timeouts handled
- [x] SSH public-key auth from the Mac (key in `administrators_authorized_keys`)
- [x] `Host yoga-win` entry in the Mac's `~/.ssh/config`
- [x] `DefaultShell` set to PowerShell 7 (`pwsh` 7.4.17)

**Git**
- [x] Bare repo `C:\Users\nicks\butane_flutter.git`, `HEAD` repointed to `main`
- [x] `windows` remote on the Mac with the `uploadpack`/`receivepack` config
      from [gotcha 6](#6-gits-helper-binaries-are-not-on-the-non-interactive-path)
- [x] `git push windows main` verified end to end — box tip matched the Mac,
      `git fsck` clean
- [x] Working copy `C:\Users\nicks\butane_flutter`, on `main`, clean,
      `core.autocrlf=false`

**Deps**
- [x] Router-side DHCP reservation for `6c:94:66:ae:49:26` (operator) — the
      pinned `192.168.4.44` in `~/.ssh/config` is now stable
- [x] `url.https://github.com/.insteadOf git@github.com:` — anonymous fetch of
      the public org repos, no credentials on the box

**Toolchain**
- [x] Git (`C:\Program Files\Git\cmd\git.exe`)
- [x] **Flutter 3.44.8 / Dart 3.12.2** (was 3.10.5 / Dart 3.0.5) — clears
      butane's `sdk: ^3.11.0` and `flutter: ">=3.27.0"` floors. See
      [Upgrading Flutter](#upgrading-flutter).
- [x] Visual Studio Community 2022 **17.2.1**, Desktop C++ workload, Windows
      10 SDK `10.0.19041.0` — `flutter doctor` on 3.44.8 reports
      `[√] Visual Studio - develop Windows apps`; windows-x64 artifacts present

### Remaining
- [ ] `flutter config --enable-windows-desktop`; add Windows runners
      (`flutter create --platforms=windows .`) — no `windows/` directory exists
      anywhere in this repo yet
- [ ] Scaffold the `butane_windows` platform package

### Butane interactive central scheduled task

The bench operator must remain logged on locally while the Windows central
harness runs. The scheduled task runs only with that user's interactive token;
it does not run in the OpenSSH service session. The repository path embedded in
the task action must equal the burn configuration's `windowsRepo`.

For the current `C:\repo` checkout, register the task from elevated
PowerShell:

```powershell
$taskName = 'Butane\InteractiveCentralHarness'
$payload = 'C:\repo\.grid\remote_windows_host_launch.ps1'
$action = New-ScheduledTaskAction `
  -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$payload`""
$principal = New-ScheduledTaskPrincipal `
  -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -RunOnlyIfNetworkAvailable
Register-ScheduledTask `
  -TaskName $taskName `
  -Action $action `
  -Principal $principal `
  -Settings $settings `
  -Force
```

For the attended rendering check, log on locally, start the resident
Windows-central burn, and confirm that the `butane_harness` window is visible
on the box. Then run:

```bash
ssh -o BatchMode=yes yoga-win "powershell.exe -NoProfile -NonInteractive -Command Get-Content C:/repo/.grid/remote_windows_host_launch.log"
```

The output must contain `GRID_VM_URI=ws://` and must contain none of
`EGL Error`, `Surface creation failed`, or `SwapChain`. Absence of a logged-on
interactive user is a hard precondition failure and never falls back to
OpenSSH session 0.

## Gotchas — the things that fail *silently*

### 1. Admin accounts ignore `~/.ssh/authorized_keys`

`nicospencer\nicks` is a local **administrator**, and Windows OpenSSH
deliberately routes admins to a different file. `C:\ProgramData\ssh\sshd_config`
ends with:

```
Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```

So the key must live in `C:\ProgramData\ssh\administrators_authorized_keys`,
**and that file's ACLs must be locked down** or `sshd` refuses it without
logging anything by default.

```powershell
# Elevated PowerShell, at the machine
$k = 'ssh-ed25519 AAAAC3Nza... nico@mac'   # contents of the Mac's ~/.ssh/id_ed25519.pub
Add-Content -Path C:\ProgramData\ssh\administrators_authorized_keys -Value $k
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r `
  /grant 'Administrators:F' /grant 'SYSTEM:F'
Restart-Service sshd
```

**`ssh-copy-id` does not work here** — it pipes a `sh -c` script over SSH, which
`cmd.exe` cannot run, and even on success it would write to the wrong file.
Place the key manually while physically at the machine.

### 2. The default shell is `cmd.exe`

`HKLM:\SOFTWARE\OpenSSH\DefaultShell` is unset, so every remote command lands in
`cmd.exe`. From the Mac that means wrapping everything:

```bash
ssh yoga-win "powershell -NoProfile -Command \"Get-Service sshd\""
```

**This has been done** — `DefaultShell` is set to PowerShell 7, so remote
commands are invoked directly:

```bash
ssh yoga-win '$PSVersionTable.PSVersion.ToString()'   # 7.4.17
```

The registry change, for reference or rebuild:

```powershell
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
  -Value 'C:\Program Files\PowerShell\7\pwsh.exe' -PropertyType String -Force
```

Beyond ergonomics this also fixes the git-over-SSH quoting failure in
[gotcha 6](#6-gits-helper-binaries-are-not-on-the-non-interactive-path).
Existing SSH sessions keep their old shell; only new ones pick it up.

### 3. The network profile silently voids firewall rules

If Windows classifies the wifi as `Public`, rules scoped to `Private` simply do
not apply — with no error anywhere. Check before debugging anything else:

```powershell
Get-NetConnectionProfile
Set-NetConnectionProfile -InterfaceAlias 'Wi-Fi' -NetworkCategory Private
```

Current state is `Private`, and the SSH rule is scoped `Any`, so this is
already safe here.

### 4. ICMP is dropped by default

Windows Firewall blocks echo requests, so `ping` failing proves nothing. Allow
it so the box is diagnosable from the Mac:

```powershell
New-NetFirewallRule -DisplayName 'ICMPv4 Echo Request' -Protocol ICMPv4 `
  -IcmpType 8 -Enabled True -Direction Inbound -Action Allow -Profile Any
```

Until then, the reliable liveness check from the Mac is ARP:

```bash
arp -n 192.168.4.44     # a MAC address means it is up, even if nothing answers
```

### 5. A Windows Hello PIN is not a password

SSH password auth uses the **account** password. If the account is tied to a
Microsoft account, that is the MSA password — the PIN will never authenticate.
Public-key auth sidesteps this entirely, which is why the key is installed
locally rather than pushed with `ssh-copy-id`.

### 6. Git's helper binaries are not on the non-interactive PATH

`git.exe` lives in `C:\Program Files\Git\cmd` and **is** on `PATH`, but
`git-upload-pack.exe` / `git-receive-pack.exe` live in Git's `mingw64\bin`,
which non-interactive SSH sessions do not get. So an interactive login looks
fine while every `git push`/`git fetch` from the Mac dies with:

```
'git-upload-pack' is not recognized as an internal or external command
fatal: Could not read from remote repository.
```

This is **not** a URL-syntax problem — the scp-style form, the `ssh://` form,
and a home-relative path all fail identically.

**There are two independent failures stacked here**, and they have different
fixes. Routing through `git.exe` (which *is* on `PATH`) clears the
missing-binary error, and then you hit the second one:

```
fatal: ''C:/Users/nicks/butane_flutter.git'' does not appear to be a git repository
```

Note the doubled quotes. Git always wraps the repository path in single quotes
for the SSH transport, and **`cmd.exe` does not strip them** — so the path
arrives with literal `'` characters in it. Proof:

```console
$ ssh yoga-win "git upload-pack 'C:/Users/nicks/butane_flutter.git'"
fatal: ''C:/Users/nicks/butane_flutter.git'' does not appear to be a git repository

$ ssh yoga-win "git upload-pack C:/Users/nicks/butane_flutter.git"
0000fatal: the remote end hung up unexpectedly     # 0000 = valid empty-repo handshake
```

So the remote command must run under a shell that *does* parse single quotes.
**`DefaultShell` is now set to PowerShell 7** (see
[gotcha 2](#2-the-default-shell-is-cmdexe)), which handles the quoting — so
only the PATH half needs a Mac-side fix:

```bash
git config remote.windows.uploadpack  "git upload-pack"
git config remote.windows.receivepack "git receive-pack"
```

Verified under `DefaultShell = pwsh`: `git upload-pack 'C:/…'` returns a
normal capability advertisement, i.e. the quotes are stripped correctly.

> **If `DefaultShell` is ever reverted to `cmd.exe`**, the quoting breaks again
> and the config must absorb both problems:
>
> ```bash
> git config remote.windows.uploadpack  "powershell -NoProfile -Command git upload-pack"
> git config remote.windows.receivepack "powershell -NoProfile -Command git receive-pack"
> ```
>
> That form was verified working too, binary pack stream included — a full
> `git push windows main` landed with the box's tip matching the Mac's and
> `git fsck` clean on the bare repo.

> The remaining PATH half could be retired entirely by appending Git's
> `mingw64\bin` to the machine `PATH`, which would fix it for every future
> clone rather than just this one. Deliberately not done — it is a
> system-wide change, and anyone else cloning this repo will need the two
> config lines above until it is.

> The durable alternative is to append Git's `mingw64\bin` to the machine
> `PATH` on the box, which fixes it for every tool and every future clone. That
> is a system-wide change, so it is deliberately *not* the default here — the
> per-remote config lives only in your local clone, and anyone else cloning
> this repo will hit the same wall until they set it too.

### 7. The laptop sleeps, and SSH dies with it

Windows 11 will sleep the machine on idle/battery and drop the network with
it. Symptoms escalate as it goes: `Operation timed out` while it is busy or
dozing, then `Host is down` once it is gone. Observed mid-SDK-download on
2026-07-25.

Before a long remote build, keep it awake — either adjust the power plan, or
hold it open for the session:

```powershell
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
```

Treat a dropped SSH connection during a long operation as "check whether it
slept" before assuming the command failed.

## Firewall reference

```powershell
Get-NetFirewallRule -Name *OpenSSH* | Select Name,DisplayName,Enabled,Profile
Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'

# only if the rule is absent (the capability normally creates it):
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' `
  -Enabled True -Direction Inbound -Protocol TCP -Action Allow `
  -LocalPort 22 -Profile Any
```

## Git Topology

```
GitHub (origin)
    ↑
Mac Studio repo: ~/development/com.nicospencer/butane_flutter
    ↓ (SSH remote)
Lenovo/Windows repo: C:\Users\nicks\butane_flutter
```

- **Mac** is the source of truth and pushes to GitHub, `linux`, and `windows`
- **Lenovo** is a read-only build target from git's perspective
- No GitHub credentials on the box

```bash
# From the Mac, once the bare repo exists on the box
git remote add windows yoga-win:C:/Users/nicks/butane_flutter.git

# REQUIRED — see gotcha 6. Without these, every push/fetch fails, first with
# "'git-upload-pack' is not recognized", then on literal quotes in the path.
git config remote.windows.uploadpack  "powershell -NoProfile -Command git upload-pack"
git config remote.windows.receivepack "powershell -NoProfile -Command git receive-pack"

git push windows main
```

The bare repo is created by `git init --bare`, which leaves `HEAD` pointing at
`master`. Repoint it so clones check out `main`:

```powershell
git -C C:\Users\nicks\butane_flutter.git symbolic-ref HEAD refs/heads/main
```

```powershell
# On the box, initial setup
git init --bare C:\Users\nicks\butane_flutter.git
git clone C:\Users\nicks\butane_flutter.git C:\Users\nicks\butane_flutter
```

> Use forward slashes in the git remote path. Set `core.autocrlf=false` on the
> box — this repo is LF and CRLF translation will produce spurious diffs.

## Upgrading Flutter

fvm's `default` is a symlink to `versions\stable`, which is an ordinary Flutter
**git checkout on the `stable` branch** — so it upgrades with git, not with an
installer.

The obvious command does not work:

```
git pull --ff-only
fatal: Not possible to fast-forward, aborting.
```

That is expected, not damage. Flutter cuts stable *releases* as cherry-pick
branches, so a release tag is not an ancestor of the moving `stable` branch —
this checkout measured **31 ahead / 54,868 behind** `origin/stable` while
sitting on tag `3.10.5`. There is nothing to preserve in an SDK cache, so reset
onto the branch:

```powershell
cd C:\Users\nicks\fvm\versions\stable
git status --porcelain          # confirm clean first
git fetch origin --tags
git reset --hard origin/stable
.\bin\flutter.bat --version     # triggers the engine + Dart SDK download
```

The artifact download is ~1–2 GB and saturates the machine; SSH may time out
while it runs, and the laptop may sleep partway through
([gotcha 7](#7-the-laptop-sleeps-and-ssh-dies-with-it)). Run it detached and
re-probe rather than assuming failure.

To pin an exact version alongside instead of moving `stable` — e.g. to match
the Linux half — use `fvm install <version>` and `fvm global <version>`. Note
that an interrupted `fvm install` leaves a partial directory under
`versions\`; clear it with `fvm remove <version>` before retrying.

## Dependency resolution — fully hosted

Published org dependencies are ordinary hosted constraints in package
pubspecs, and the Windows environment resolves fully from hosted releases.
`grid_assets 0.1.0` and `leonard_flutter 0.1.8` have crossed the release
boundaries that previously required local overrides. Do not run `grid dart link`
and do not restore sibling-checkout paths.

`genesis_perception 0.1.3` and `genesis_tree 0.1.5` are published and
compatible. `grid_cli` resolves hosted at ^0.2.0; other directly imported
published Grid packages resolve hosted at ^0.1.0.

The Grid descriptors must retain their upstream `git@github.com:` URLs so pub
can unify them. Because the repositories are public, redirect transport
anonymously on a machine without an org SSH key:

```powershell
git config --global url."https://github.com/".insteadOf "git@github.com:"
```

## Build Workflow

```bash
# From the Mac — push, then build remotely
git push windows main
ssh yoga-win "powershell -NoProfile -Command \"cd C:\Users\nicks\butane_flutter; flutter build windows\""
```

`cmake` and `ninja` are **not** on `PATH`, and that is fine — Flutter uses the
copies bundled inside the Visual Studio installation for Windows desktop builds.

## Toolchain

| Tool | State |
|------|-------|
| Git | `C:\Program Files\Git\cmd\git.exe` |
| Flutter | `C:\Users\nicks\fvm\default\bin\flutter.bat` — **3.44.8** (stable) |
| Dart | 3.12.2 (via Flutter) |
| Visual Studio | Community 2022 17.2.1, Desktop C++ workload ✓ |
| Windows SDK | `10.0.19041.0` |
| PowerShell 7 | `C:\Program Files\PowerShell\7\pwsh.exe` |
| cmake / ninja | Not on `PATH` — supplied by VS |

## Why Windows needs a native C++ plugin

Unlike Linux — where `butane_bluez` is a 16-line Dart-only shim over the pure
Dart `butane_dart_bluez` — Windows requires a real C++/WinRT plugin. D-Bus is a
*wire protocol* Dart speaks over a socket; WinRT is an *in-process COM ABI*.
The Dart WinRT projection stack (`windows_devices` / `windows_foundation`) was
archived in September 2024, and `ffigen` parses C, not C++.

Full reasoning, the interface mismatches, and the decomposition live on the
Windows epic in the bead store.
