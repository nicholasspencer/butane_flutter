# Platform: iOS
- UDID: `xcrun devicectl list devices` (connected row).
- Build: `flutter build ios --release --dart-define=ROLE=peripheral --dart-define=WS_PORT=19101` (iOS can't read env vars via `open`).
- Install: `ios-deploy --bundle build/ios/iphoneos/Runner.app --id <UDID> --uninstall --no-wifi`.
- Launch: `xcrun devicectl device process launch --device <UDID> --terminate-existing com.nicospencer.butaneHarness`.
- Coordinator must reach iPad directly: supply `PERIPHERAL_HOST=<iPad LAN IP>`.
