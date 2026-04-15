# Platform: iOS
- UDID: `flutter devices` or `ios-deploy -c --timeout 5` (the 40-char `00008110-...` format). Note `xcrun devicectl list devices` shows **CoreDevice UUIDs** (`D9EBF582-...`), a distinct identifier used only by `devicectl` — `run_harness.sh` auto-resolves that from the UDID.
- Build: `flutter build ios --release --dart-define=ROLE=peripheral --dart-define=WS_PORT=19101` (iOS can't read env vars via `open`).
- Install: `ios-deploy --bundle build/ios/iphoneos/Runner.app --id <UDID> --uninstall --no-wifi`.
- Launch: `xcrun devicectl device process launch --device <UDID> --terminate-existing com.nicospencer.butaneHarness`.
- Coordinator discovers the iPad via mDNS (harness advertises `_butane-harness._tcp` via `nsd`); ensure iPad + Mac share a LAN with multicast enabled.
