#!/usr/bin/env bash
# Validate the Windows platform implementation on the remote build target.
#
# Run from the Mac. Pushes the current branch to the `windows` remote, then
# resolves, analyzes, and tests over SSH — including the C++ googletests, which
# only build as part of the example (windows/CMakeLists.txt gates the
# butane_windows_test target on include_butane_windows_tests).
#
# This is the validation_plan for the Windows epic's build children. It covers
# compile + unit level only; BLE behaviour still needs a human with two radios.
#
# Host comes from BUTANE_WINDOWS_HOST (default: the yoga-win alias documented in
# docs/windows-dev-environment.md). Remote checkout from BUTANE_WINDOWS_REPO.
set -euo pipefail

# Every failure says which step failed and why — the lesson from
# butane_flutter-43j, where bare `set -e` exits left the operator bisecting the
# script by hand.
trap 'echo "validate_windows.sh: FAILED at line $LINENO" >&2' ERR

HOST="${BUTANE_WINDOWS_HOST:-yoga-win}"
REPO="${BUTANE_WINDOWS_REPO:-C:/Users/nicks/butane_flutter}"
FLUTTER="${BUTANE_WINDOWS_FLUTTER:-C:/Users/nicks/fvm/versions/stable/bin/flutter.bat}"
REMOTE="${BUTANE_WINDOWS_REMOTE:-windows}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

step() { echo; echo "==> $*"; }
die() { echo "validate_windows.sh: $*" >&2; exit 1; }

# Run a PowerShell command on the box. DefaultShell is pwsh, so no wrapping.
remote() { ssh -o BatchMode=yes -o ConnectTimeout=15 "$HOST" "$@"; }

# ── Preflight ───────────────────────────────────────────────────────────────

step "Preflight: local tooling"
for tool in git ssh; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

step "Preflight: $HOST reachable over SSH"
if ! remote "exit 0" >/dev/null 2>&1; then
  die "cannot reach '$HOST' over SSH.
  The Lenovo is DUAL-BOOTED — it may be powered off, booted into Ubuntu, or
  asleep. Note that ICMP is dropped by default on Windows, so a failed ping
  proves nothing; ARP is the reliable liveness check:
      arp -n 192.168.4.44     # a MAC address means it is up
  See docs/windows-dev-environment.md."
fi

step "Preflight: the box is booted into Windows"
# The dual-boot trap: Ubuntu also runs sshd on this machine, so a successful
# connection does NOT mean we are on the Windows half. Fail with a plain
# sentence rather than letting MSVC or flutter produce something cryptic.
os_platform="$(remote '[System.Environment]::OSVersion.Platform' 2>/dev/null || true)"
if [[ "$os_platform" != *"Win32NT"* ]]; then
  die "'$HOST' answered but is NOT running Windows (OSVersion.Platform='${os_platform:-<none>}').
  The Lenovo is almost certainly booted into Ubuntu. Reboot it into Windows,
  or run the Linux validation instead. A Linux burn and a Windows validation
  cannot share a session — see docs/windows-dev-environment.md."
fi

step "Preflight: remote checkout exists"
remote "if (-not (Test-Path '$REPO')) { exit 1 }" \
  || die "no checkout at '$REPO' on $HOST. Create it per the Git Topology section of docs/windows-dev-environment.md."

step "Preflight: remote Flutter is present"
remote "if (-not (Test-Path '$FLUTTER')) { exit 1 }" \
  || die "no Flutter at '$FLUTTER' on $HOST. Override with BUTANE_WINDOWS_FLUTTER, or install per docs/windows-dev-environment.md."

# ── Sync ────────────────────────────────────────────────────────────────────

branch="$(git rev-parse --abbrev-ref HEAD)"
head_sha="$(git rev-parse HEAD)"

step "Pushing '$branch' ($(git rev-parse --short HEAD)) to '$REMOTE'"
git push --force-with-lease "$REMOTE" "HEAD:refs/heads/$branch" >/dev/null 2>&1 \
  || die "push to '$REMOTE' failed.
  If this is 'git-upload-pack is not recognized', the per-remote config is
  missing — see gotcha 6 in docs/windows-dev-environment.md:
      git config remote.$REMOTE.uploadpack  \"git upload-pack\"
      git config remote.$REMOTE.receivepack \"git receive-pack\""

step "Checking out $head_sha on $HOST"
remote "cd '$REPO'; git fetch origin 2>&1 | Out-Null; git checkout --detach $head_sha 2>&1 | Out-Null; git reset --hard $head_sha 2>&1 | Out-Null; git rev-parse HEAD" \
  | grep -q "$head_sha" || die "remote checkout did not land on $head_sha"

# ── Validate ────────────────────────────────────────────────────────────────

step "flutter pub get (workspace)"
remote "cd '$REPO'; & '$FLUTTER' pub get 2>&1 | Select-Object -Last 20"

step "flutter analyze (packages/butane_windows)"
# Scoped deliberately: the workspace does not analyze clean as a whole while
# butane_grid_assets still imports the removed grid_controller/grid_federation
# (butane_flutter-7ol). Widen this once that lands.
remote "cd '$REPO/packages/butane_windows'; & '$FLUTTER' analyze 2>&1 | Select-Object -Last 20"

step "flutter test (Dart — packages/butane_windows)"
remote "cd '$REPO/packages/butane_windows'; & '$FLUTTER' test 2>&1 | Select-Object -Last 20"

step "Building the example (this is what compiles the C++ unit tests)"
remote "cd '$REPO/packages/butane_windows/example'; & '$FLUTTER' build windows --debug 2>&1 | Select-Object -Last 20"

step "Running the C++ googletests (butane_windows_test)"
remote "cd '$REPO/packages/butane_windows/example'; \
  \$exe = Get-ChildItem -Path build -Recurse -Filter butane_windows_test.exe -ErrorAction SilentlyContinue | Select-Object -First 1; \
  if (-not \$exe) { Write-Error 'butane_windows_test.exe not found under build/ — the test target did not build. Check that include_butane_windows_tests is set by the example build.'; exit 1 }; \
  & \$exe.FullName; exit \$LASTEXITCODE"

echo
echo "==> validate_windows.sh: PASS ($head_sha on $HOST)"
echo "    Compile + unit level only. BLE behaviour still needs two real radios."
